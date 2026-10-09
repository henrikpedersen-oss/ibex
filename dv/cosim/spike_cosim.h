// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef SPIKE_COSIM_H_
#define SPIKE_COSIM_H_

#include <stdint.h>

#include <deque>
#include <memory>
#include <string>
#include <vector>

#include "cosim.h"
#include "riscv/devices.h"
#include "riscv/log_file.h"
#include "riscv/processor.h"
#include "riscv/simif.h"

#define IBEX_MARCHID 22

class SpikeCosim : public simif_t, public Cosim {
 private:
  // A sigsegv has been observed when deleting isa_parser_t instances under
  // Xcelium on CentOS 7. The root cause is unknown so for a workaround simply
  // use a raw pointer for isa_parser that never gets deleted. This produces a
  // minor memory leak but it is of little consequence as when SpikeCosim is
  // being deleted it is the end of simulation and the process will be
  // terminated shortly anyway.
#ifdef COSIM_SIGSEGV_WORKAROUND
  isa_parser_t *isa_parser;
#else
  std::unique_ptr<isa_parser_t> isa_parser;
#endif
  std::unique_ptr<processor_t> processor;
  std::unique_ptr<log_file_t> log;
  bus_t bus;
  std::vector<std::unique_ptr<mem_t>> mems;
  std::vector<std::string> errors;
  bool nmi_mode;

  typedef struct {
    uint8_t mpp;
    bool mpie;
    uint32_t epc;
    uint32_t cause;
  } mstack_t;

  mstack_t mstack;

  void fixup_csr(int csr_num, uint32_t csr_val);

  struct PendingMemAccess {
    DSideAccessInfo dut_access_info;
    uint32_t be_spike;
  };

  std::vector<PendingMemAccess> pending_dside_accesses;

  bool pending_iside_error;
  uint32_t pending_iside_err_addr;

  // True when set_mip() observed a 0->nonzero enabled-IRQ transition but the
  // DUT has not yet retired the first instruction of the handler.  Deferred
  // here so that step() can call early_interrupt_handle() only when rvfi_intr
  // confirms the DUT actually entered the handler (rather than abandoning the
  // IRQ while the controller sat in IRQ_TAKEN with handle_irq=0).
  bool pending_irq_early_handle;
  // pre_mip of the set_mip() call that set pending_irq_early_handle: the interrupt state the DUT
  // reported when it took the trap. Later items may sample mip again after the line has dropped.
  uint32_t pending_irq_pre_mip;

  // Zcmp instructions write several GPRs in a single Spike instruction, but Ibex
  // expands them into one RVFI retirement per register at the same PC. RVFI
  // carries one rd per retirement, so the DUT cannot present them all at once
  // and this is not a DUT bug.
  //
  //   cm.mvsa01 / cm.mva01s  2 GPRs
  //   cm.popret / cm.pop     up to 13 (ra, s0-s11), e.g. cm.pop {ra, s0-s7} = 9
  //
  // The first DUT retirement is checked against whichever of Spike's writes it
  // carries; the rest are queued here. Each subsequent step() at the same PC
  // consumes one entry and returns WITHOUT stepping Spike again -- otherwise the
  // ISS would run ahead of the DUT by a whole instruction.
  //
  // Matching is by register number throughout: Spike does not list the writes in
  // Ibex's micro-op order, so position cannot be relied on.
  // Register writes from the non-final operations of an expanded instruction.
  //
  // Ibex retires one RVFI item per operation of a Zcmp instruction, all at the
  // same PC, while the ISS executes the whole thing in one step. step() is told
  // via `more_ops` when further operations are coming; it records the DUT's
  // write here and does NOT step the ISS. On the final operation it steps once
  // and matches the ISS's register writes against this set plus the final
  // write.
  //
  // Deferring the step is what makes the memory side work: by the final
  // operation every access the instruction performs has been observed on the
  // DUT memory interface and queued in pending_dside_accesses, so the ISS's
  // accesses match against a complete set. Stepping on the first operation
  // instead left the ISS issuing (say) nine loads for a cm.pop against a queue
  // holding one, which surfaced as "A load at address ... was expected but
  // there are no pending accesses" and a manufactured load access fault.
  //
  // Matching is by register number: the ISS does not use Ibex's operation
  // order. For cm.pop the DUT's first load was sp+92 where the ISS's was sp+88.
  struct PendingGprWrite {
    uint32_t reg;
    uint32_t data;
  };
  std::vector<PendingGprWrite> deferred_dut_writes;
  uint32_t deferred_dut_writes_pc;

  typedef enum {
    kCheckMemOk,           // Checks passed and access succeeded in RTL
    kCheckMemCheckFailed,  // Checks failed
    kCheckMemBusError  // Checks passed, but access generated bus error in RTL
  } check_mem_result_e;

  check_mem_result_e check_mem_access(bool store, uint32_t addr, size_t len,
                                      const uint8_t *bytes);

  bool pc_is_mret(uint32_t pc);
  bool pc_is_load(uint32_t pc, uint32_t &rd_out);

  bool pc_is_debug_ebreak(uint32_t pc);
  bool check_debug_ebreak(uint32_t write_reg, uint32_t pc, bool sync_trap);

  bool check_gpr_write(const commit_log_reg_t::value_type &reg_change,
                       uint32_t write_reg, uint32_t write_reg_data);

  bool check_suppress_reg_write(uint32_t write_reg, uint32_t pc,
                                uint32_t &suppressed_write_reg);

  void on_csr_write(const commit_log_reg_t::value_type &reg_change);

  void leave_nmi_mode();

  bool change_cpuctrlsts_sync_exc_seen(bool flag);
  void set_cpuctrlsts_double_fault_seen();
  void handle_cpuctrl_exception_entry(bool was_debug_mode);

  void initial_proc_setup(uint32_t start_pc, uint32_t start_mtvec,
                          uint32_t mhpm_counter_num, bool rv32b_enabled);

  void early_interrupt_handle();
  // Takes the interrupt set_mip() deferred (pending_irq_early_handle), if it is still enabled.
  void take_deferred_irq();
  // Takes the highest-priority enabled interrupt in mip pre_val, with any halt request masked.
  // Records an error and returns false if none is pending.
  bool take_irq_before_halt();

  void misaligned_pmp_fixup();
  void misaligned_store_second_half(const DSideAccessInfo &dut);

  unsigned int insn_cnt;
  uint32_t mhpm_counter_num;

 public:
  SpikeCosim(const std::string &isa_string, uint32_t start_pc,
             uint32_t start_mtvec, const std::string &trace_log_path,
             bool secure_ibex, bool icache_en, uint32_t pmp_num_regions,
             uint32_t pmp_granularity, uint32_t mhpm_counter_num,
             uint32_t dm_start_addr, uint32_t dm_end_addr);

  // simif_t implementation
  virtual char *addr_to_mem(reg_t addr) override;
  virtual bool mmio_load(reg_t addr, size_t len, uint8_t *bytes) override;
  virtual bool mmio_store(reg_t addr, size_t len,
                          const uint8_t *bytes) override;
  virtual void proc_reset(unsigned id) override;
  virtual const char *get_symbol(uint64_t addr) override;

  // Cosim implementation
  void add_memory(uint32_t base_addr, size_t size) override;
  bool backdoor_write_mem(uint32_t addr, size_t len,
                          const uint8_t *data_in) override;
  bool backdoor_read_mem(uint32_t addr, size_t len, uint8_t *data_out) override;
  bool step(uint32_t write_reg, uint32_t write_reg_data, uint32_t pc,
            bool intr, bool sync_trap, bool suppress_reg_write, bool more_ops) override;

  bool check_retired_instr(uint32_t write_reg, uint32_t write_reg_data,
                           uint32_t dut_pc, bool suppress_reg_write);
  bool check_sync_trap(uint32_t write_reg, uint32_t pc,
                       uint32_t initial_spike_pc);
  void set_mip(uint32_t pre_mip, uint32_t post_mip) override;
  void set_nmi(bool nmi) override;
  void set_nmi_int(bool nmi_int, uint32_t mtval) override;
  void set_debug_req(bool debug_req) override;
  void set_mcycle(uint64_t mcycle) override;
  void set_csr(const int csr_num, const uint32_t new_val) override;
  uint32_t get_csr(const int csr_num) override;
  void set_ic_scr_key_valid(bool valid) override;
  void notify_dside_access(const DSideAccessInfo &access_info) override;
  // The spike co-simulator assumes iside and dside accesses within a step are
  // disjoint. If both access the same address within a step memory faults may
  // be incorrectly cause on one rather than the other or the access checking
  // will break.
  // TODO: Work on spike changes to remove this restriction
  void set_iside_error(uint32_t addr) override;
  const std::vector<std::string> &get_errors() override;
  void clear_errors() override;
  unsigned int get_insn_cnt() override;
};

#endif  // SPIKE_COSIM_H_
