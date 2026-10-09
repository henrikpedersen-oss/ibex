// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "spike_cosim.h"

#include <algorithm>
#include <cassert>
#include <iostream>
#include <sstream>
#include <vector>

#include "riscv/config.h"
#include "riscv/debug_rom_defines.h"
#include "riscv/decode.h"
#include "riscv/devices.h"
#include "riscv/log_file.h"
#include "riscv/mmu.h"
#include "riscv/processor.h"
#include "riscv/simif.h"

// For a short time, we're going to support building against version
// ibex-cosim-v0.2 (20a886c) and also ibex-cosim-v0.3 (9af9730). Unfortunately,
// they've got different APIs and spike doesn't expose a version string.
//
// However, a bit of digging around finds some defines that have been added
// between the two versions.
//
// TODO: Once there's been a bit of a window to avoid a complete flag day,
//       remove this ugly hack!
#ifndef HGATP_MODE_SV57X4
#define OLD_SPIKE
#endif

#ifndef OLD_SPIKE
#include "riscv/isa_parser.h"
#endif

SpikeCosim::SpikeCosim(const std::string &isa_string, uint32_t start_pc,
                       uint32_t start_mtvec, const std::string &trace_log_path,
                       bool secure_ibex, bool icache_en,
                       uint32_t pmp_num_regions, uint32_t pmp_granularity,
                       uint32_t mhpm_counter_num, uint32_t dm_start_addr,
                       uint32_t dm_end_addr)
    : nmi_mode(false),
      pending_iside_error(false),
      pending_irq_early_handle(false),
      pending_irq_pre_mip(0),
      deferred_dut_writes_pc(0),
      insn_cnt(0),
      mhpm_counter_num(mhpm_counter_num) {
  FILE *log_file = nullptr;
  if (trace_log_path.length() != 0) {
    log = std::make_unique<log_file_t>(trace_log_path.c_str());
    log_file = log->get();
  }

#ifdef OLD_SPIKE
  processor =
      std::make_unique<processor_t>(isa_string.c_str(), "MU", DEFAULT_VARCH,
                                    this, 0, false, log_file, std::cerr);
#else

#ifdef COSIM_SIGSEGV_WORKAROUND
  isa_parser = new isa_parser_t(isa_string.c_str(), "MU");
  processor = std::make_unique<processor_t>(isa_parser, DEFAULT_VARCH, this, 0,
                                            false, log_file, std::cerr);
#else
  isa_parser = std::make_unique<isa_parser_t>(isa_string.c_str(), "MU");
  processor = std::make_unique<processor_t>(
      isa_parser.get(), DEFAULT_VARCH, this, 0, false, log_file, std::cerr);
#endif

#endif

  processor->set_pmp_num(pmp_num_regions);
  processor->set_mhpm_counter_num(mhpm_counter_num);
  processor->set_pmp_granularity(1 << (pmp_granularity + 2));
  processor->set_ibex_flags(secure_ibex, icache_en);
  processor->set_debug_module_range(dm_start_addr, dm_end_addr);

  initial_proc_setup(start_pc, start_mtvec, mhpm_counter_num);

  if (log) {
    processor->set_debug(true);
    processor->enable_log_commits();
  }
}

// always return nullptr so all memory accesses go via mmio_load/mmio_store
char *SpikeCosim::addr_to_mem(reg_t addr) { return nullptr; }

bool SpikeCosim::mmio_load(reg_t addr, size_t len, uint8_t *bytes) {
  bool bus_error = !bus.load(addr, len, bytes);

  bool dut_error = false;

  // Incoming access may be an iside or dside access. Use PC to help determine
  // which. PC is 64 bits in spike, we only care about the bottom 32-bit so mask
  // off the top bits.
  uint64_t pc = processor->get_state()->pc & 0xffffffff;
  uint32_t aligned_addr = addr & 0xfffffffc;

  if (pending_iside_error && (aligned_addr == pending_iside_err_addr)) {
    // Check if the incoming access is subject to an iside error, in which case
    // assume it's an iside access and produce an error.
    pending_iside_error = false;
    dut_error = true;
  } else {
    // Spike may attempt to access up to 8-bytes from the PC when fetching, so
    // only check as a dside access when it falls outside that range.
    //
    // This is a heuristic and it misfires when a *data* load happens to target
    // an address within 8 bytes of the PC -- which is exactly what happens once
    // a test runs off into garbage and starts executing data. In
    // riscv_assorted_traps_interrupts_debug_test.21576 a `c.lbu s0, 0(s0)` at pc
    // 0x46 loaded from 0x4a, so the load was silently treated as an ifetch, the
    // DUT's matching bus access was never popped from pending_dside_accesses,
    // and it then collided with the next genuine access -- surfacing as a
    // spurious "store at address 3d463f3c was expected but there are no pending
    // accesses" plus a manufactured trap.
    //
    // Narrow it using instruction width: RISC-V instructions are 2 or 4 bytes,
    // so no instruction fetch is ever a single byte. That is exactly what the
    // .21576 case was -- a `c.lbu`, len 1 -- and byte loads are the common way
    // a runaway program reads its own code region.
    //
    // Narrower still: Spike fetches one 16-bit parcel per mmio_load
    // (mmu_t::fetch_slow_path reads sizeof(uint16_t fetch_temp)), so every
    // fetch has len 2 and a word access is always data. pmp_fault_hazard's
    // `lw t1, 0(t0)` at pc 0x800022d0 reads 0x800022d4 = pc + 4 on purpose;
    // taken for a fetch, its DUT access stayed queued and failed the next
    // access on every seed (2026-10-08). Still ambiguous: a halfword load from
    // [pc, pc + 8), which needs a fetch/data flag from Spike to close.
    bool in_iside_range = (addr >= pc) && (addr < pc + 8) && (len == 2);

    if (!in_iside_range) {
      dut_error = (check_mem_access(false, addr, len, bytes) != kCheckMemOk);
    }
  }

  return !(bus_error || dut_error);
}

bool SpikeCosim::mmio_store(reg_t addr, size_t len, const uint8_t *bytes) {
  bool bus_error = !bus.store(addr, len, bytes);
  // If the RTL produced a bus error for the access, or the checking failed
  // produce a memory fault in spike.
  bool dut_error = (check_mem_access(true, addr, len, bytes) != kCheckMemOk);

  return !(bus_error || dut_error);
}

void SpikeCosim::proc_reset(unsigned id) {}

const char *SpikeCosim::get_symbol(uint64_t addr) { return nullptr; }

void SpikeCosim::add_memory(uint32_t base_addr, size_t size) {
  auto new_mem = std::make_unique<mem_t>(size);
  bus.add_device(base_addr, new_mem.get());
  mems.emplace_back(std::move(new_mem));
}

bool SpikeCosim::backdoor_write_mem(uint32_t addr, size_t len,
                                    const uint8_t *data_in) {
  return bus.store(addr, len, data_in);
}

bool SpikeCosim::backdoor_read_mem(uint32_t addr, size_t len,
                                   uint8_t *data_out) {
  return bus.load(addr, len, data_out);
}

// When we call processor->step(), spike advances to the next pc IFF a trap does
// not occur. If a trap does occur, state.last_inst_pc is set to PC_INVALID, and
// we need to call step() again to actually execute the first instruction of the
// trap handler.
// This sentinel value PC_INVALID of state.last_inst_pc allows the cosimulation
// testbench to detect when spike is in this transient state, where we have
// attempted to step but have taken a trap instead and not actually executed
// another instruction.
//
// The flow of spike goes something like this...
// - Start of processor_t::step()
//   Set state.last_inst_pc to PC_INVALID. This is only set back to a
//   non-sentinel valid pc if the processor is able to completely execute the
//   next instruction. It is set back to a valid pc at the end of
//   execute_insn().
// - When calling execute_insn(), we try/except the fetch.func(), which
//   eventually calls one of the templated instructions in insn_template.cc.
//   These functions return the npc. From fetch.func(), we expect to catch
//   the exceptions (wait_for_interrupt_t, mem_trap_t&), which don't finish
//   executing the insn, but do result in printing to the log and re-throwing
//   the exception to be caught up one level by the step() function.
// - In step(), while trying to execute an instruction (down either the
//   fast/slow paths), we can catch an exception (trap_t&, triggers::matched_t&,
//   wait_for_interrupt_t), which means the pc never gets advanced. The pc only
//   gets advanced right at the end of the main paths if nothing goes awry (In
//   the macro advance_pc()).
//   The state.last_inst_pc also remains with the sentinel value PC_INVALID.
// - If we catch a trap_t&, then the take_trap() fn updates the state of the
//   processor, and when we call step() again we start executing in the new
//   context of the trap (trap handler, new MSTATUS, debug rom, etc. etc.)
bool SpikeCosim::step(uint32_t write_reg, uint32_t write_reg_data, uint32_t pc,
                      bool intr, bool sync_trap, bool suppress_reg_write, bool more_ops) {
  assert(write_reg < 32);

  // Consume any deferred interrupt handle.  set_mip() sets this flag when the
  // enabled-IRQ bits transition 0->nonzero rather than calling
  // early_interrupt_handle() directly, because a level-sensitive IRQ can be
  // withdrawn while the DUT's controller sits in IRQ_TAKEN (handle_irq=0),
  // and calling early_interrupt_handle() for an interrupt the DUT abandoned
  // causes a PC mismatch.
  //
  // rvfi_intr is the definitive signal: the DUT sets it on the first
  // instruction of any trap handler.  If it is set with no sync_trap, the DUT
  // entered an async (interrupt) handler and Spike must take it too.  If it is
  // clear, the DUT resumed normal execution and the IRQ was abandoned.
  //
  // Normally Spike takes a pending interrupt itself inside step(1). Not when the DUT also took a
  // debug request before the handler's first instruction (rvfi_intr on the debug ROM's first
  // instruction): by now set_debug_req() has reached Spike, which ranks halt_request above
  // interrupts. So take the interrupt here, with the halt masked, whenever set_mip() deferred one
  // OR a halt is pending; the step below then enters debug from the handler, as the DUT did.
  // set_mip()'s 0->1 test misses an interrupt that was already pending, e.g. in a handler that
  // mret'ed (riscv_assorted_traps_interrupts_debug_test 28613, 2026-10-09). Use the mip the DUT
  // reported when it took the trap, not this item's: a later debug capture samples mip again after
  // a short pulse dropped (riscv_mem_error_traps_test 28610). rvfi_intr is only set for
  // EXC_PC_IRQ, never for a plain debug entry, and an NMI already set nmi_mode.
  if (!more_ops) {
    if (intr && !sync_trap && !processor->get_state()->debug_mode && !nmi_mode &&
        (pending_irq_early_handle || processor->halt_request != processor_t::HR_NONE)) {
      const reg_t item_pre_mip = processor->get_state()->mip->read_pre_val();
      if (pending_irq_early_handle) {
        processor->get_state()->mip->write_pre_val(pending_irq_pre_mip);
      }
      const bool taken = take_irq_before_halt();
      processor->get_state()->mip->write_pre_val(item_pre_mip);
      pending_irq_early_handle = false;
      if (!taken) {
        return false;
      }
    }
    pending_irq_early_handle = false;
  }

  // The DUT has just produced an RVFI item
  // (parameters of this func is the data in the RVFI item).

  // Non-final operation of an expanded instruction: record the DUT's register
  // write and return WITHOUT stepping the ISS. See deferred_dut_writes in
  // spike_cosim.h for why the step has to wait for the final operation.
  if (more_ops) {
    if (!deferred_dut_writes.empty() && pc != deferred_dut_writes_pc) {
      std::stringstream err_str;
      err_str << "DUT retired pc " << std::hex << pc
              << " as part of an expanded instruction while " << std::dec
              << deferred_dut_writes.size()
              << " operation(s) from pc " << std::hex << deferred_dut_writes_pc
              << " were still outstanding";
      errors.emplace_back(err_str.str());
      deferred_dut_writes.clear();
      return false;
    }
    deferred_dut_writes.push_back({write_reg, write_reg_data});
    deferred_dut_writes_pc = pc;
    insn_cnt++;
    return true;
  }

  // A trap part-way through an expanded instruction ends it. Spike commits each
  // cm.pop load as it goes and does not roll back, so the operations already
  // retired leave the same registers on both sides; nothing is left to match.
  if (sync_trap) {
    deferred_dut_writes.clear();
  }

  uint32_t initial_spike_pc;
  uint32_t suppressed_write_reg;
  uint32_t suppressed_write_reg_data;
  bool pending_sync_exception = false;

  if (suppress_reg_write) {
    // If Ibex suppressed a register write (which occurs when a load gets data
    // with bad integrity) record the state of the destination register before
    // we do the stop, so we can restore it after the step (as spike won't
    // suppressed the register write).
    //
    // First check retired instruction to ensure load suppression is correct
    if (!check_suppress_reg_write(write_reg, pc, suppressed_write_reg)) {
      return false;
    }

    // The check gives us the destination register the instruction would have
    // written to (write_reg will be 0 to indicate to write). Record the
    // contents of that register.
    suppressed_write_reg_data =
        processor->get_state()->XPR[suppressed_write_reg];
  }

  // Before stepping Spike, record the current spike pc.
  // (If the current step causes a synchronous trap, it will be
  //  recorded against the current pc)
  initial_spike_pc = (processor->get_state()->pc & 0xffffffff);
  // Spike enters debug inside step(1) when a single-stepped instruction traps, so whether the
  // trap was taken outside debug mode must be sampled before the step.
  const bool pre_step_debug_mode = processor->get_state()->debug_mode;
  // The other way round: step() enters debug mode *before* it fetches anything when a halt
  // request is pending, or when the previous step retired a single-stepped instruction
  // (processor_t::step(), riscv/execute.cc), and then runs the debug ROM's first instruction in
  // the same step. If that fetch faults (an iside error injected at the halt address), Spike traps
  // at DEBUG_ROM_ENTRY, in debug mode, not at the pc it held before the step
  // (riscv_mem_error_traps_test 7492/7499, 2026-10-09: "PC mismatch at synchronous trap, DUT at
  // pc: 80000000 while ISS pc is at : 80003006"; both sides had entered debug and faulted there).
  const bool debug_entry_before_fetch =
      !pre_step_debug_mode &&
      ((processor->halt_request != processor_t::HR_NONE) ||
       (!processor->get_state()->serialized &&
        processor->get_state()->single_step == state_t::STEP_STEPPED));
  // Ibex gives an exception from the instruction in ID priority over a pending
  // interrupt (ibex_controller.sv: handle_irq is only considered when
  // !special_req); Spike takes the interrupt at the earliest boundary. Both are
  // legal, so if the DUT reported a synchronous trap and no interrupt, hide
  // pending interrupts from Spike for this one step.
  //
  // Deliberately NOT widened to every step without rvfi_intr (tried 2026-09-28):
  // the DUT's pending bit is often visible to Spike only before the DUT's
  // handler-entry step, so hiding it then left Spike never taking the interrupt
  // (riscv_single_interrupt_test, 11 seeds). Following the DUT's interrupt timing
  // in general needs Spike to be told when the DUT takes one, not a hidden mip.
  //
  // Likewise while the hart single-steps: Ibex hardwires dcsr.stepie to 0 (ibex_cs_registers.sv)
  // and takes no interrupt while dcsr.step is set outside debug mode (ibex_controller.sv
  // handle_irq: ~debug_single_step_i), including at the end of the step, where it enters debug
  // mode (cause 4) with dpc at the next instruction. This Spike has no stepie:
  // processor_t::step() calls take_pending_interrupt() before it enters debug mode for a
  // completed step, so when the stepped instruction enabled a pending interrupt it took the
  // interrupt and then entered debug with dpc at the handler (cov_expr_step_irq 28607/28608,
  // 2026-10-09: "Synchronous trap was expected at ISS PC: 80000000" at the step's debug entry).
  // The condition is Spike's own state, not the DUT's.
  const bool single_stepping =
      !pre_step_debug_mode && processor->get_state()->dcsr->step;
  if ((sync_trap && !intr) || single_stepping) {
    const reg_t saved_pre_mip = processor->get_state()->mip->read_pre_val();
    processor->get_state()->mip->write_pre_val(0);
    processor->step(1);
    processor->get_state()->mip->write_pre_val(saved_pre_mip);
  } else {
    processor->step(1);
  }

  // ISS
  // - If encountered an async trap,
  //    - PC_INVALID == true
  //    - step again to execute 1st instr of handler
  // - If encountered a sync trap,
  //    - PC_INVALID == true
  //    - current state is that of the trapping instruction
  //    - step again to execute 1st instr of handler
  // - If encountering a sync trap, immediately upon trying to jump to a async
  //      trap handler, (the reverse is not possible, as async traps are
  //      disabled upon entering a handler)
  //    - PC_INVALID == true
  //    - current state is that of the trapping instruction
  // DUT
  // - If the dut encounters an async trap (which can be thought of as occurring
  //   between instructions), an rvfi_item will be generated for the the first
  //   retired instruction of the trap handler.
  // - If the dut encounters a sync trap, an rvfi_item will be generated for the
  //   trapping instruction, with sync_trap == True. (The trapping instruction
  //   is presented on the RVFI but was not retired.)

  if (processor->get_state()->last_inst_pc == PC_INVALID) {
    if (!(processor->get_state()->mcause->read() & 0x80000000) ||
        processor->get_state()
            ->debug_mode) {  // (Async-Traps are disabled in debug mode)
      // Spike encountered a synchronous trap
      pending_sync_exception = true;

    } else {
      // Spike encountered an asynchronous trap.

      // Step to the first instruction of the ISR.
      initial_spike_pc = (processor->get_state()->pc & 0xffffffff);
      processor->step(1);

      if (processor->get_state()->last_inst_pc == PC_INVALID) {
        // If we see PC_INVALID here, the first instr of the ISR must cause an
        // exception, as interrupts are now disabled.
        pending_sync_exception = true;
      }
    }

    // If spike has advanced to be at a synchronous trap, now check that it
    // matches the reported dut behaviour.
    if (pending_sync_exception) {
      if (!sync_trap) {
        std::stringstream err_str;
        err_str << "Synchronous trap was expected at ISS PC: " << std::hex
                << processor->get_state()->pc
                << " but the DUT didn't report one at PC " << pc;
        errors.emplace_back(err_str.str());
        return false;
      }

      if (debug_entry_before_fetch) {
        initial_spike_pc = DEBUG_ROM_ENTRY;
      }

      if (!check_sync_trap(write_reg, pc, initial_spike_pc)) {
        return false;
      }

      // An exception taken in debug mode leaves cpuctrlsts alone (ibex_cs_registers.sv), and
      // after debug_entry_before_fetch the trap was taken in debug mode.
      handle_cpuctrl_exception_entry(pre_step_debug_mode || debug_entry_before_fetch);

      // This is all the checking possible when consider a
      // synchronously-trapping instruction that never retired.
      return true;
    }
  }

  // We reached a retired instruction, so check spike and the dut behaved
  // consistently.

  if (!sync_trap && pc_is_mret(pc)) {
    change_cpuctrlsts_sync_exc_seen(false);

    if (nmi_mode) {
      // Do handling for recoverable NMI
      leave_nmi_mode();
    }
  }

  if (pending_iside_error) {
    std::stringstream err_str;
    err_str << "DUT generated an iside error for address: " << std::hex
            << pending_iside_err_addr << " but the ISS didn't produce one";
    errors.emplace_back(err_str.str());
    return false;
  }
  pending_iside_error = false;

  if (suppress_reg_write) {
    // If we suppressed a register write restore the old register state now
    processor->get_state()->XPR.write(suppressed_write_reg,
                                      suppressed_write_reg_data);
  }

  if (!check_retired_instr(write_reg, write_reg_data, pc, suppress_reg_write)) {
    return false;
  }

  // Only increment insn_cnt and return true if there are no errors
  insn_cnt++;
  return true;
}

bool SpikeCosim::check_retired_instr(uint32_t write_reg,
                                     uint32_t write_reg_data, uint32_t dut_pc,
                                     bool suppress_reg_write) {
  // Check the retired instruction and all of its side-effects match those from
  // the DUT

  // Check PC of executed instruction matches the expected PC
  // TODO: Confirm details of why spike sign extends PC, something to do with
  // 32-bit address as 64-bit address must be sign extended?
  if ((processor->get_state()->last_inst_pc & 0xffffffff) != dut_pc) {
    std::stringstream err_str;
    err_str << "PC mismatch, DUT retired : " << std::hex << dut_pc
            << " , but the ISS retired: " << std::hex
            << (processor->get_state()->last_inst_pc & 0xffffffff);
    errors.emplace_back(err_str.str());
    return false;
  }

  // Check register writes from executed instruction match what is expected
  auto &reg_changes = processor->get_state()->log_reg_write;

  bool gpr_write_seen = false;

  // Collect the GPR writes before checking any of them. A single Spike
  // instruction can write two GPRs -- the Zcmp double-register moves
  // cm.mvsa01 and cm.mva01s -- which Ibex expands into two RVFI retirements at
  // the same PC. We therefore cannot assume the first GPR write in the log is
  // the one this retirement carries, and must match by register number.
  std::vector<const commit_log_reg_t::value_type *> gpr_writes;

  for (auto &reg_change : reg_changes) {
    // reg_change.first provides register type in bottom 4 bits, then register
    // index above that

    // Ignore writes to x0
    if (reg_change.first == 0)
      continue;

    if ((reg_change.first & 0xf) == 0) {
      // register is GPR
      gpr_writes.push_back(&reg_change);
    } else if ((reg_change.first & 0xf) == 4) {
      // register is CSR
      on_csr_write(reg_change);
    } else {
      // should never see other types
      assert(false);
    }
  }

  if (!suppress_reg_write && gpr_writes.size() > 1) {
    // Expanded instruction (Zcmp): the ISS wrote several GPRs in this single
    // step, and the DUT reported them across several retirements at the same
    // PC. The earlier ones were recorded by step() via `more_ops`; this call
    // carries the final one. Match the whole set.
    //
    // Matching is by register number -- the ISS does not use Ibex's operation
    // order, so position cannot be relied on.
    std::vector<PendingGprWrite> dut_writes = deferred_dut_writes;
    dut_writes.push_back({write_reg, write_reg_data});
    deferred_dut_writes.clear();
    // The ISS side skips x0 above; do the same here. cm.popret(z) ends in
    // `jalr x0, 0(ra)`, which the DUT reports as a write to x0.
    dut_writes.erase(std::remove_if(dut_writes.begin(), dut_writes.end(),
                                    [](const PendingGprWrite &w) { return w.reg == 0; }),
                     dut_writes.end());

    if (dut_writes.size() != gpr_writes.size()) {
      std::stringstream err_str;
      err_str << "Expanded instruction at pc " << std::hex << dut_pc
              << ": the DUT reported " << std::dec << dut_writes.size()
              << " register write(s) but the ISS made " << gpr_writes.size();
      errors.emplace_back(err_str.str());
      return false;
    }

    for (const auto &dut_write : dut_writes) {
      size_t match_idx = gpr_writes.size();
      for (size_t i = 0; i < gpr_writes.size(); i++) {
        if (gpr_writes[i] != nullptr &&
            ((gpr_writes[i]->first >> 4) & 0x1f) == dut_write.reg) {
          match_idx = i;
          break;
        }
      }

      if (match_idx == gpr_writes.size()) {
        std::stringstream err_str;
        err_str << "DUT wrote register x" << std::dec << dut_write.reg
                << " at pc " << std::hex << dut_pc
                << " but the ISS made no such write among the "
                << std::dec << gpr_writes.size()
                << " writes of this expanded instruction";
        errors.emplace_back(err_str.str());
        return false;
      }

      if (!check_gpr_write(*gpr_writes[match_idx], dut_write.reg,
                           dut_write.data)) {
        return false;
      }

      // Consume it so a second DUT write to the same register cannot match the
      // same ISS write twice.
      gpr_writes[match_idx] = nullptr;
    }

    gpr_write_seen = true;
  } else {
    for (auto *gpr_write : gpr_writes) {
      // should never see more than one GPR write per step
      assert(!gpr_write_seen);

      if (!suppress_reg_write &&
          !check_gpr_write(*gpr_write, write_reg, write_reg_data)) {
        return false;
      }

      gpr_write_seen = true;
    }
  }

  if (write_reg != 0 && !gpr_write_seen) {
    std::stringstream err_str;
    err_str << "DUT wrote register x" << write_reg
            << " but a write was not expected" << std::endl;
    errors.emplace_back(err_str.str());
    return false;
  }

  // Errors may have been generated outside of step()
  // (e.g. in check_mem_access()).
  if (errors.size() != 0) {
    return false;
  }

  return true;
}

bool SpikeCosim::check_sync_trap(uint32_t write_reg, uint32_t dut_pc,
                                 uint32_t initial_spike_pc) {
  // Check if an synchronously-trapping instruction matches
  // between Spike and the DUT.

  // Check that both spike and DUT trapped on the same pc
  if (initial_spike_pc != dut_pc) {
    std::stringstream err_str;
    err_str << "PC mismatch at synchronous trap, DUT at pc: " << std::hex
            << dut_pc << "while ISS pc is at : " << std::hex
            << initial_spike_pc;
    errors.emplace_back(err_str.str());
    return false;
  }

  // A sync trap should not have any side-effects, as the instruction appears on
  // the DUT RVFI but is not actually retired.
  if (write_reg != 0) {
    std::stringstream err_str;
    err_str << "Synchronous trap occurred at PC: " << std::hex << dut_pc
            << "but DUT wrote to register: x" << std::dec << write_reg;
    errors.emplace_back(err_str.str());
    return false;
  }

  if ((processor->get_state()->mcause->read() == 0x5) ||
      (processor->get_state()->mcause->read() == 0x7)) {
    // We have a load or store access fault, apply fixup for misaligned accesses
    misaligned_pmp_fixup();
  }

  // If we see an internal NMI, that means we receive an extra memory intf item.
  // Deleting that is necessary since next Load/Store would fail otherwise.
  if (processor->get_state()->mcause->read() == 0xFFFFFFE0) {
    pending_dside_accesses.erase(pending_dside_accesses.begin());
  }

  // Errors may have been generated outside of step() (e.g. in
  // check_mem_access()), return false if there are any.
  if (errors.size() != 0) {
    return false;
  }

  return true;
}

bool SpikeCosim::check_gpr_write(const commit_log_reg_t::value_type &reg_change,
                                 uint32_t write_reg, uint32_t write_reg_data) {
  uint32_t cosim_write_reg = (reg_change.first >> 4) & 0x1f;

  if (write_reg == 0) {
    std::stringstream err_str;
    err_str << "DUT didn't write to register x" << cosim_write_reg
            << ", but a write was expected";
    errors.emplace_back(err_str.str());

    return false;
  }

  if (write_reg != cosim_write_reg) {
    std::stringstream err_str;
    err_str << "Register write index mismatch, DUT: x" << write_reg
            << " expected: x" << cosim_write_reg;
    errors.emplace_back(err_str.str());

    return false;
  }

  // TODO: Investigate why this fails (may be because spike can produce PCs
  // with high 32 bits set).
  // assert((reg_change.second.v[0] & 0xffffffff00000000) == 0);
  uint32_t cosim_write_reg_data = reg_change.second.v[0];

  if (write_reg_data != cosim_write_reg_data) {
    std::stringstream err_str;
    err_str << "Register write data mismatch to x" << cosim_write_reg
            << " DUT: " << std::hex << write_reg_data
            << " expected: " << cosim_write_reg_data;
    errors.emplace_back(err_str.str());

    return false;
  }

  return true;
}

bool SpikeCosim::check_suppress_reg_write(uint32_t write_reg, uint32_t pc,
                                          uint32_t &suppressed_write_reg) {
  if (write_reg != 0) {
    std::stringstream err_str;
    err_str << "Instruction at " << std::hex << pc
            << " indicated a suppressed register write but wrote to x"
            << std::dec << write_reg;
    errors.emplace_back(err_str.str());

    return false;
  }

  if (!pc_is_load(pc, suppressed_write_reg)) {
    std::stringstream err_str;
    err_str << "Instruction at " << std::hex << pc
            << " indicated a suppressed register write is it not a load"
               " only loads can suppress register writes";
    errors.emplace_back(err_str.str());

    return false;
  }

  return true;
}

void SpikeCosim::on_csr_write(const commit_log_reg_t::value_type &reg_change) {
  int cosim_write_csr = (reg_change.first >> 4) & 0xfff;

  // TODO: Investigate why this fails (may be because spike can produce PCs
  // with high 32 bits set).
  // assert((reg_change.second.v[0] & 0xffffffff00000000) == 0);
  uint32_t cosim_write_csr_data = reg_change.second.v[0];

  // Spike and Ibex have different WARL behaviours so after any CSR write
  // check the fields and adjust to match Ibex behaviour.
  fixup_csr(cosim_write_csr, cosim_write_csr_data);
}

void SpikeCosim::leave_nmi_mode() {
  nmi_mode = false;

  // Restore CSR status from mstack
  uint32_t mstatus = processor->get_csr(CSR_MSTATUS);
  mstatus = set_field(mstatus, MSTATUS_MPP, mstack.mpp);
  mstatus = set_field(mstatus, MSTATUS_MPIE, mstack.mpie);
#ifdef OLD_SPIKE
  processor->set_csr(CSR_MSTATUS, mstatus);

  processor->set_csr(CSR_MEPC, mstack.epc);
  processor->set_csr(CSR_MCAUSE, mstack.cause);
#else
  processor->put_csr(CSR_MSTATUS, mstatus);

  processor->put_csr(CSR_MEPC, mstack.epc);
  processor->put_csr(CSR_MCAUSE, mstack.cause);
#endif
}

void SpikeCosim::handle_cpuctrl_exception_entry(bool was_debug_mode) {
  if (!was_debug_mode) {
    bool old_sync_exc_seen = change_cpuctrlsts_sync_exc_seen(true);
    if (old_sync_exc_seen) {
      set_cpuctrlsts_double_fault_seen();
    }
  }
}

bool SpikeCosim::change_cpuctrlsts_sync_exc_seen(bool flag) {
  bool old_flag = false;
  uint32_t cpuctrlsts = processor->get_csr(CSR_CPUCTRLSTS);

  // If sync_exc_seen (bit 6) is already set update old_flag to match
  if (cpuctrlsts & 0x40) {
    old_flag = true;
  }

  cpuctrlsts = (cpuctrlsts & 0x1bf) | (flag ? 0x40 : 0);
  processor->put_csr(CSR_CPUCTRLSTS, cpuctrlsts);

  return old_flag;
}

void SpikeCosim::set_cpuctrlsts_double_fault_seen() {
  uint32_t cpuctrlsts = processor->get_csr(CSR_CPUCTRLSTS);
  // Set double_fault_seen  (bit 7)
  cpuctrlsts = (cpuctrlsts & 0x17f) | 0x80;
  processor->put_csr(CSR_CPUCTRLSTS, cpuctrlsts);
}

void SpikeCosim::initial_proc_setup(uint32_t start_pc, uint32_t start_mtvec,
                                    uint32_t mhpm_counter_num) {
  processor->get_state()->pc = start_pc;
  processor->get_state()->mtvec->write(start_mtvec);

  // Ibex resets mstatus to 0x0000_0080, MPIE = 1 (doc/03_reference/cs_registers.rst); Spike's
  // mstatus starts at 0. A program that reads mstatus before its first trap or MRET saw the
  // difference (debug_dm_pmp: DUT 0x1880, Spike 0x1800 after setting MPP).
  processor->get_state()->mstatus->write(processor->get_state()->mstatus->read() |
                                         MSTATUS_MPIE);

  processor->get_state()->csrmap[CSR_MARCHID] =
      std::make_shared<const_csr_t>(processor.get(), CSR_MARCHID, IBEX_MARCHID);

  processor->set_mmu_capability(IMPL_MMU_SBARE);

  for (int i = 0; i < processor->TM.count(); ++i) {
    processor->TM.tdata2_write(processor.get(), i, 0);
    processor->TM.tdata1_write(processor.get(), i, 0x28001048);
  }

  for (int i = 0; i < mhpm_counter_num; i++) {
    processor->get_state()->csrmap[CSR_MHPMEVENT3 + i] =
        std::make_shared<const_csr_t>(processor.get(), CSR_MHPMEVENT3 + i,
                                      1 << i);
  }

  // Ibex implements mhpmcounter3 .. 3+MHPMCounterNum-1; the others read 0 and ignore writes.
  // Spike makes all 29 writable counters whatever set_mhpm_counter_num says (only their events
  // are constant), so a write to an unimplemented one stuck in the model: ibex_decode_holes
  // wrote 0xffffffff to mhpmcounter13 with MHPMCounterNum = 10 and the DUT read back 0, Spike
  // 0xffffffff (2026-10-08). Hardwire them to zero here, with their high halves. Not the user-level
  // aliases (hpmcounterN/hpmcounterNh): they are proxies that check mcounteren before reading, and
  // a const_csr_t in their place dropped that check, so a U-mode read Ibex traps on (mcounteren bit
  // N is 0 for an unimplemented counter) read 0 in Spike (mcounteren_test, csr_access_sweep,
  // 2026-10-09). The proxies read the original counter, which stays 0 as nothing can write it now.
  auto &csrmap = processor->get_state()->csrmap;
  for (int i = mhpm_counter_num; i < 29; i++) {
    for (reg_t csr : {(reg_t)CSR_MHPMCOUNTER3 + i, (reg_t)CSR_MHPMCOUNTER3H + i}) {
      if (csrmap.count(csr)) {
        csrmap[csr] = std::make_shared<const_csr_t>(processor.get(), csr, 0);
      }
    }
  }
}

void SpikeCosim::set_mip(uint32_t pre_mip, uint32_t post_mip) {
  uint32_t new_mip = pre_mip;
  uint32_t old_mip = processor->get_state()->mip->read();

  processor->get_state()->mip->write_with_mask(0xffffffff, post_mip);
  processor->get_state()->mip->write_pre_val(pre_mip);

  if (processor->get_state()->debug_mode ||
      (processor->halt_request == processor_t::HR_REGULAR) ||
      (!get_field(processor->get_csr(CSR_MSTATUS), MSTATUS_MIE) &&
       processor->get_state()->prv == PRV_M)) {
    // Return now if new MIP won't trigger an interrupt handler either because
    // we're in or heading to debug mode or interrupts are disabled.
    return;
  }

  uint32_t old_enabled_irq = old_mip & processor->get_state()->mie->read();
  uint32_t new_enabled_irq = new_mip & processor->get_state()->mie->read();
  if ((old_enabled_irq == 0) && (new_enabled_irq != 0)) {
    // Defer the early_interrupt_handle() call until step() can confirm via
    // rvfi_intr that the DUT actually entered the handler.  A level-sensitive
    // IRQ that is withdrawn while the controller sits in IRQ_TAKEN (handle_irq
    // goes false) is legally abandoned; calling early_interrupt_handle() here
    // would cause Spike to take an interrupt the DUT did not take.
    pending_irq_early_handle = true;
    pending_irq_pre_mip = pre_mip;
  }
}

// An NMI (set_nmi / set_nmi_int) can reach the model while an interrupt set_mip() deferred is
// still pending: the DUT entered the interrupt (IRQ_TAKEN committed: mepc, mcause, MPIE written)
// and the NMI arrived before the handler's first instruction retired, nesting on top of it. The
// deferred interrupt must then be taken first, so that the NMI's mstack holds the interrupt's
// mepc/mcause/MPIE as on the DUT; left to step(), it was taken a second time inside the NMI
// handler (riscv_pmp_traps_test 24861 and riscv_mem_error_traps_test 24857, 2026-10-06).
// Not covered: an NMI that pre-empts the interrupt in the IRQ_TAKEN cycle itself, so the DUT never
// takes the interrupt -- that shows up as a later mepc/mstack mismatch, it is not hidden.
void SpikeCosim::take_deferred_irq() {
  if (!pending_irq_early_handle) {
    return;
  }
  pending_irq_early_handle = false;
  state_t *s = processor->get_state();
  const bool irq_enabled =
      get_field(processor->get_csr(CSR_MSTATUS), MSTATUS_MIE) || s->prv < PRV_M;
  if (!irq_enabled || !(pending_irq_pre_mip & s->mie->read())) {
    return;
  }
  const reg_t saved_pre_mip = s->mip->read_pre_val();
  s->mip->write_pre_val(pending_irq_pre_mip);
  take_irq_before_halt();
  s->mip->write_pre_val(saved_pre_mip);
}

bool SpikeCosim::take_irq_before_halt() {
  state_t *s = processor->get_state();
  const bool irq_enabled =
      get_field(processor->get_csr(CSR_MSTATUS), MSTATUS_MIE) || s->prv < PRV_M;
  if (!irq_enabled || !(s->mip->read_pre_val() & s->mie->read())) {
    std::stringstream err_str;
    err_str << "DUT entered an interrupt handler (rvfi_intr) but the ISS has no enabled "
            << "interrupt pending: mip 0x" << std::hex << s->mip->read_pre_val() << " mie 0x"
            << s->mie->read() << " mstatus 0x" << processor->get_csr(CSR_MSTATUS);
    errors.emplace_back(err_str.str());
    return false;
  }
  // As in step(): a debug request already passed to the model must not pre-empt the interrupt.
  const auto saved_halt = processor->halt_request;
  processor->halt_request = processor_t::HR_NONE;
  early_interrupt_handle();
  processor->halt_request = saved_halt;
  return true;
}

void SpikeCosim::early_interrupt_handle() {
  // Execute a spike step on the assumption an interrupt will occur so no new
  // instruction is executed just the state altered to reflect the interrupt.
  uint32_t initial_spike_pc = (processor->get_state()->pc & 0xffffffff);
  processor->step(1);

  if (processor->get_state()->last_inst_pc != PC_INVALID) {
    std::stringstream err_str;
    err_str << "Attempted step for interrupt, expecting no instruction would "
            << "be executed but saw one. PC before: " << std::hex
            << initial_spike_pc
            << " PC after: " << (processor->get_state()->pc & 0xffffffff);
    errors.emplace_back(err_str.str());
  }
}

// Ibex splits misaligned accesses into two separate requests. They
// independently undergo PMP access checks. It is possible for one to fail (so
// no request produced for that half of the access) whilst the other succeeds
// (producing a request for that half of the access).
//
// Spike splits misaligned accesses up into bytes and will apply PMP access
// checks byte by byte in a linear order. As soon as a byte sees a PMP
// permission failure the rest of the misaligned access is aborted.
//
// This results in mismatches as in some misaligned access cases Ibex will
// produce a request and spike will not.
//
// This fixup detects this condition and removes the Ibex access from
// pending_dside_accesses to avoid a mismatch. This removed access is checked
// against PMP using the spike MMU to check spike agrees it passes PMP checks.
//
// There may be a better way to handle this (e.g. altering spike behaviour to
// match Ibex) so for now a warning is generated in fixup cases so they can be
// easily identified.
void SpikeCosim::misaligned_pmp_fixup() {
  if (pending_dside_accesses.size() != 0) {
    auto &top_pending_access = pending_dside_accesses.front();
    auto &top_pending_access_info = top_pending_access.dut_access_info;

    // If top access is the second half of a misaligned access where the first
    // half saw an error we have the PMP fixup case
    if (top_pending_access_info.misaligned_second &&
        top_pending_access_info.misaligned_first_saw_error) {
      mmu_t *mmu = processor->get_mmu();

      // Check if the second half of the access (which Ibex produces a request
      // for and spike does not) passes PMP
      if (!mmu->pmp_ok(top_pending_access_info.addr, 4,
                       top_pending_access_info.store ? STORE : LOAD,
                       top_pending_access_info.m_mode_access ? PRV_M : PRV_U)) {
        // Raise an error if the second half shouldn't have passed PMP
        std::stringstream err_str;
        err_str << "Saw second half of a misaligned access which not have "
                << "generated a memory request as it does not pass a PMP check,"
                << " address: " << std::hex << top_pending_access_info.addr;
        errors.emplace_back(err_str.str());
      } else {
        // Output warning on stdout so we're aware which tests this is happening
        // in
        std::cout << "WARNING: Cosim dropping second half of misaligned access "
                  << "as first half saw an error and second half passed PMP "
                  << "check, address: " << std::hex
                  << top_pending_access_info.addr << std::endl;
        std::cout << std::dec;

        // A store's second half is not just an access to skip: Ibex wrote those bytes (the
        // privileged spec lets the part of a misaligned store that passes PMP become visible),
        // while Spike aborted at the first failing byte and wrote nothing. Dropping it left the
        // bench's memory and Spike's different, and the next load of those bytes mismatched
        // (riscv_pmp_full_random_test.3977: sh 0xfaff6170 to 0x3e99f1ff, first half denied,
        // 0x61 written at 0x3e99f200; much later an lhu read it back as 0x61 vs Spike's 0).
        if (top_pending_access_info.store) {
          misaligned_store_second_half(top_pending_access_info);
        }

        pending_dside_accesses.erase(pending_dside_accesses.begin());
      }
    }
  }
}

// Apply the second half of a misaligned store whose first half faulted to Spike's memory. The
// bytes come from Spike's own state, not from the DUT: Spike has just taken the store access
// fault, so MEPC is the store and MTVAL its start address (Spike faults on the first byte); the
// store is decoded from Spike's memory and its rs2 read from Spike's register file. The DUT's
// write is then checked against them, byte enables included, so the DUT cannot slip a wrong
// value into the model this way.
void SpikeCosim::misaligned_store_second_half(const DSideAccessInfo &dut) {
  state_t *s = processor->get_state();
  uint32_t pc = s->mepc->read();
  uint32_t start = s->mtval->read();
  uint32_t insn = 0;
  uint8_t ib[4];
  if (!backdoor_read_mem(pc, 4, ib)) {
    errors.emplace_back("Misaligned store fixup: cannot read the store instruction at mepc");
    return;
  }
  insn = ib[0] | (ib[1] << 8) | (ib[2] << 16) | (ib[3] << 24);

  unsigned rs2 = 0, size = 0;
  if ((insn & 0x3) != 0x3) {
    uint32_t c = insn & 0xffff;
    if ((c & 0xe003) == 0xc000) {          // c.sw   rs2' = bits[4:2] + 8
      rs2 = ((c >> 2) & 0x7) + 8;
      size = 4;
    } else if ((c & 0xe003) == 0xc002) {   // c.swsp rs2  = bits[6:2]
      rs2 = (c >> 2) & 0x1f;
      size = 4;
    }
  } else if ((insn & 0x7f) == 0x23) {      // STORE: funct3 1 = sh, 2 = sw
    uint32_t f3 = (insn >> 12) & 0x7;
    rs2 = (insn >> 20) & 0x1f;
    size = (f3 == 1) ? 2 : (f3 == 2) ? 4 : 0;
  }
  if (size == 0) {
    std::stringstream err_str;
    err_str << "Misaligned store fixup: instruction 0x" << std::hex << insn << " at 0x" << pc
            << " is not a store the fixup can model";
    errors.emplace_back(err_str.str());
    return;
  }

  uint32_t value = s->XPR[rs2];
  uint32_t exp_be = 0, exp_data = 0;
  for (unsigned i = 0; i < size; ++i) {
    uint32_t a = start + i;
    if ((a & ~0x3u) != dut.addr) continue;  // only the bytes in the second word
    uint8_t b = (value >> (8 * i)) & 0xff;
    exp_be |= 1u << (a & 0x3);
    exp_data |= uint32_t(b) << (8 * (a & 0x3));
    backdoor_write_mem(a, 1, &b);
  }

  uint32_t mask = 0;
  for (unsigned i = 0; i < 4; ++i)
    if (exp_be & (1u << i)) mask |= 0xffu << (8 * i);
  if (exp_be != dut.be || (dut.data & mask) != exp_data) {
    std::stringstream err_str;
    err_str << "Second half of misaligned store at 0x" << std::hex << start << " (first half "
            << "faulted): DUT wrote data 0x" << (dut.data & mask) << " BE 0x" << dut.be
            << " to 0x" << dut.addr << " but data 0x" << exp_data << " BE 0x" << exp_be
            << " was expected";
    errors.emplace_back(err_str.str());
  }
}

void SpikeCosim::set_nmi(bool nmi) {
  if (nmi && !nmi_mode && !processor->get_state()->debug_mode &&
      processor->halt_request != processor_t::HR_REGULAR) {
    take_deferred_irq();  // before the mstack save below
    processor->get_state()->nmi = true;
    nmi_mode = true;

    // When NMI is set it is guaranteed NMI trap will be taken at the next step
    // so save CSR state for recoverable NMI to mstack now.
    mstack.mpp = get_field(processor->get_csr(CSR_MSTATUS), MSTATUS_MPP);
    mstack.mpie = get_field(processor->get_csr(CSR_MSTATUS), MSTATUS_MPIE);
    mstack.epc = processor->get_csr(CSR_MEPC);
    mstack.cause = processor->get_csr(CSR_MCAUSE);

    early_interrupt_handle();
  }
}

void SpikeCosim::set_nmi_int(bool nmi_int, uint32_t mtval) {
  if (nmi_int && !nmi_mode && !processor->get_state()->debug_mode &&
      processor->halt_request != processor_t::HR_REGULAR) {
    take_deferred_irq();  // before the mstack save below
    processor->get_state()->nmi_int = true;
    nmi_mode = true;

    // When NMI is set it is guaranteed NMI trap will be taken at the next step
    // so save CSR state for recoverable NMI to mstack now.
    mstack.mpp = get_field(processor->get_csr(CSR_MSTATUS), MSTATUS_MPP);
    mstack.mpie = get_field(processor->get_csr(CSR_MSTATUS), MSTATUS_MPIE);
    mstack.epc = processor->get_csr(CSR_MEPC);
    mstack.cause = processor->get_csr(CSR_MCAUSE);

    early_interrupt_handle();

    // Spike has now taken the trap and zeroed mtval, as a standard RISC-V model
    // does for any interrupt. Ibex instead writes the address of the
    // transaction that returned bad integrity, so overwrite Spike's value with
    // the DUT's. Done AFTER early_interrupt_handle() for that reason -- setting
    // it before would simply be overwritten by the trap.
    //
    // Without this, a `csrr rd, mtval` in the NMI handler diverges and the run
    // dies with "Register write data mismatch ... DUT: 8001xxxx expected: 0".
    // That was riscv_mem_intg_error_test seeds 21577/21580/21582 in the
    // 2026-09-23 regression -- the DUT was correct in all three.
#ifdef OLD_SPIKE
    processor->set_csr(CSR_MTVAL, mtval);
#else
    processor->put_csr(CSR_MTVAL, mtval);
#endif
  }
}

void SpikeCosim::set_debug_req(bool debug_req) {
  processor->halt_request =
      debug_req ? processor_t::HR_REGULAR : processor_t::HR_NONE;
}

void SpikeCosim::set_mcycle(uint64_t mcycle) {
  uint32_t upper_mcycle = mcycle >> 32;
  uint32_t lower_mcycle = mcycle & 0xffffffff;

  // Spike decrements the MCYCLE CSR when you write to it to hack around an
  // issue it has with incorrectly setting minstret/mcycle when there's an
  // explicit write to them. There's no backdoor write available via the public
  // interface to skip this. To complicate matters we can only write 32 bits at
  // a time and get a decrement each time.

  // Write the lower half first, incremented twice due to the double decrement
  processor->get_state()->csrmap[CSR_MCYCLE]->write(lower_mcycle + 2);

  if ((processor->get_state()->csrmap[CSR_MCYCLE]->read() & 0xffffffff) == 0) {
    // If the lower half is 0 at this point then the upper half will get
    // decremented, so increment it first.
    upper_mcycle++;
  }

  // Set the upper half
  processor->get_state()->csrmap[CSR_MCYCLEH]->write(upper_mcycle);

  // TODO: Do a neater job of this, a more recent spike release should allow us
  // to write all 64 bits at once at least.
}

uint32_t SpikeCosim::get_csr(const int csr_num) {
  return (uint32_t)processor->get_csr(csr_num);
}

void SpikeCosim::set_csr(const int csr_num, const uint32_t new_val) {
  // Note that this is tested with ibex-cosim-v0.3 version of Spike. 'set_csr'
  // method might have a hardwired zero for mhpmcounterX registers.
#ifdef OLD_SPIKE
  processor->set_csr(csr_num, new_val);
#else
  processor->put_csr(csr_num, new_val);
#endif
}

void SpikeCosim::set_ic_scr_key_valid(bool valid) {
  processor->set_ic_scr_key_valid(valid);
}

void SpikeCosim::notify_dside_access(const DSideAccessInfo &access_info) {
  // Address must be 32-bit aligned
  assert((access_info.addr & 0x3) == 0);

  pending_dside_accesses.emplace_back(
      PendingMemAccess{.dut_access_info = access_info, .be_spike = 0});
}

void SpikeCosim::set_iside_error(uint32_t addr) {
  // Address must be 32-bit aligned
  assert((addr & 0x3) == 0);

  pending_iside_error = true;
  pending_iside_err_addr = addr;
}

const std::vector<std::string> &SpikeCosim::get_errors() { return errors; }

void SpikeCosim::clear_errors() { errors.clear(); }

void SpikeCosim::fixup_csr(int csr_num, uint32_t csr_val) {
  switch (csr_num) {
    case CSR_MSTATUS: {
      reg_t mask =
          MSTATUS_MIE | MSTATUS_MPIE | MSTATUS_MPRV | MSTATUS_MPP | MSTATUS_TW;

      reg_t new_val = csr_val & mask;
#ifdef OLD_SPIKE
      processor->set_csr(csr_num, new_val);
#else
      processor->put_csr(csr_num, new_val);
#endif
      break;
    }
    case CSR_MCAUSE: {
      uint32_t any_interrupt = csr_val & 0x80000000;
      uint32_t int_interrupt = csr_val & 0x40000000;

      reg_t new_val = (csr_val & 0x0000001f) | any_interrupt;

      if (any_interrupt && int_interrupt) {
        new_val |= 0x7fffffe0;
      }
#ifdef OLD_SPIKE
      processor->set_csr(csr_num, new_val);
#else
      processor->put_csr(csr_num, new_val);
#endif
      break;
    }
    case CSR_MTVEC: {
      uint32_t mtvec_and_mask = 0xffffff00;
      uint32_t mtvec_or_mask = 0x1;

      // For Ibex, mtvec.MODE is set to vectored and
      // mtvec.BASE must be 256-byte aligned
      reg_t new_val = (csr_val & mtvec_and_mask) | mtvec_or_mask;
#ifdef OLD_SPIKE
      processor->set_csr(csr_num, new_val);
#else
      processor->put_csr(csr_num, new_val);
#endif
      break;
    }
    case CSR_MISA: {
      // For Ibex, misa is hardwired
      reg_t new_val = 0x40901104;
#ifdef OLD_SPIKE
      processor->set_csr(csr_num, new_val);
#else
      processor->put_csr(csr_num, new_val);
#endif
      break;
    }
    case CSR_MCOUNTEREN: {
      // Bits 3..3+mhpm_counter_num-1 correspond to implemented HPM counters
      reg_t hpm_mask = ((1 << mhpm_counter_num) - 1) << 3;
      // Bit 0 and 2 are for mcycle and minstret which are always implemented
      // Bit 1 is for time which is not implemented, hence the mask 0x5
      reg_t new_val = csr_val & (0x5 | hpm_mask);
#ifdef OLD_SPIKE
      processor->set_csr(csr_num, new_val);
#else
      processor->put_csr(csr_num, new_val);
#endif
      break;
    }
  }
}

SpikeCosim::check_mem_result_e SpikeCosim::check_mem_access(
    bool store, uint32_t addr, size_t len, const uint8_t *bytes) {
  assert(len >= 1 && len <= 4);
  // Expect that no spike memory accesses cross a 32-bit boundary
  assert(((addr + (len - 1)) & 0xfffffffc) == (addr & 0xfffffffc));

  std::string iss_action = store ? "store" : "load";

  // Check if there are any pending DUT accesses to check against
  if (pending_dside_accesses.size() == 0) {
    std::stringstream err_str;
    err_str << "A " << iss_action << " at address " << std::hex << addr
            << " was expected but there are no pending accesses";
    errors.emplace_back(err_str.str());

    return kCheckMemCheckFailed;
  }

  auto &top_pending_access = pending_dside_accesses.front();
  auto &top_pending_access_info = top_pending_access.dut_access_info;

  std::string dut_action = top_pending_access_info.store ? "store" : "load";

  // Check for an address match
  uint32_t aligned_addr = addr & 0xfffffffc;
  if (aligned_addr != top_pending_access_info.addr) {
    std::stringstream err_str;
    err_str << "DUT generated " << dut_action << " at address " << std::hex
            << top_pending_access_info.addr << " but " << iss_action
            << " at address " << aligned_addr << " was expected";
    errors.emplace_back(err_str.str());

    return kCheckMemCheckFailed;
  }

  // Check access type match
  if (store != top_pending_access_info.store) {
    std::stringstream err_str;
    err_str << "DUT generated " << dut_action << " at addr " << std::hex
            << top_pending_access_info.addr << " but a " << iss_action
            << " was expected";
    errors.emplace_back(err_str.str());

    return kCheckMemCheckFailed;
  }

  // Calculate bytes within aligned 32-bit word that spike has accessed
  uint32_t expected_be = ((1 << len) - 1) << (addr & 0x3);

  bool pending_access_done = false;
  bool misaligned = top_pending_access_info.misaligned_first ||
                    top_pending_access_info.misaligned_second;

  if (misaligned) {
    // For misaligned accesses spike will generated multiple single byte
    // accesses where the DUT will generate an access covering all bytes within
    // an aligned 32-bit word.

    // Check bytes accessed this time haven't already been been seen for the DUT
    // access we are trying to match against
    if ((expected_be & top_pending_access.be_spike) != 0) {
      std::stringstream err_str;
      err_str << "DUT generated " << dut_action << " at address " << std::hex
              << top_pending_access_info.addr << " with BE "
              << top_pending_access_info.be << " and expected BE "
              << expected_be << " has been seen twice, so far seen "
              << top_pending_access.be_spike;

      errors.emplace_back(err_str.str());

      return kCheckMemCheckFailed;
    }

    // Check expected access isn't trying to access bytes that the DUT access
    // didn't access.
    if ((expected_be & ~top_pending_access_info.be) != 0) {
      std::stringstream err_str;
      err_str << "DUT generated " << dut_action << " at address " << std::hex
              << top_pending_access_info.addr << " with BE "
              << top_pending_access_info.be << " but expected BE "
              << expected_be << " has other bytes enabled";
      errors.emplace_back(err_str.str());
      return kCheckMemCheckFailed;
    }

    // Record which bytes have been seen from spike
    top_pending_access.be_spike |= expected_be;

    // If all bytes have been seen from spike we're done with this DUT access
    if (top_pending_access.be_spike == top_pending_access_info.be) {
      pending_access_done = true;
    }
  } else {
    // For aligned accesses bytes from spike access must precisely match bytes
    // from DUT access in one go
    if (expected_be != top_pending_access_info.be) {
      std::stringstream err_str;
      err_str << "DUT generated " << dut_action << " at address " << std::hex
              << top_pending_access_info.addr << " with BE "
              << top_pending_access_info.be << " but BE " << expected_be
              << " was expected";
      errors.emplace_back(err_str.str());

      return kCheckMemCheckFailed;
    }

    pending_access_done = true;
  }

  // Check data from expected access matches pending DUT access.
  // Data is ignored on error responses to loads so don't check it. Always check
  // store data.
  if (store || !top_pending_access_info.error) {
    // Combine bytes into a single word
    uint32_t expected_data = 0;
    for (int i = 0; i < len; ++i) {
      expected_data |= bytes[i] << (i * 8);
    }

    // Shift bytes into their position within an aligned 32-bit word
    expected_data <<= (addr & 0x3) * 8;

    // Mask off bytes expected access doesn't touch and check bytes match for
    // those that it does
    uint32_t expected_be_bits = (((uint64_t)1 << (len * 8)) - 1)
                                << ((addr & 0x3) * 8);
    uint32_t masked_dut_data = top_pending_access_info.data & expected_be_bits;

    if (expected_data != masked_dut_data) {
      std::stringstream err_str;
      err_str << "DUT generated " << iss_action << " at address " << std::hex
              << top_pending_access_info.addr << " with data "
              << masked_dut_data << " but data " << expected_data
              << " was expected with byte mask " << expected_be;

      errors.emplace_back(err_str.str());

      return kCheckMemCheckFailed;
    }
  }

  bool pending_access_error = top_pending_access_info.error;

  if (pending_access_error && misaligned) {
    // When misaligned accesses see an error, if they have crossed a 32-bit
    // boundary DUT will generate two accesses. If the top pending access from
    // the DUT was the first half of a misaligned access which accesses the top
    // byte, it must have crossed the 32-bit boundary and generated a second
    // access
    if (top_pending_access_info.misaligned_first &&
        ((top_pending_access_info.be & 0x8) != 0)) {
      // Check the second access DUT exists
      if ((pending_dside_accesses.size() < 2) ||
          !pending_dside_accesses[1].dut_access_info.misaligned_second) {
        std::stringstream err_str;
        err_str << "DUT generated first half of misaligned " << iss_action
                << " at address " << std::hex << top_pending_access_info.addr
                << " but second half was expected and not seen";

        errors.emplace_back(err_str.str());

        return kCheckMemCheckFailed;
      }

      // Check the second access had the expected address
      if (pending_dside_accesses[1].dut_access_info.addr !=
          (top_pending_access_info.addr + 4)) {
        std::stringstream err_str;
        err_str << "DUT generated first half of misaligned " << iss_action
                << " at address " << std::hex << top_pending_access_info.addr
                << " but second half had incorrect address "
                << pending_dside_accesses[1].dut_access_info.addr;

        errors.emplace_back(err_str.str());

        return kCheckMemCheckFailed;
      }

      // TODO: How to check BE? May need length of transaction?

      // Remove the top pending access now so both the first and second DUT
      // accesses for this misaligned access are removed.
      pending_dside_accesses.erase(pending_dside_accesses.begin());
    }

    // For any misaligned access that sees an error immediately indicate to
    // spike the error has occurred, so ensure the top pending access gets
    // removed.
    pending_access_done = true;
  }

  if (pending_access_done) {
    pending_dside_accesses.erase(pending_dside_accesses.begin());
  }

  return pending_access_error ? kCheckMemBusError : kCheckMemOk;
}

bool SpikeCosim::pc_is_mret(uint32_t pc) {
  uint32_t insn;

  if (!backdoor_read_mem(pc, 4, reinterpret_cast<uint8_t *>(&insn))) {
    return false;
  }

  return insn == 0x30200073;
}

bool SpikeCosim::pc_is_debug_ebreak(uint32_t pc) {
  uint32_t dcsr = processor->get_csr(CSR_DCSR);

  // ebreak debug entry is controlled by the ebreakm (bit 15) and ebreaku (bit
  // 12) fields of DCSR. If the appropriate bit of the current privilege level
  // isn't set ebreak won't enter debug so return false.
  if (((processor->get_state()->prv == PRV_M) && ((dcsr & 0x1000) == 0)) ||
      ((processor->get_state()->prv == PRV_U) && ((dcsr & 0x8000) == 0))) {
    return false;
  }

  // First check for 16-bit c.ebreak
  uint16_t insn_16;
  if (!backdoor_read_mem(pc, 2, reinterpret_cast<uint8_t *>(&insn_16))) {
    return false;
  }

  if (insn_16 == 0x9002) {
    return true;
  }

  // Not a c.ebreak, check for 32 bit ebreak
  uint32_t insn_32;
  if (!backdoor_read_mem(pc, 4, reinterpret_cast<uint8_t *>(&insn_32))) {
    return false;
  }

  return insn_32 == 0x00100073;
}

bool SpikeCosim::check_debug_ebreak(uint32_t write_reg, uint32_t pc,
                                    bool sync_trap) {
  // A ebreak from the DUT should not write a register and will be reported as a
  // 'sync_trap' (though doesn't act like a trap in various respects).

  if (write_reg != 0) {
    std::stringstream err_str;
    err_str << "DUT executed ebreak at " << std::hex << pc
            << " but also wrote register x" << std::dec << write_reg
            << " which was unexpected";
    errors.emplace_back(err_str.str());

    return false;
  }

  if (sync_trap) {
    std::stringstream err_str;
    err_str << "DUT executed ebreak into debug at " << std::hex << pc
            << " but indicated a synchronous trap, which was unexpected";
    errors.emplace_back(err_str.str());

    return false;
  }

  return true;
}

bool SpikeCosim::pc_is_load(uint32_t pc, uint32_t &rd_out) {
  uint16_t insn_16;

  if (!backdoor_read_mem(pc, 2, reinterpret_cast<uint8_t *>(&insn_16))) {
    return false;
  }

  // C.LW
  if ((insn_16 & 0xE003) == 0x4000) {
    rd_out = ((insn_16 >> 2) & 0x7) + 8;
    return true;
  }

  // C.LWSP
  if ((insn_16 & 0xE003) == 0x4002) {
    rd_out = (insn_16 >> 7) & 0x1F;
    return rd_out != 0;
  }

  uint16_t insn_32;

  if (!backdoor_read_mem(pc, 4, reinterpret_cast<uint8_t *>(&insn_32))) {
    return false;
  }

  // LB/LH/LW/LBU/LHU
  if ((insn_32 & 0x7F) == 0x3) {
    uint32_t func = (insn_32 >> 12) & 0x7;
    if ((func == 0x3) || (func == 0x6) || (func == 0x7)) {
      // Not valid load encodings
      return false;
    }

    rd_out = (insn_32 >> 7) & 0x1F;
    return true;
  }

  return false;
}

unsigned int SpikeCosim::get_insn_cnt() { return insn_cnt; }
