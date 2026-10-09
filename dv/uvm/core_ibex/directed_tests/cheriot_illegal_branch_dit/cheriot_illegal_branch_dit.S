# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_illegal_branch_dit -- branches and jumps naming x16-x31 in CHERIoT
# mode, with data-independent timing off and on
# =============================================================================
# In CHERIoT mode x16-x31 do not exist (RV32E register file): an instruction naming one
# is illegal (CHERIoT-Sail Error_not_rv32e_register -> handle_illegal: mcause 2, mtval 0,
# MEPCC at the instruction). ibex makes it illegal through illegal_reg_16
# (ibex_decoder.sv), which -- unlike illegal_insn -- does not clear branch_in_dec_o /
# jump_in_dec_o. With cpuctrlsts.data_ind_timing set, stall_branch includes
# data_ind_timing_i (ibex_id_stage.sv), so such a branch may stall in ID like a branch
# although it is illegal, which the RTL assertion IllegalInsnStallMustBeMemStall forbids
# (tech-notes/rtl_todo.md, "Unconfirmed: a branch naming x16-x31 ..."). This test is the
# directed check of that: if the stall happens, the assertion fails the simulation.
#
# The same table of encodings runs twice (illegal_sweep.h, each slot must trap with
# mcause 2, mtval 0, MEPCC = the slot):
#   pass 1  data-independent timing off;
#   pass 2  after csrsi cpuctrlsts, 2. The bit is read back first, so pass 2 cannot
#           silently run with data-independent timing off (DataIndTiming = SecureIbex: the
#           opentitan configuration has it).
# Both passes, and the cpuctrlsts accesses, are also checked by the CHERIoT-Sail cosim: the
# model's platform has Ibex's cpuctrlsts (spec GAP-CS-3). Pass 2 also relies on the RTL
# assertions, which no model can stand in for.
# Codes: 2000 + 4 * slot + k for pass 1, 3000 + 4 * slot + k for pass 2 (k as in
# illegal_sweep.h: 0 executed instead of trapping, 1 mcause, 2 mtval, 3 MEPCC);
# 1999 / 2999 liveness; 2998 data_ind_timing did not read back as set.
#include "cheriot_dv.h"
#include "cheriot_illegal_sweep/illegal_sweep.h"
    .option norelax
    .text
    .globl main
main:
    cmove     a2, ra                        # the crt's return sentry; the sweep never writes a2
    li        a5, 0                         # ca5: integer, untagged
    li        t2, 2000
    jal       ra, run_sweep
    bnez      a0, .Lexit

    csrsi     0x7c0, 2                      # cpuctrlsts.data_ind_timing
    csrr      t0, 0x7c0
    andi      t0, t0, 2
    li        a0, 2998
    beqz      t0, .Lexit
    li        t2, 3000
    jal       ra, run_sweep
    bnez      a0, .Lexit
    csrci     0x7c0, 2
    li        a0, 0
.Lexit:
    cmove     ra, a2
    ret

# One pass over the table. t2 = code base (2000 or 3000). Returns a0 = 0 or a failure code.
# SWEEP clobbers s0, s1, a3, a4, t0-t2 and ca0, never a1, a2, a5 or cra (it moves between slots
# with jalr zero / mret), so the code base is kept in a1 and the return sentry stays in cra.
run_sweep:
    mv        a1, t2
    SWEEP     sweep_start, sweep_end, 0
    csrw      mscratch, a3                  # failure count, for the log
    li        a0, 0
    beqz      a4, 1f
    add       a0, a4, a1                    # code base + 4 * slot + k
    ret
1:  j         .Lload_nslot                  # NSLOT is final only after the table (gas .set)
.Lnslot_loaded:
    beq       s1, t0, 2f
    addi      a0, a1, -1                    # liveness: 1999 / 2999
2:  ret

    .option push
    .option norvc
    .balign 8
sweep_start:
    E32 0x01250263                          # beq  a0, s2, .+4   (rs2 = x18)
    E32 0x00a91263                          # bne  s2, a0, .+4   (rs1 = x18)
    E32 0x010fc263                          # blt  t6, a6, .+4   (x31, x16)
    E32 0x0149f263                          # bgeu s3, s4, .+4   (x19, x20)
    E32 0x004008ef                          # jal  a7, .+4       (rd = x17)
sweep_end:
    .option pop

# li t0, NSLOT must come after every SLOT: .set gives a symbol its value at that point in the
# file, so before the table it is 0 and the liveness check can never pass.
.Lload_nslot:
    li      t0, NSLOT
    j       .Lnslot_loaded
