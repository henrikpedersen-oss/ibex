// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// CHERIoT-Ibex's implementation-defined CSRs, implemented by the CHERIoT-Sail model's platform.
// Local addition (VENDORED_FROM 2026-10-09; ibex_cheriot_verification spec GAP-CS-3): the model
// gains the CSRs Ibex implements in CHERIoT mode and the model's platform lacked.
//
// The model calls these from is_CSR_defined, check_Counteren, readCSR, writeCSR,
// ext_check_CSR, trap_handler, exception_handler (MRET) and init_sys (riscv_sys_control.sail,
// riscv_insts_zicsr.sail, cheri_addr_checks.sail; the same calls are hand-patched into
// generated_definitions/c/riscv_rvfi_model_RV32.c). Everything an access does besides the value
// -- the illegal-instruction checks (privilege, writes to read-only CSRs), the ASR check, the
// write of rd, RVFI -- is the model's own CSR instruction semantics.
//
// Values come from the RTL source, never from the DUT at run time. Configuration: Ibex's
// `opentitan` configuration, the one the UVM and TestRIG benches build (ibex/ibex_configs.yaml:
// MHPMCounterNum 10, MHPMCounterWidth 32, DbgTriggerEn 1, ICache 1, SecureIbex 1 so
// DataIndTiming and DummyInstructions 1 (ibex_core.sv:195, ibex_top.sv:214); DbgHwBreakNum 1,
// the ibex_top.sv default). Line numbers below are ibex/rtl/ibex_cs_registers.sv unless stated.
//
// Only the counters' values are bench inputs: they depend on timing (wait cycles, the number of
// loads, ...) the model does not have, so the bench pushes the DUT's RVFI record of them before
// each step (ibex_platform_set_mhpmcounter), as for mcycle. The same applies to
// cpuctrlsts.ic_scr_key_valid, which follows the bench's scrambling-key handshake, and to the
// mcounteren_writable_i pin. Reset values, WARL masks and the side effects of traps and MRET on
// cpuctrlsts are modelled here.

#include "ibex_platform_csrs.h"

// opentitan configuration (see the header comment).
#define IBEX_MHPM_COUNTER_NUM 10u  // mhpmcounter3 .. mhpmcounter12 exist
#define IBEX_MHPM_COUNTER_BASE 3u   // MHPMCOUNTER_BASE, :185

// mcounteren / mcountinhibit: one flop per counter 0 .. MHPMCounterNum+2, bit 1 (time) tied to
// 0 (:1541-1559, :1697-1736): 0x1FFD.
#define IBEX_COUNTER_MASK \
  ((((uint64_t)1 << (IBEX_MHPM_COUNTER_NUM + IBEX_MHPM_COUNTER_BASE)) - 1) & ~(uint64_t)0x2)

// cpuctrlsts (:235-246 cpu_ctrl_sts_part_t, :674-678 read, :877-880 write, :1876-1972 masks):
//   [0] icache_enable  [1] data_ind_timing  [2] dummy_instr_en  [5:3] dummy_instr_mask
//   [6] sync_exc_seen  [7] double_fault_seen  -- all writable with ICache, DataIndTiming and
//   DummyInstructions on; [8] ic_scr_key_valid, read-only (:1922-1953); [31:9] zero.
#define IBEX_CPUCTRLSTS_WMASK         UINT64_C(0xFF)
#define IBEX_CPUCTRLSTS_SYNC_EXC_SEEN UINT64_C(0x40)
#define IBEX_CPUCTRLSTS_DOUBLE_FAULT  UINT64_C(0x80)

// tdata1 for the single trigger outside debug mode (:1836-1852): type 2, dmode 1, action 1
// (enter debug mode), m 1, u 1, execute = tmatch_control_q (reset 0, written only in debug mode,
// :1763-1768, which the model does not have).
#define IBEX_TDATA1_VALUE UINT64_C(0x28001048)

// State. Reset values: all 0 (ibex_csr ResetValue '0: :1725-1736 mcounteren, :1711-1717
// mcountinhibit, :1961-1972 cpuctrlsts).
static uint64_t s_mcounteren;
static uint64_t s_mcountinhibit;
static uint64_t s_cpuctrlsts;  // bits [7:0]
// Bench inputs.
static uint64_t s_mhpmcounter[32];
static bool     s_ic_scr_key_valid;
static bool     s_mcounteren_writable = true;

static bool is_hpm_idx_implemented(unsigned idx) {
  return idx >= IBEX_MHPM_COUNTER_BASE &&
         idx < IBEX_MHPM_COUNTER_BASE + IBEX_MHPM_COUNTER_NUM;
}

// The CSRs this file implements (in machine mode; CHERIoT is M-mode only).
bool ibex_csr_defined(mach_bits csr) {
  switch (csr) {
    case 0xF15:  // mconfigptr
    case 0x306:  // mcounteren
    case 0x30A:  // menvcfg
    case 0x31A:  // menvcfgh
    case 0x320:  // mcountinhibit (the model's own keeps bits 0 and 2 only; see writeCSR)
    case 0x7A0:  // tselect
    case 0x7A1:  // tdata1
    case 0x7A2:  // tdata2
    case 0x7A3:  // tdata3
    case 0x7A8:  // mcontext
    case 0x7AA:  // mscontext
    case 0x5A8:  // scontext
    case 0x7C0:  // cpuctrlsts
    case 0x7C1:  // secureseed
      return true;
    default:
      break;
  }
  return (csr >= 0x323 && csr <= 0x33F) ||  // mhpmevent3..31
         (csr >= 0xB03 && csr <= 0xB1F) ||  // mhpmcounter3..31
         (csr >= 0xB83 && csr <= 0xB9F) ||  // mhpmcounter3h..31h
         (csr >= 0xC03 && csr <= 0xC1F) ||  // hpmcounter3..31 (read-only)
         (csr >= 0xC83 && csr <= 0xC9F);    // hpmcounter3h..31h (read-only)
}

// Reads that need no Access System Registers permission: hpmcounter3..31(h), which the CHERIoT
// ISA's CSR allowlist names (archdoc chap-cheri-riscv.tex, "CSR allowlist": hpmcounter(h)
// read-only) and the RTL allows (ibex_decoder.sv:780-798). cycle/instret(h) are already in the
// model's own allowlist (cheri_addr_checks.sail ext_check_CSR).
bool ibex_csr_read_without_asr(mach_bits csr) {
  return (csr >= 0xC03 && csr <= 0xC1F) || (csr >= 0xC83 && csr <= 0xC9F);
}

mach_bits ibex_csr_read(mach_bits csr) {
  const unsigned idx = (unsigned)(csr & 0x1F);  // mhpmcounter_idx = csr_addr[4:0] (:408)
  switch (csr) {
    case 0xF15: return 0;                       // :440, ibex_pkg.sv:734 CSR_MCONFIGPTR_VALUE
    case 0x306: return s_mcounteren;            // :472
    case 0x30A: case 0x31A: return 0;           // :457, no write case
    case 0x320: return s_mcountinhibit;         // :576
    case 0x7A0: return 0;                       // :644-647, tselect_q (1 bit, DbgHwBreakNum 1)
    case 0x7A1: return IBEX_TDATA1_VALUE;       // :648-651
    case 0x7A2: return 0;                       // :652-655, tmatch_value_q, reset 0 (:1808-1819)
    case 0x7A3: case 0x7A8: case 0x7AA: case 0x5A8:
      return 0;                                 // :656-671
    case 0x7C0:                                 // :674-678
      return (s_cpuctrlsts & IBEX_CPUCTRLSTS_WMASK) | ((uint64_t)s_ic_scr_key_valid << 8);
    case 0x7C1: return 0;                       // :680-683, cannot be read
    default: break;
  }
  if (csr >= 0x323 && csr <= 0x33F) {
    // :577-586, :1589-1607: hardwired event selector, one-hot per implemented counter.
    return is_hpm_idx_implemented(idx) ? ((uint64_t)1 << (idx - IBEX_MHPM_COUNTER_BASE)) : 0;
  }
  if ((csr >= 0xB03 && csr <= 0xB1F) || (csr >= 0xC03 && csr <= 0xC1F)) {
    // :588-599, :615-627; unimplemented counters read 0 (:1687-1688).
    return is_hpm_idx_implemented(idx) ? (s_mhpmcounter[idx] & UINT64_C(0xFFFFFFFF)) : 0;
  }
  if ((csr >= 0xB83 && csr <= 0xB9F) || (csr >= 0xC83 && csr <= 0xC9F)) {
    // :601-612, :629-641. MHPMCounterWidth 32: the upper half is 0 on the DUT and in the record.
    return is_hpm_idx_implemented(idx) ? (s_mhpmcounter[idx] >> 32) : 0;
  }
  return 0;
}

unit ibex_csr_write(mach_bits csr, mach_bits value) {
  const unsigned idx = (unsigned)(csr & 0x1F);
  switch (csr) {
    case 0x306:  // :848 (only with mcounteren_writable_i On), :1551-1559
      if (s_mcounteren_writable) s_mcounteren = value & IBEX_COUNTER_MASK;
      return UNIT;
    case 0x320:  // :849, :1541-1549
      s_mcountinhibit = value & IBEX_COUNTER_MASK;
      return UNIT;
    case 0x7C0:  // :877-880 (exceptions take priority, but a CSR write that retires had none)
      s_cpuctrlsts = value & IBEX_CPUCTRLSTS_WMASK;
      return UNIT;
    default:
      break;
  }
  // mhpmcounterN (:851-862): the low 32 bits. The bench overwrites the value before the next
  // step from its RVFI record (which includes this write); kept so that a run without the bench
  // reads back what was written. mhpmcounterNh: MHPMCounterWidth 32 has no upper half.
  if (csr >= 0xB03 && csr <= 0xB1F && is_hpm_idx_implemented(idx)) {
    s_mhpmcounter[idx] = value & UINT64_C(0xFFFFFFFF);
  }
  // Writes with no effect: mconfigptr/hpmcounter* never get here (read-only, the model raises
  // an illegal instruction first); menvcfg(h), mhpmevent* (no write case); tselect/tdata1/tdata2
  // (written only in debug mode, :1763-1768); tdata3 and the context CSRs (no flops); secureseed
  // (reseeds the dummy-instruction LFSR, :1902, nothing readable).
  return UNIT;
}

// A synchronous exception (not an interrupt) taken outside debug mode, :936-946.
unit ibex_csr_sync_exception(unit u) {
  (void)u;
  if (s_cpuctrlsts & IBEX_CPUCTRLSTS_SYNC_EXC_SEEN) s_cpuctrlsts |= IBEX_CPUCTRLSTS_DOUBLE_FAULT;
  s_cpuctrlsts |= IBEX_CPUCTRLSTS_SYNC_EXC_SEEN;
  return UNIT;
}

// MRET, :963-966.
unit ibex_csr_mret(unit u) {
  (void)u;
  s_cpuctrlsts &= ~IBEX_CPUCTRLSTS_SYNC_EXC_SEEN;
  return UNIT;
}

// Core reset. The bench inputs are reset too and pushed again before the first step;
// mcounteren_writable is a pin, not core state, so it keeps its value.
unit ibex_csr_reset(unit u) {
  (void)u;
  s_mcounteren       = 0;
  s_mcountinhibit    = 0;
  s_cpuctrlsts       = 0;
  s_ic_scr_key_valid = false;
  for (unsigned i = 0; i < 32; i++) s_mhpmcounter[i] = 0;
  return UNIT;
}

void ibex_platform_set_mhpmcounter(unsigned idx, uint64_t value) {
  if (is_hpm_idx_implemented(idx)) s_mhpmcounter[idx] = value;
}

void ibex_platform_set_ic_scr_key_valid(bool valid) { s_ic_scr_key_valid = valid; }

void ibex_platform_set_mcounteren_writable(bool writable) { s_mcounteren_writable = writable; }
