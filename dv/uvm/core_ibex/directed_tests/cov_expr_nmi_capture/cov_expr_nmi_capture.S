# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_expr_nmi_capture -- NMIs, interrupts and a withdrawn halt request around an empty ID
# =============================================================================
# RISC-V mode (cheriot_enable_i Off). Cosim off: the program checks itself (trap log below).
# rtl_test core_ibex_stall_events_test (see its header) with:
#   +gnt_trig_lo/hi = [TRIG, TRIG + 0x3ff]: the offset of a data access picks what its grant (G)
#     raises: T_IRQ irq_external_i from G + 2, T_NMI irq_nm_i from G + 2 (G + 4 with
#     T_NMI_LATE, +gnt_nmi_late_cycles default 2) (both held until the
#     core takes an interrupt), T_DPULSE debug_req in cycle G + 1 only (withdrawn), T_NMI_IRQ
#     irq_nm_i from the second cycle after the next IRQ_TAKEN, held until taken;
#   +mem_mode_on_write = MEMMODE: M_PIPE, data responses 6..16 cycles after the grant and
#     instruction responses 60..124 cycles apart (each counted from the previous response, or from
#     the request if none is queued), so after a fetched word, or a redirect, nothing more is
#     fetched for 60 cycles: ID stays empty while the access is outstanding in WB. The 6-cycle
#     minimum response gives the irq agent, which may drive two items started together a cycle or
#     two apart, time to raise its lines before the controller takes the interrupt;
#   +dside_intg_err_lo/hi = INTG_ADDR: loads of it return bad integrity (internal NMI);
#   +stall_events_bus_alerts=2: one bus alert per integrity error (sections A, B), no other alert;
#   +enable_bad_intg_on_uninit_access=0: TRIG and INTG_ADDR are not part of the image;
#   +disable_fetch_enable_seq=1: no fetch-enable drops.
#
# Expression-coverage targets (regression 26231 after UNR, 2026-10-11,
# formal_cov/unr/uncovered_after_exclude.txt). RVFI rows are ibex_core.sv `ifdef RVFI; they stay
# in the coverage numbers (coverage_waivers_xlm.tcl excludes only g_rvfi_stages).
#   ibex_controller.sv:741 IRQ_TAKEN `irq_nm_int & !irq_nm_ext_i`, row (1, 1), and
#   ibex_controller.sv:410 g_intg_irq_int `entering_nmi & !irq_nm_ext_i`, row (1, 1): the
#     external NMI taken while the internal one is pending (it stays pending). Sections A, B.
#   ibex_core.sv:2017 RVFI capture `~instr_valid_id & (new_debug_req | new_irq | new_nmi |
#     new_nmi_int) & (~captured_valid | (new_debug_req & ~captured_debug_req) | (new_nmi &
#     ~captured_nmi & ~captured_debug_req))`, the rows with new_nmi = 1 over a valid capture:
#     6.1.3  recapture, nothing else new: internal NMI captured, then the external NMI (A);
#     6.1.6  the same with an interrupt pending and enabled (B);
#     6.1.12 no recapture, a debug request captured and withdrawn (D, E);
#     6.1.15 the same with an interrupt pending and enabled (D).
#   ibex_core.sv:2050 RVFI `IRQ_TAKEN & handle_irq & ~instr_valid_id & ready_wb &
#     ~captured_taken`, row captured_taken = 1: a second IRQ_TAKEN (an NMI) before the first
#     handler's first instruction reaches ID, with the capture still holding the withdrawn
#     request, so not recaptured (E). Its other two rows are waived (PipeEmptyOnIrq).
#
# Why each section reaches its rows (ibex_controller.sv, ibex_core.sv RVFI block):
#   A  [c.lw L1 (INTG_ADDR, bad integrity) ; c.lw L2 (T_NMI)] share one 32-bit word, so L2 is in
#      ID from L1's grant + 1. It waits for L1's response (R1), issues then and leaves ID at its
#      grant G2 >= R1. The internal NMI is pending from R1 + 1, after which halt_if lets nothing
#      into ID; the word behind is 60+ cycles away, which covers G2 = R1 (nothing would hold it
#      out at R1 + 1). So ID is empty from G2 + 1 and captures the internal NMI there (its first
#      empty cycle with the NMI pending). irq_nm_i rises at G2 + 4 (T_NMI_LATE), with ID still
#      empty and L2 still outstanding (response at G2 + 6 or later), so the controller is still
#      in DECODE and not in NMI mode: new_nmi recaptures (6.1.3). Raised at G2 + 2 (plain T_NMI,
#      to 2026-10-18) it could fall in that first capture cycle itself (the irq agent drives a
#      cycle or two after it starts, and with G2 = R1 the capture is a cycle late): one capture
#      then took both NMIs (captured_nmi = 1) and 6.1.3 / 6.1.6 were never hit. IRQ_TAKEN follows L2's
#      response with both NMIs pending: the external one is taken, the internal one stays
#      (741, 410). Only the load right after the faulting one executes first, as
#      exception_interrupts.rst allows.
#   B  As A with T_NMI | T_NMI_LATE | T_IRQ and mie.MEIE / mstatus.MIE set: the interrupt from
#      G2 + 2 is not captured (captured_valid), and new_irq = 1 when the NMI arrives (6.1.6). The
#      bench drops irq_external_i at the IRQ_TAKEN (the NMI's), so no MEI is ever taken.
#   D  A lone 32-bit load at T_DPULSE | T_NMI | T_IRQ (MIE on): ID is empty from G + 1 (next
#      word 60+ cycles away) while the load is outstanding (id_wb_pending, no debug entry), so
#      the pulse is captured at G + 1 (captured_debug_req = 1) and lost; at G + 2 the NMI and
#      the interrupt arrive and are not recaptured (6.1.15). The NMI is taken after the
#      response; no debug entry.
#   E  A lone load at T_DPULSE | T_NMI_IRQ | T_IRQ (MIE on): the pulse is captured at G + 1 and
#      lost, the interrupt (G + 2) is not recaptured, and is taken after the response (IRQ_TAKEN
#      #1, which sets captured_taken). Its handler's first word is 60+ cycles away, so ID is still
#      empty when irq_nm_i rises two cycles later: no recapture (captured_debug_req), 6.1.12
#      (MIE is clear by then), and the NMI is taken (IRQ_TAKEN #2) with captured_taken = 1.
#
# Expected behaviour (not taken from the RTL):
#   - doc/03_reference/exception_interrupts.rst: the external NMI (mcause 0x8000001F) takes
#     priority over the internal one, which stays pending; the load-integrity internal NMI is
#     mcause 0xFFFFFFE0 with mtval = the load address, does not write rd, and is taken after the
#     handler's mret (NMIs do not nest), before the instruction mret returns to; NMI > external
#     interrupt; a recoverable NMI taken at the entry of another trap handler saves and its mret
#     restores mepc and mcause (mstack), so that handler then sees its own trap.
#   - RISC-V Debug Spec: a halt request withdrawn before the hart halts need not halt it; the
#     bench raises it while the core cannot halt (ID empty, an access outstanding), so no debug
#     entry may happen (an entry fails the test, code 0x200 | section).
#   - mepc of an interrupt taken with ID empty is the next instruction to execute.
#
# Failure: TEST_FAIL with TESTNUM (gp); trap log entries are (mcause, mepc, mtval):
#   A 10 entries != 2   11/12 first: mcause not 0x8000001F / mepc not A's resume point
#     13/14/15 second: mcause not 0xFFFFFFE0 / mepc not the resume point / mtval not INTG_ADDR
#     16 the faulting load wrote its rd
#   B 20-26 as A
#   D 40 entries != 1   41/42 mcause not 0x8000001F / mepc not D's resume point
#   E 50 entries != 2   51/52 first: mcause not 0x8000001F / mepc not the MEI vector (mtvec +
#     0x2c: taken before the MEI handler's first instruction)   53/54 second: mcause not
#     0x8000000B / mepc not E's resume point (the MEI's own, restored by the NMI's mret)
#   0x100 | code  an exception      0x200 | code  a debug-mode entry
#
# Proving it can fail (build-time switch, not in the testlist):
#   -DCOV_EXPR_INJECT_FAIL  section A's second load drops T_NMI: no external NMI -> TESTNUM 10

#include "riscv_test.h"
#include "test_macros.h"

#define TRIG          0x80100000          /* +gnt_trig_lo/hi = 80100000 / 801003ff */
#define T_IRQ         0x008
#define T_NMI         0x020
#define T_NMI_LATE    0x004               /* with T_NMI: irq_nm_i +gnt_nmi_late_cycles (2) later */
#define T_DPULSE      0x100
#define T_NMI_IRQ     0x200
#define MEMMODE       0x80100800          /* +mem_mode_on_write=80100800 */
#define M_PIPE        0x3C0006            /* data responses 6..16, instruction 60..124 apart */
#define INTG_ADDR     0x80104000          /* +dside_intg_err_lo/hi = 80104000 / 80104003 */
#define POISON        0x0BADF00D
#define CAUSE_NMI_EXT 0x8000001f
#define CAUSE_NMI_INT 0xffffffe0
#define CAUSE_MEI     0x8000000b
#define LOG_SZ        12

#ifdef COV_EXPR_INJECT_FAIL
#define A_OFF         0
#else
#define A_OFF         (T_NMI | T_NMI_LATE)
#endif

# Registers: a0 = TRIG, a1 = INTG_ADDR, s9 = trap log base, s8 = next free log entry (the
# handlers advance it; they use t5/t6 only).

# Set the memory agents' timing; the load and nops keep the next access out of the change-over.
.macro MEM_MODE v
  li    t0, MEMMODE
  li    t1, \v
  sw    t1, 0(t0)
  lw    t1, 0(t0)
  .rept 4
  nop
  .endr
.endm

.macro LOG_COUNT n, code
  li    TESTNUM, \code
  sub   t0, s8, s9
  li    t1, (\n) * LOG_SZ
  bne   t0, t1, fail
.endm

# Log entry \idx, word \fld (0 mcause, 4 mepc, 8 mtval) must equal register \reg.
.macro LOG_CHK idx, fld, reg, code
  li    TESTNUM, \code
  lw    t0, ((\idx) * LOG_SZ + (\fld))(s9)
  bne   t0, \reg, fail
.endm

.macro IRQ_ON
  li    t0, MIP_MEIP
  csrs  mie, t0
  csrsi mstatus, MSTATUS_MIE
.endm

.macro IRQ_OFF
  csrci mstatus, MSTATUS_MIE
  li    t0, MIP_MEIP
  csrc  mie, t0
.endm

  .option norvc
  .option norelax

#----------------------------------------------------------------------------------------------
# Debug halt / exception addresses (DEBUG_MODE_HALT_ADDR = BOOT_ADDR, _EXCEPTION_ADDR = + 8):
# no section may enter debug mode.
    .section .text.init
    j       dbg_entry
    nop
    j       dbg_entry

#----------------------------------------------------------------------------------------------
    .text

# mtvec (vectored, as Ibex forces): exceptions at +0, the machine external interrupt at +0x2c,
# NMIs at +0x7c.
    .balign 256
mtvec_table:
    j       exc_handler
    .org    mtvec_table + 0x2c
mei_vector:
    j       trap_log
    .org    mtvec_table + 0x7c
    j       trap_log

exc_handler:
    ori     TESTNUM, TESTNUM, 0x100
    j       fail

# NMIs and the external interrupt: log (mcause, mepc, mtval) and return.
trap_log:
    csrr    t5, mcause
    sw      t5, 0(s8)
    csrr    t5, mepc
    sw      t5, 4(s8)
    csrr    t5, mtval
    sw      t5, 8(s8)
    addi    s8, s8, LOG_SZ
    mret

dbg_entry:
    ori     TESTNUM, TESTNUM, 0x200
    j       fail

#----------------------------------------------------------------------------------------------
RVTEST_RV32M
RVTEST_CODE_BEGIN

  la      t0, mtvec_table
  csrw    mtvec, t0
  la      s9, trap_log_buf
  li      a0, TRIG
  li      a1, INTG_ADDR
  MEM_MODE M_PIPE
  # Words fetched ahead before the change-over came at the old speed; use them up so that A's
  # word and the one behind it are 60+ cycles apart (B, D and E follow a CSR write, which
  # flushes the pipeline and refetches).
  .rept 16
  nop
  .endr

  # ---- A: internal NMI captured with ID empty, then the external NMI ----
  mv      s8, s9
  li      a2, POISON
  .balign 4
  .option push
  .option rvc
  c.lw    a2, 0(a1)                 # L1: bad integrity, internal NMI
  c.lw    a3, A_OFF(a0)             # L2: irq_nm_i from its grant + 4
  .option pop
a_resume:
  LOG_COUNT 2, 10
  li      t2, CAUSE_NMI_EXT
  LOG_CHK 0, 0, t2, 11
  la      t3, a_resume
  LOG_CHK 0, 4, t3, 12
  li      t2, CAUSE_NMI_INT
  LOG_CHK 1, 0, t2, 13
  LOG_CHK 1, 4, t3, 14
  LOG_CHK 1, 8, a1, 15
  li      TESTNUM, 16
  li      t0, POISON
  bne     a2, t0, fail

  # ---- B: as A with the external interrupt pending and enabled as the NMI arrives ----
  mv      s8, s9
  li      a2, POISON
  IRQ_ON
  .balign 4
  .option push
  .option rvc
  c.lw    a2, 0(a1)
  c.lw    a3, (T_NMI | T_NMI_LATE | T_IRQ)(a0)
  .option pop
b_resume:
  IRQ_OFF
  LOG_COUNT 2, 20
  li      t2, CAUSE_NMI_EXT
  LOG_CHK 0, 0, t2, 21
  la      t3, b_resume
  LOG_CHK 0, 4, t3, 22
  li      t2, CAUSE_NMI_INT
  LOG_CHK 1, 0, t2, 23
  LOG_CHK 1, 4, t3, 24
  LOG_CHK 1, 8, a1, 25
  li      TESTNUM, 26
  li      t0, POISON
  bne     a2, t0, fail

  # ---- D: withdrawn halt request captured, then the NMI and the interrupt ----
  mv      s8, s9
  li      a4, TRIG + T_DPULSE
  IRQ_ON
  lw      a3, (T_NMI | T_IRQ)(a4)
d_resume:
  IRQ_OFF
  LOG_COUNT 1, 40
  li      t2, CAUSE_NMI_EXT
  LOG_CHK 0, 0, t2, 41
  la      t3, d_resume
  LOG_CHK 0, 4, t3, 42

  # ---- E: withdrawn halt request, the interrupt taken, the NMI before its handler runs ----
  mv      s8, s9
  li      a5, TRIG + T_DPULSE + T_NMI_IRQ
  IRQ_ON
  lw      a3, T_IRQ(a5)
e_resume:
  IRQ_OFF
  LOG_COUNT 2, 50
  li      t2, CAUSE_NMI_EXT
  LOG_CHK 0, 0, t2, 51
  la      t3, mei_vector
  LOG_CHK 0, 4, t3, 52
  li      t2, CAUSE_MEI
  LOG_CHK 1, 0, t2, 53
  la      t3, e_resume
  LOG_CHK 1, 4, t3, 54

  MEM_MODE 0
  j       pass

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .balign 16
trap_log_buf:
  .zero 64
RVTEST_DATA_END
