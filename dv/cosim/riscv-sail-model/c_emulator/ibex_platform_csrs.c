// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Ibex's implementation-defined CSRs, implemented by the RISC-V Sail model's platform. Local
// addition (VENDORED_FROM 2026-10-12), the RISC-V counterpart of the CHERIoT model's file of the
// same name: the model gains the CSRs Ibex documents and the model lacked or read differently.
//
// Values come from Ibex's documentation (ibex/doc/03_reference/cs_registers.rst,
// performance_counters.rst; "doc" below), with the parameters of the `opentitan` configuration the
// TestRIG bench builds (ibex/ibex_configs.yaml: MHPMCounterNum 10, MHPMCounterWidth 32,
// DbgTriggerEn 1, ICache 1, SecureIbex 1; DbgHwBreakNum 1, the default). One exception, marked
// below: mhpmevent follows the RTL where the documentation disagrees with it (draft ticket in
// status/rtl_tickets.md (ibex_cheriot_verification)).
//
// The model calls these from is_CSR_defined, check_Counteren, readCSR, writeCSR, trap_handler,
// exception_handler (MRET) and init_sys, hand-patched into
// generated_definitions/c/riscv_rvfi_model_RV32.c. Everything else an access does -- privilege
// and read-only checks, the write of rd, RVFI -- is the model's own CSR instruction semantics.
//
// Only the counters' values are bench inputs: they depend on timing the model does not have, so
// the bench pushes the DUT's RVFI record of them before each step, as for mcycle. The same holds
// for cpuctrlsts.ic_scr_key_valid (the scrambling-key handshake).

#include "ibex_platform_csrs.h"

#define IBEX_MHPM_COUNTER_NUM  10u  // opentitan; mhpmcounter3 .. mhpmcounter12 count
#define IBEX_MHPM_COUNTER_BASE 3u

// mcounteren / mcountinhibit: one bit per counter 0 .. MHPMCounterNum+2, no time counter (bit 1
// zero); "bits above MHPMCounterNum + 2 always read as zero" (doc cs_registers.rst:238).
#define IBEX_COUNTER_MASK \
  ((((uint64_t)1 << (IBEX_MHPM_COUNTER_NUM + IBEX_MHPM_COUNTER_BASE)) - 1) & ~(uint64_t)0x2)

// cpuctrlsts (doc cs_registers.rst:593-640): [0] icache_enable, [1] data_ind_timing,
// [2] dummy_instr_en, [5:3] dummy_instr_mask, [6] sync_exc_seen, [7] double_fault_seen -- all
// writable with ICache and SecureIbex on; [8] ic_scr_key_valid, read-only; the rest zero.
#define IBEX_CPUCTRLSTS_WMASK         UINT64_C(0xFF)
#define IBEX_CPUCTRLSTS_SYNC_EXC_SEEN UINT64_C(0x40)
#define IBEX_CPUCTRLSTS_DOUBLE_FAULT  UINT64_C(0x80)

// tdata1 (doc cs_registers.rst:414-468): type 2, dmode 1, action 1, m 1, u 1; execute is written
// only in debug mode, which the model does not have, so it stays 0.
#define IBEX_TDATA1_VALUE UINT64_C(0x28001048)

// mseccfg (Smepmp 1.0, doc cs_registers.rst:374-395): [0] MML and [1] MMWP sticky, [2] RLB, which
// cannot be set while any pmpcfg.L is set; reset 0; mseccfgh reads 0 and ignores writes.
#define IBEX_MSECCFG_MML  UINT64_C(0x1)
#define IBEX_MSECCFG_MMWP UINT64_C(0x2)
#define IBEX_MSECCFG_RLB  UINT64_C(0x4)

uint64_t sys_pmp_count(unit);

// State; reset values 0 (doc: counters enabled after reset, performance_counters.rst:59).
static uint64_t s_mseccfg;
static bool     s_any_pmp_locked;
static uint64_t s_mcounteren;
static uint64_t s_mcountinhibit;
static uint64_t s_cpuctrlsts;
// Bench inputs.
static uint64_t s_mhpmcounter[32];
static bool     s_ic_scr_key_valid;

static bool is_hpm_idx_implemented(unsigned idx) {
  return idx >= IBEX_MHPM_COUNTER_BASE &&
         idx < IBEX_MHPM_COUNTER_BASE + IBEX_MHPM_COUNTER_NUM;
}

static bool is_user_counter(mach_bits csr) {
  return (csr >= 0xC03 && csr <= 0xC1F) || (csr >= 0xC83 && csr <= 0xC9F);
}

bool ibex_csr_defined(mach_bits csr) {
  switch (csr) {
    case 0x747:  // mseccfg, only with PMP (doc cs_registers.rst:395)
    case 0x757:  // mseccfgh
      return sys_pmp_count(UNIT) > 0;
    case 0xF15:  // mconfigptr (RTL reads 0; not in the doc's table, draft ticket)
    case 0x306:  // mcounteren
    case 0x30A:  // menvcfg (RTL reads 0; not in the doc's table, draft ticket)
    case 0x31A:  // menvcfgh
    case 0x320:  // mcountinhibit
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
  return (csr >= 0x323 && csr <= 0x33F) ||  // mhpmevent3..31 (doc: all exist, WARL)
         (csr >= 0xB03 && csr <= 0xB1F) ||  // mhpmcounter3..31
         (csr >= 0xB83 && csr <= 0xB9F) ||  // mhpmcounter3h..31h
         is_user_counter(csr);              // hpmcounter3..31(h), read-only
}

// U-mode access to hpmcounterX(h): mcounteren bit X (doc performance_counters.rst:66-78).
bool ibex_csr_user_counter_enabled(mach_bits csr) {
  return is_user_counter(csr) && ((s_mcounteren >> (csr & 0x1F)) & 1);
}

mach_bits ibex_csr_read(mach_bits csr) {
  const unsigned idx = (unsigned)(csr & 0x1F);
  switch (csr) {
    case 0x747: return s_mseccfg;
    case 0x757: return 0;
    case 0xF15: case 0x30A: case 0x31A: return 0;
    case 0x306: return s_mcounteren;
    case 0x320: return s_mcountinhibit;
    case 0x7A0: return 0;  // doc :397-412: reset 0, one trigger, so index 0 only
    case 0x7A1: return IBEX_TDATA1_VALUE;
    case 0x7A2: return 0;  // tmatch_value, written only in debug mode, reset 0
    case 0x7A3: case 0x7A8: case 0x7AA: case 0x5A8:
      return 0;            // doc :484-515: not supported, read as zero
    case 0x7C0:
      return (s_cpuctrlsts & IBEX_CPUCTRLSTS_WMASK) | ((uint64_t)s_ic_scr_key_valid << 8);
    case 0x7C1: return 0;  // doc :643: cannot be read
    default: break;
  }
  if (csr >= 0x323 && csr <= 0x33F) {
    // Follows the RTL (bit idx-3), not the doc (bit idx, performance_counters.rst:134-150):
    // draft ticket "mhpmevent3-12 read values disagree with the documentation".
    return is_hpm_idx_implemented(idx) ? ((uint64_t)1 << (idx - IBEX_MHPM_COUNTER_BASE)) : 0;
  }
  // "Unavailable counters always read 0" (doc performance_counters.rst:93).
  if ((csr >= 0xB03 && csr <= 0xB1F) || (csr >= 0xC03 && csr <= 0xC1F)) {
    return is_hpm_idx_implemented(idx) ? (s_mhpmcounter[idx] & UINT64_C(0xFFFFFFFF)) : 0;
  }
  if ((csr >= 0xB83 && csr <= 0xB9F) || (csr >= 0xC83 && csr <= 0xC9F)) {
    return is_hpm_idx_implemented(idx) ? (s_mhpmcounter[idx] >> 32) : 0;
  }
  return 0;
}

unit ibex_csr_write(mach_bits csr, mach_bits value) {
  const unsigned idx = (unsigned)(csr & 0x1F);
  switch (csr) {
    case 0x747: {
      // Smepmp 1.0, chapter 2 items 2-4: MML and MMWP are sticky; RLB stays 0 once clear while
      // any pmpcfg.L is set, otherwise follows the write.
      uint64_t next = s_mseccfg | (value & (IBEX_MSECCFG_MML | IBEX_MSECCFG_MMWP));
      bool rlb_frozen = !(s_mseccfg & IBEX_MSECCFG_RLB) && s_any_pmp_locked;
      if (!rlb_frozen) next = (next & ~IBEX_MSECCFG_RLB) | (value & IBEX_MSECCFG_RLB);
      s_mseccfg = next;
      return UNIT;
    }
    case 0x306: s_mcounteren = value & IBEX_COUNTER_MASK; return UNIT;
    case 0x320: s_mcountinhibit = value & IBEX_COUNTER_MASK; return UNIT;
    case 0x7C0: s_cpuctrlsts = value & IBEX_CPUCTRLSTS_WMASK; return UNIT;
    default: break;
  }
  // mhpmcounterN: the bench overwrites it before the next step from its RVFI record (which
  // includes this write); kept so that a run without the bench reads back what was written.
  // MHPMCounterWidth 32: no upper half.
  if (csr >= 0xB03 && csr <= 0xB1F && is_hpm_idx_implemented(idx)) {
    s_mhpmcounter[idx] = value & UINT64_C(0xFFFFFFFF);
  }
  // All others: no effect (read-only zero, hardwired, or written only in debug mode).
  return UNIT;
}

// A synchronous exception (doc cpuctrlsts sync_exc_seen / double_fault_seen, double-fault detect).
unit ibex_csr_sync_exception(unit u) {
  (void)u;
  if (s_cpuctrlsts & IBEX_CPUCTRLSTS_SYNC_EXC_SEEN) s_cpuctrlsts |= IBEX_CPUCTRLSTS_DOUBLE_FAULT;
  s_cpuctrlsts |= IBEX_CPUCTRLSTS_SYNC_EXC_SEEN;
  return UNIT;
}

// MRET clears sync_exc_seen (doc cpuctrlsts table).
unit ibex_csr_mret(unit u) {
  (void)u;
  s_cpuctrlsts &= ~IBEX_CPUCTRLSTS_SYNC_EXC_SEEN;
  return UNIT;
}

unit ibex_csr_reset(unit u) {
  (void)u;
  s_mseccfg          = 0;
  s_any_pmp_locked   = false;
  s_mcounteren       = 0;
  s_mcountinhibit    = 0;
  s_cpuctrlsts       = 0;
  s_ic_scr_key_valid = false;
  for (unsigned i = 0; i < 32; i++) s_mhpmcounter[i] = 0;
  return UNIT;
}

// ---- Smepmp 1.0 ------------------------------------------------------------------------------

bool ibex_mseccfg_mml(void) { return (s_mseccfg & IBEX_MSECCFG_MML) != 0; }
bool ibex_mseccfg_rlb(void) { return (s_mseccfg & IBEX_MSECCFG_RLB) != 0; }
void ibex_mseccfg_set_any_locked(bool any_locked) { s_any_pmp_locked = any_locked; }

// Permissions for an access matching an entry while mseccfg.MML is set: Smepmp 1.0 section 2.1
// ("Truth table when mseccfg.MML is set"). Index: L<<3 | R<<2 | W<<1 | X; bits: R 1, W 2, X 4.
enum { P_R = 1, P_W = 2, P_X = 4 };
static const uint8_t kMmlM[16] = {
  0,         0,   P_R | P_W, P_R | P_W, 0,   0,         0,         0,          // L=0
  0,         P_X, P_X,       P_R | P_X, P_R, P_R | P_X, P_R | P_W, P_R};       // L=1
static const uint8_t kMmlSU[16] = {
  0,         P_X, P_R,       P_R | P_W, P_R, P_R | P_X, P_R | P_W, P_R | P_W | P_X,
  0,         0,   P_X,       P_X,       0,   0,         0,         P_R};

bool ibex_smepmp_mml_perms(uint64_t cfg, int acc, bool machine) {
  const unsigned idx = (unsigned)(((cfg >> 7) & 1) << 3 | (cfg & 1) << 2 | ((cfg >> 1) & 1) << 1 |
                                  ((cfg >> 2) & 1));
  const uint8_t p = machine ? kMmlM[idx] : kMmlSU[idx];
  switch (acc) {
    case 0:  return (p & P_R) != 0;
    case 1:  return (p & P_W) != 0;
    case 2:  return (p & (P_R | P_W)) == (P_R | P_W);
    default: return (p & P_X) != 0;
  }
}

// Items 3 (MMWP: default deny) and 4c (MML: M-mode executes only from a matching rule).
bool ibex_smepmp_m_unmatched_allowed(bool execute) {
  if (s_mseccfg & IBEX_MSECCFG_MMWP) return false;
  if ((s_mseccfg & IBEX_MSECCFG_MML) && execute) return false;
  return true;
}

// The model's pmpWriteCfg (riscv_pmp_regs.sail) plus Smepmp items 2a and 4a/4b. cfg bits: R 0,
// W 1, X 2, A 4:3, L 7.
uint64_t ibex_smepmp_write_cfg(uint64_t old_cfg, uint64_t v, uint64_t grain) {
  const bool mml = (s_mseccfg & IBEX_MSECCFG_MML) != 0;
  const bool rlb = (s_mseccfg & IBEX_MSECCFG_RLB) != 0;
  if ((old_cfg & 0x80) && !rlb) return old_cfg;  // locked (2a: RLB bypasses the lock)
  uint64_t cfg = v & 0x9f;
  // R=0 W=1 is reserved without MML: "will be treated by the core as Read/Write permission = 0"
  // (cs_registers.rst, PMP Configuration Register). R and W are cleared and X kept as written: the
  // model's own pmpWriteCfg cleared X too, which the manual does not say (TestRIG csr generator
  // 2026-10-18: pmpcfg rtl 0x04 / model 0x00). With MML it encodes a Shared-Region (4a).
  if (!mml && (cfg & 0x3) == 0x2) cfg &= ~UINT64_C(0x3);
  // G >= 1: NA4 is not selectable (set to OFF, as the model's own pmpWriteCfg).
  if (grain >= 1 && ((cfg >> 3) & 0x3) == 0x2) cfg &= ~UINT64_C(0x18);
  // 4b: with MML, a new executable M-mode-only rule (LRWX 1001, 1101) or locked Shared-Region
  // (1010, 1011) is refused unless RLB: the write is ignored, pmpcfg unchanged.
  if (mml && !rlb && (cfg & 0x80)) {
    const unsigned rwx = (unsigned)(cfg & 0x7);  // X<<2 | W<<1 | R
    if (rwx == 0x4 || rwx == 0x5 || rwx == 0x2 || rwx == 0x6) return old_cfg;
  }
  return cfg;
}

void ibex_platform_set_mhpmcounter(unsigned idx, uint64_t value) {
  if (is_hpm_idx_implemented(idx)) s_mhpmcounter[idx] = value;
}

void ibex_platform_set_ic_scr_key_valid(bool valid) { s_ic_scr_key_valid = valid; }
