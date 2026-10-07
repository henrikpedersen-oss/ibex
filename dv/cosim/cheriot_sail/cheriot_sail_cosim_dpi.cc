// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Step 2: DPI bridge between cheriot-sail generated C and UVM cosim scoreboard.
//
// Wraps zinit_model / zrvfi_set_instr_packet / zstep / zrvfi_get_cheri_data
// in an extern "C" interface callable from SystemVerilog via DPI.
// This is a global singleton — the Sail model uses process-wide global state.

#include "cheriot_sail_cosim_dpi.h"

#include <cassert>
#include <csetjmp>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
// svBitVecVal = uint32_t, svBit = unsigned char (from IEEE 1800 / svdpi.h).
// Defined here so we can compile without Xcelium headers.
typedef uint32_t      svBitVecVal;
typedef unsigned char svBit;

// Include gmp.h first in C++ context so its inline C++ stream operators are
// declared before sail.h re-requests it inside an extern "C" block (where
// extern "C++" nesting causes compiler errors on some GCC versions).
#include <gmp.h>

extern "C" {
// sail.h will try to #include <gmp.h> but include guards make it a no-op;
// the C++ operators are already registered above.
#include "sail.h"
#include "sail_failure.h"
#include "rts.h"  // read_tag_bool: the model's tag memory
#include "riscv_rvfi_model_RV32.h"

// model_init / model_fini are defined in the generated C but not declared in
// the generated header (they live in the .c only).
void model_init(void);
void model_fini(void);

// Required callbacks referenced by riscv_platform.c / riscv_platform_impl.c
// but defined in riscv_sim.c (which we exclude to avoid its main()).
bool config_print_instr       = false;
bool config_print_reg         = false;
bool config_print_mem_access  = false;
bool config_print_platform    = false;
bool config_print_exception   = false;
FILE *trace_log               = nullptr;

// write_mem is defined in the generated model C code; declare it here so we
// can call it from cheriot_sail_cosim_write_mem_byte.
void write_mem(uint64_t addr, uint64_t byte_val);

// Externally-visible memory layout globals (riscv_platform_impl.c)
extern uint64_t rv_ram_base;
extern uint64_t rv_ram_size;
extern uint64_t rv_rom_base;
extern uint64_t rv_rom_size;
extern uint64_t rv_htif_tohost;
extern bool     rv_enable_fdext;
extern bool     rv_enable_zfinx;
extern bool     rv_enable_misaligned;
}  // extern "C"

// ---------------------------------------------------------------------------
// Module state
// ---------------------------------------------------------------------------
static bool s_initialized = false;
static int64_t s_step_no  = 0;
static std::vector<std::string> s_errors;

// Init and per-step trace on stderr, only with CHERIOT_SAIL_TRACE set: TestRIG
// re-initialises the model for every test, so an unconditional trace printed
// thousands of lines per run. Errors are reported through s_errors regardless.
static bool trace_enabled(void) {
  static const bool enabled = getenv("CHERIOT_SAIL_TRACE") != nullptr;
  return enabled;
}
// The model refuses to run a trap loop through an untagged PCC and MTCC
// (cheri_addr_checks.sail: not_implemented "Untagged PCC and MTCC infinite
// loops"). Architecturally every later fetch faults back to MTCC, so until the
// next reset each step is reported as a trap to MTCC.address.
static bool s_pcc_mtcc_loop = false;
// RAM mapped at 0x80000000 by the next init. The default, 8 MiB, is the TestRIG TB's data memory
// (core_ibex_testrig_tb_top.sv DataMemSize), so accesses beyond it fault on both sides. The UVM
// bench's memory extends to the signature address (0x8ffffffc) and sets a larger size.
static uint64_t s_ram_size = UINT64_C(0x800000);

void cheriot_sail_cosim_set_ram_size(const svBitVecVal *size_p) {
  s_ram_size = (uint64_t)size_p[0];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Retrieve the CHERI extension packet and extract the two scalar fields we
// check: capability destination register address and write-tag bit.
static void get_cheri_output(uint64_t *out_cd_addr, uint64_t *out_cd_wtag) {
  lbits raw;
  CREATE(lbits)(&raw);
  zrvfi_get_cheri_data(&raw, UNIT);

  // The field accessors take the struct wrapper by value, sharing the lbits
  // pointer.  Call them before KILL(raw).
  struct zRVFI_DII_Execution_Packet_Ext_CHERI pkt = {.zbits = raw};
  *out_cd_addr = z_get_RVFI_DII_Execution_Packet_Ext_CHERI_rvfi_cd_addr(pkt);
  *out_cd_wtag = z_get_RVFI_DII_Execution_Packet_Ext_CHERI_rvfi_cd_wtag(pkt);

  KILL(lbits)(&raw);
}

// Retrieve the integer extension packet fields for integer-result CHERIoT
// instructions (e.g. cgetoffset, cgettag, cgetlen).
// Only call when zrvfi_int_data_present is true.
static void get_integer_output(uint64_t *out_rd_addr, uint64_t *out_rd_wdata) {
  *out_rd_addr  = z_get_RVFI_DII_Execution_Packet_Ext_Integer_rvfi_rd_addr(zrvfi_int_data);
  *out_rd_wdata = z_get_RVFI_DII_Execution_Packet_Ext_Integer_rvfi_rd_wdata(zrvfi_int_data);
}

// ---------------------------------------------------------------------------
// DPI interface
// ---------------------------------------------------------------------------

void cheriot_sail_cosim_init(const svBitVecVal *boot_addr_p) {
  uint32_t boot_addr = boot_addr_p[0];
  if (trace_enabled()) fprintf(stderr, "[cheriot-sail] init: boot_addr=0x%08x\n", boot_addr);
  if (s_initialized) {
    if (trace_enabled()) fprintf(stderr, "[cheriot-sail] init: re-initializing (calling model_fini first)\n");
    model_fini();
  }
  // CHERIoT-Ibex has no F/D and FS is read-only zero, so crt's
  // `csrs mstatus, 0x1e000` must not stick. legalize_mstatus() only clears FS
  // when Zfinx is on (riscv_sys_regs.sail), so fdext=false alone is not enough.
  // Side effect: Zfinx FP encodings would execute in Sail instead of trapping.
  // Must be set before zinit_model(): zinit_sys() reads them to build misa/mstatus.
  rv_enable_fdext = false;
  rv_enable_zfinx = true;
  // ibex performs misaligned loads/stores in hardware (split into two bus accesses); the
  // model must not trap on them. The sail-riscv platform default is false.
  rv_enable_misaligned = true;
  if (trace_enabled()) fprintf(stderr, "[cheriot-sail] init: calling model_init\n");
  model_init();
  if (trace_enabled()) fprintf(stderr, "[cheriot-sail] init: calling zinit_model\n");
  zinit_model(UNIT);
  // Match ibex_cs_registers.sv MSTATUS_RST_VAL mpie=1 (Sail resets 0; both legal). MPP is left
  // at M on purpose: CHERIoT is M-mode only (misa.U=0 here), so the RTL's reset mpp=U is a
  // finding, not a reset-value choice to paper over. No generated MPIE setter: MPIE=bit 7.
  zmstatus.zbits |= UINT64_C(0x80);
  if (trace_enabled()) fprintf(stderr, "[cheriot-sail] init: calling zext_rvfi_init\n");
  zext_rvfi_init(UNIT);
  if (trace_enabled()) fprintf(stderr, "[cheriot-sail] init: zext_rvfi_init done\n");

  // CHERIoT-Ibex RVFI-DII mode: no ROM, RAM starts at 0x80000000.
  // These globals are in riscv_platform_impl.c, linked into our .so.
  rv_ram_base    = UINT64_C(0x80000000);
  rv_ram_size    = s_ram_size;
  rv_rom_base    = UINT64_C(0);
  rv_rom_size    = UINT64_C(0);
  rv_htif_tohost = UINT64_C(0);

  // Set PC and mtvec to match CHERIoT-Ibex reset behaviour (from riscv_sim.c).
  // Ibex's reset PC is {boot_addr[31:8], 8'h80} (ibex_if_stage.sv PC_BOOT). The
  // per-step PC resync used to hide a model that started 0x80 early.
  zPC             = (uint64_t)((boot_addr & ~0xffu) | 0x80u);
  zmtvec.zbits    = (uint64_t)boot_addr;

  s_step_no = 0;
  s_errors.clear();
  have_exception  = false;
  s_pcc_mtcc_loop = false;
  s_initialized = true;
  if (trace_enabled()) fprintf(stderr, "[cheriot-sail] init: complete, PC=0x%08llx\n", (unsigned long long)zPC);
}

// zext_rvfi_init() (called by init above) sets x1-x15 to root_cap_mem, the start state
// QuickCheckVEngine sequences expect, and the TestRIG TB forces the RTL register file to match.
// CHERIoT-Ibex itself resets every GPR to NULL, as Sail's own ext_init_regs() does
// (cheri_regs.sail:174-188). A bench that runs real programs from reset (the UVM cosim) calls this
// after init; without it, a register the program reads before writing (e.g. csp saved by a trap
// handler) silently holds a root capability in the model and the comparison goes wrong later.
// znull_cap is a model global the generated header does not declare.
extern "C" struct zCapability znull_cap;
void cheriot_sail_cosim_null_gprs(void) {
  assert(s_initialized && "cheriot_sail_cosim_init() must be called first");
  struct zCapability *const gprs[] = {&zx1, &zx2,  &zx3,  &zx4,  &zx5,  &zx6,  &zx7, &zx8,
                                      &zx9, &zx10, &zx11, &zx12, &zx13, &zx14, &zx15};
  for (struct zCapability *r : gprs) *r = znull_cap;
}

int cheriot_sail_cosim_step(const svBitVecVal *insn_p,
                             const svBitVecVal *pc_p,
                             svBit cheri_rf_we,
                             const svBitVecVal *cheri_rd_p,
                             svBit cheri_rtag,
                             const svBitVecVal *rtl_rd_wdata_p,
                             svBit rtl_trap) {
  uint32_t insn     = insn_p[0];
  uint32_t pc       = pc_p[0];
  uint32_t cheri_rd = cheri_rd_p[0];
  assert(s_initialized && "cheriot_sail_cosim_init() must be called first");

  if (trace_enabled()) {
    fprintf(stderr, "[cheriot-sail] step %lld: insn=0x%08x pc=0x%08x\n",
            (long long)s_step_no, insn, pc);
  }

  // Encode RVFI-DII instruction packet (Sail bitfield RVFI_DII_Instruction_Packet):
  //   bits[31: 0] = rvfi_insn  (instruction word)
  //   bits[47:32] = rvfi_time  (step sequence number, 16-bit)
  //   bits[55:48] = rvfi_cmd   (0x01 = execute-instruction)
  //   bits[63:56] = reserved
  uint64_t pkt = (uint64_t)insn
               | ((uint64_t)(s_step_no & 0xffff) << 32)
               | ((uint64_t)0x01 << 48);
  zrvfi_set_instr_packet(pkt);
  // Clear the execution output packet before each step (mirrors riscv_sim.c).
  zrvfi_zzero_exec_packet(UNIT);

  if (s_pcc_mtcc_loop) {
    s_step_no++;
    return 0;
  }

  // The model runs on its own PC and must be where the DUT is. A difference means
  // the two diverged on an earlier step: report it here, where it becomes
  // visible, rather than letting it surface instructions later as a register
  // mismatch (the UVM cosim path has no next-pc check of its own). The model is
  // not moved to the DUT's PC: it keeps running from its own state, so the
  // errors that follow are the real consequence of the divergence rather than a
  // comparison against state copied from the DUT. (Moving zPC, and before that
  // PCC.address, to the DUT's PC masked PCC bounds violations, TestRIG
  // 2026-09-28.)
  bool pc_diverged = false;
  if (zPC != (uint64_t)pc) {
    char buf[160];
    snprintf(buf, sizeof(buf),
             "cheriot-sail model PC 0x%08llx differs from DUT PC 0x%08x at step %lld: "
             "the two diverged on an earlier step",
             (unsigned long long)zPC, pc, (long long)s_step_no);
    s_errors.emplace_back(buf);
    pc_diverged = true;
  }
  // (C.SLLI/C.SRLI/C.SRAI with shamt[5]=1 are rejected by the model's own decoder:
  // generated_definitions/c patched, riscv_insts_cext.sail guard backported.)

  sail_int sail_step;
  CREATE(sail_int)(&sail_step);
  CONVERT_OF(sail_int, mach_int)(&sail_step, s_step_no);

  // Arm the longjmp recovery buffer so that sail_match_failure() (which fires
  // when the generated decoder can't match an illegal instruction encoding)
  // returns here rather than calling exit() and crashing the simulation.
  sail_recovery_buf_active = 1;
  int recovery = setjmp(sail_recovery_buf);
  bool stepped;
  if (recovery != 0) {
    // sail_match_failure or sail_assert fired inside zstep(): the model has no
    // behaviour for this instruction (an encoding its decoder cannot match, or
    // an internal assertion). Nothing can be compared, and the model's state is
    // whatever zstep() left. That is an error, not a skip: a silent skip would
    // pass every instruction the model cannot execute.
    sail_recovery_buf_active = 0;
    // sail_step was CREATE'd above; the longjmp bypassed KILL — free it now.
    KILL(sail_int)(&sail_step);
    char buf[200];
    snprintf(buf, sizeof(buf),
             "cheriot-sail model cannot execute insn=0x%08x at pc=0x%08x (step %lld, "
             "Sail %s): not compared",
             insn, pc, (long long)s_step_no,
             recovery == 2 ? "assertion" : "match failure");
    s_errors.emplace_back(buf);
    s_step_no++;
    return -1;
  }

  // zstep() returns false when a trap was taken before any instruction ran (a
  // fetch fault or an interrupt). That is not a model failure: riscv_sim.c's
  // RVFI-DII loop sends the trace regardless and only uses `stepped` to advance
  // its step counter, so the trap is compared below like any other.
  stepped = zstep(sail_step);
  sail_recovery_buf_active = 0;
  KILL(sail_int)(&sail_step);
  (void)stepped;

  s_step_no++;

  // A Sail `throw` sets have_exception and unwinds zstep(); riscv_sim.c stops
  // there, and every later zstep() would return at once. Only the untagged
  // PCC/MTCC loop is expected; anything else is a real model error.
  if (have_exception) {
    have_exception = false;
    if (!zPCC.ztag && !zMTCC.ztag) {
      s_pcc_mtcc_loop = true;
      fprintf(stderr,
              "[cheriot-sail] step %lld: untagged PCC and MTCC, trap loop to 0x%08llx "
              "until reset\n",
              (long long)(s_step_no - 1), (unsigned long long)zMTCC.zaddress);
      return pc_diverged ? -1 : 0;
    }
    s_errors.emplace_back("cheriot-sail model raised a Sail exception at step " +
                          std::to_string(s_step_no - 1));
    return -1;
  }

  int ok = 1;

  // ── Capability register checks ────────────────────────────────────────────
  //
  // Only compare CHERI output when the Sail model executed a CHERIoT capability
  // instruction (zrvfi_cheri_data_present is true).  For ordinary integer
  // instructions both tag and address are uninitialized in the model's output
  // packet; calling zrvfi_get_cheri_data() would trigger a sail_assert failure.
  if (zrvfi_cheri_data_present) {
    uint64_t sail_cd_addr = 0, sail_cd_wtag = 0;
    get_cheri_output(&sail_cd_addr, &sail_cd_wtag);

    // Skip if Sail reports no capability destination (cd_addr=0, cd_wtag=0).
    // Integer-result CHERI instructions (cgettag, cgetlen, etc.) don't write a
    // capability in Sail's model; ibex nullifies the register but Sail doesn't.
    // Writing to c0 with tag=0 is also a no-op and safe to skip.
    bool has_cap_dest = !(sail_cd_addr == 0 && sail_cd_wtag == 0);
    if (has_cap_dest && cheri_rf_we) {
      if (sail_cd_addr != (uint64_t)cheri_rd) {
        char buf[160];
        snprintf(buf, sizeof(buf),
                 "cheriot-sail cd_addr mismatch: sail=0x%02llx rtl=0x%02x "
                 "(insn=0x%08x pc=0x%08x step=%lld)",
                 (unsigned long long)sail_cd_addr, (unsigned)cheri_rd,
                 (unsigned)insn, (unsigned)pc, (long long)(s_step_no - 1));
        s_errors.emplace_back(buf);
        ok = 0;
      }

      if ((sail_cd_wtag & 1) != (uint64_t)((unsigned)cheri_rtag & 1)) {
        char buf[160];
        snprintf(buf, sizeof(buf),
                 "cheriot-sail cd_wtag mismatch: sail=%llu rtl=%u "
                 "(insn=0x%08x pc=0x%08x step=%lld)",
                 (unsigned long long)(sail_cd_wtag & 1), (unsigned)cheri_rtag & 1,
                 (unsigned)insn, (unsigned)pc, (long long)(s_step_no - 1));
        s_errors.emplace_back(buf);
        ok = 0;
      }
    }
  }

  // ── Integer rd_wdata check ────────────────────────────────────────────────
  //
  // Integer-result CHERIoT instructions (cgetoffset, cgettag, cgetlen, cperm,
  // cgettype, cgetbase, cgetlen, cgetaddr) write an integer register rather
  // than a capability register.  Compare Sail's rvfi_rd_wdata against the
  // RTL's.  Skip when the RTL took a trap — on a trap the RTL's rd_addr is 0
  // (no register was committed) and rd_wdata is undefined.
  //
  // Also skip time-varying counter CSRs: the Sail DII model does not advance
  // mcycle/minstret/mhpmcounterN between steps so those reads always return 0
  // while the RTL returns the running hardware count.
  //   opcode SYSTEM = 0x73; funct3 != 0 distinguishes CSR from ECALL/EBREAK.
  //   Counter CSR address ranges: 0xB00-0xB1F, 0xB80-0xB9F (M-mode),
  //                                0xC00-0xC1F, 0xC80-0xC9F (U-mode shadows).
  uint32_t csr_addr      = (insn >> 20) & 0xfff;
  bool is_csr_insn       = ((insn & 0x7f) == 0x73) && (((insn >> 12) & 0x7) != 0);
  bool is_counter_csr    = is_csr_insn &&
                           (((csr_addr >= 0xB00) && (csr_addr <= 0xB1F)) ||
                            ((csr_addr >= 0xB80) && (csr_addr <= 0xB9F)) ||
                            ((csr_addr >= 0xC00) && (csr_addr <= 0xC1F)) ||
                            ((csr_addr >= 0xC80) && (csr_addr <= 0xC9F)));
  if (!rtl_trap && zrvfi_int_data_present && !is_counter_csr) {
    uint64_t sail_rd_addr, sail_rd_wdata;
    get_integer_output(&sail_rd_addr, &sail_rd_wdata);
    uint32_t rtl_rd_wdata = rtl_rd_wdata_p[0];

    // Only compare when Sail wrote to a non-zero register (writing to x0 is a
    // no-op in Sail's model; RTL may report rd_addr=0 too, so skip those).
    if (sail_rd_addr != 0 && (sail_rd_wdata & 0xffffffff) != (uint64_t)rtl_rd_wdata) {
      char buf[160];
      snprintf(buf, sizeof(buf),
               "cheriot-sail rd_wdata mismatch: sail=0x%08llx rtl=0x%08x "
               "rd=%llu (insn=0x%08x pc=0x%08x step=%lld)",
               (unsigned long long)(sail_rd_wdata & 0xffffffff), rtl_rd_wdata,
               (unsigned long long)sail_rd_addr,
               (unsigned)insn, (unsigned)pc, (long long)(s_step_no - 1));
      s_errors.emplace_back(buf);
      ok = 0;
    }
  }

  return (ok && !pc_diverged) ? 0 : -1;
}

// The DUT entered an interrupt handler. The model cannot see the DUT's IRQ pins,
// so it is given the pending bits (mip) and nothing else: whether the interrupt
// is enabled, and where it goes, come from the model's own mstatus/mie/mtcc.
int cheriot_sail_cosim_take_interrupt(const svBitVecVal *mip_p) {
  assert(s_initialized);
  const uint64_t saved_mip = zmip.zbits;
  zmip.zbits = (uint64_t)mip_p[0];

  // CHERIoT is M-mode only, so dispatchInterrupt() takes an interrupt exactly
  // when mstatus.MIE is set and a pending bit is enabled in mie.
  const bool mie_set = (zmstatus.zbits >> 3) & 1;
  if (!mie_set || (zmip.zbits & zmie.zbits) == 0) {
    char buf[160];
    snprintf(buf, sizeof(buf),
             "DUT took an interrupt the model has not enabled: mip=0x%08llx mie=0x%08llx "
             "mstatus.MIE=%d",
             (unsigned long long)zmip.zbits, (unsigned long long)zmie.zbits, mie_set);
    s_errors.emplace_back(buf);
    zmip.zbits = saved_mip;
    return -1;
  }

  zrvfi_zzero_exec_packet(UNIT);
  sail_int sail_step;
  CREATE(sail_int)(&sail_step);
  CONVERT_OF(sail_int, mach_int)(&sail_step, s_step_no);
  const bool stepped = zstep(sail_step);
  KILL(sail_int)(&sail_step);
  zmip.zbits = saved_mip;

  if (have_exception) {
    have_exception = false;
    s_errors.emplace_back("cheriot-sail model raised a Sail exception taking an interrupt");
    return -1;
  }
  if (stepped) {
    s_errors.emplace_back("cheriot-sail model executed an instruction instead of taking the "
                          "interrupt");
    return -1;
  }
  return 0;
}

// Return the Sail model's mtval register value after the last zstep().
// Only meaningful when the last step took a trap (rvfi_trap == 1).
uint32_t cheriot_sail_cosim_get_mtval(void) {
  return (uint32_t)(zmtval & 0xffffffffULL);
}

// Return the Sail model's mcause register value after the last zstep().
// Only meaningful when the last step took a trap.
// Format: bit 31 = interrupt flag, bits [4:0] = exception / interrupt code.
uint32_t cheriot_sail_cosim_get_mcause(void) {
  return (uint32_t)(zmcause.zbits & 0xffffffffULL);
}

int cheriot_sail_cosim_get_num_errors(void) {
  return (int)s_errors.size();
}

const char *cheriot_sail_cosim_get_error(int index) {
  if (index < 0 || (size_t)index >= s_errors.size()) return nullptr;
  return s_errors[(size_t)index].c_str();
}

void cheriot_sail_cosim_clear_errors(void) {
  s_errors.clear();
}

// Load one byte into the Sail model's memory (call after init, before first step).
void cheriot_sail_cosim_cleanup(void) {
  if (s_initialized) {
    model_fini();
    s_initialized = false;
  }
  s_step_no = 0;
  s_errors.clear();
}

// Load one byte into the Sail model's memory (call after init, before first step).
// The SV import declares data as bit [7:0], a packed vector, which DPI passes by reference
// (const svBitVecVal *), exactly like addr -- see Verilator's generated __Dpi.h. This took
// `svBit data` by value until 2026-10-01, i.e. wrote the low byte of a pointer; it had no SV
// caller until the revocation-bitmap feed (ibex_cosim_scoreboard::cheriot_sail_load_revbm).
void cheriot_sail_cosim_write_mem_byte(const svBitVecVal *addr_p, const svBitVecVal *data_p) {
  assert(s_initialized);
  write_mem((uint64_t)addr_p[0], (uint64_t)(data_p[0] & 0xffu));
}

// Push the RTL's mcycle counter into the Sail model so that csrr mcycle
// returns the hardware value rather than Sail's own (frozen) counter.
void cheriot_sail_cosim_set_mcycle(uint64_t mcycle) {
  zmcycle = mcycle;
}

// ---------------------------------------------------------------------------
// RVFI execution packet of the last step()
// ---------------------------------------------------------------------------

static uint64_t lbits_low64(lbits *v) {
  return (uint64_t)mpz_get_ui(*v->bits);
}

uint32_t cheriot_sail_cosim_get_pc_wdata(void) {
  if (s_pcc_mtcc_loop) return (uint32_t)zMTCC.zaddress;
  return (uint32_t)z_get_RVFI_DII_Execution_Packet_PC_rvfi_pc_wdata(zrvfi_pc_data);
}

svBit cheriot_sail_cosim_get_trap(void) {
  if (s_pcc_mtcc_loop) return 1;
  return z_get_RVFI_DII_Execution_Packet_InstMetaData_rvfi_trap(zrvfi_inst_data) != 0;
}

uint32_t cheriot_sail_cosim_get_rd_addr(void) {
  if (!zrvfi_int_data_present) return 0;
  return (uint32_t)z_get_RVFI_DII_Execution_Packet_Ext_Integer_rvfi_rd_addr(zrvfi_int_data);
}

uint32_t cheriot_sail_cosim_get_rd_wdata(void) {
  if (!zrvfi_int_data_present) return 0;
  return (uint32_t)z_get_RVFI_DII_Execution_Packet_Ext_Integer_rvfi_rd_wdata(zrvfi_int_data);
}

// Capability destination (rvfi_wC). cd_addr is 0 when the step wrote no capability register.
uint32_t cheriot_sail_cosim_get_cd_addr(void) {
  if (!zrvfi_cheri_data_present) return 0;
  uint64_t addr = 0, wtag = 0;
  get_cheri_output(&addr, &wtag);
  return (uint32_t)addr;
}

// CapBits: memory-format metadata in [63:32], address in [31:0].
uint64_t cheriot_sail_cosim_get_cd_wdata(void) {
  if (!zrvfi_cheri_data_present) return 0;
  lbits raw, v;
  CREATE(lbits)(&raw);
  CREATE(lbits)(&v);
  zrvfi_get_cheri_data(&raw, UNIT);
  struct zRVFI_DII_Execution_Packet_Ext_CHERI pkt = {.zbits = raw};
  z_get_RVFI_DII_Execution_Packet_Ext_CHERI_rvfi_cd_wdata(&v, pkt);
  uint64_t r = lbits_low64(&v);
  KILL(lbits)(&v);
  KILL(lbits)(&raw);
  return r;
}

svBit cheriot_sail_cosim_get_cd_wtag(void) {
  if (!zrvfi_cheri_data_present) return 0;
  uint64_t addr = 0, wtag = 0;
  get_cheri_output(&addr, &wtag);
  return (wtag & 1) != 0;
}

svBit cheriot_sail_cosim_get_mem_present(void) {
  return zrvfi_mem_data_present;
}

uint32_t cheriot_sail_cosim_get_mem_addr(void) {
  if (!zrvfi_mem_data_present) return 0;
  return (uint32_t)z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_addr(zrvfi_mem_data);
}

// The RVFI memory record has no tag (rvfi_write records the data bits only), so
// the tag a capability store left behind is read from the model's tag memory,
// which holds one tag per 8-byte granule (addr_to_tag_addr: address >> 3).
svBit cheriot_sail_cosim_get_mem_wtag(void) {
  if (!zrvfi_mem_data_present) return 0;
  uint64_t addr =
      z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_addr(zrvfi_mem_data);
  return read_tag_bool(addr >> 3);
}

uint32_t cheriot_sail_cosim_get_mem_rmask(void) {
  if (!zrvfi_mem_data_present) return 0;
  return (uint32_t)z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_rmask(zrvfi_mem_data);
}

uint32_t cheriot_sail_cosim_get_mem_wmask(void) {
  if (!zrvfi_mem_data_present) return 0;
  return (uint32_t)z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_wmask(zrvfi_mem_data);
}

// The data fields are wider than 64 bits in the model; a CHERIoT access is at most 8 bytes.
uint64_t cheriot_sail_cosim_get_mem_rdata(void) {
  if (!zrvfi_mem_data_present) return 0;
  lbits v;
  CREATE(lbits)(&v);
  z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_rdata(&v, zrvfi_mem_data);
  uint64_t r = lbits_low64(&v);
  KILL(lbits)(&v);
  return r;
}

uint64_t cheriot_sail_cosim_get_mem_wdata(void) {
  if (!zrvfi_mem_data_present) return 0;
  lbits v;
  CREATE(lbits)(&v);
  z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_wdata(&v, zrvfi_mem_data);
  uint64_t r = lbits_low64(&v);
  KILL(lbits)(&v);
  return r;
}
