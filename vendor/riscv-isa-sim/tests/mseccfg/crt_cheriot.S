# See LICENSE for license details.
#
# CHERIoT-aware startup: identical to crt.S but initialises the capability
# stack pointer (c2) from MTDC before entering _init.
#
# In CHERIoT mode every load and store is authorised by the capability in its
# base register; there is no DDC. Standard crt.S sets x2 (SP) via integer
# arithmetic, leaving c2 untagged, so the first store in _init (c.swsp /
# c.cscsp) would fault with a tag violation.
#
# Fix: after computing the integer SP, read MTDC (SCR 29, the memory root:
# tag=1, full-memory bounds) into c2, then point c2's cursor at the integer SP
# value (see the sequence and its encodings further down).

#include "encoding.h"

#if __riscv_xlen == 64
# define LREG ld
# define SREG sd
# define REGBYTES 8
#else
# define LREG lw
# define SREG sw
# define REGBYTES 4
#endif

  .section ".text.init"
  .org 0x80
  .globl _start
_start:
  li  x1, 0
  li  x2, 0
  li  x3, 0
  li  x4, 0
  li  x5, 0
  li  x6, 0
  li  x7, 0
  li  x8, 0
  li  x9, 0
  li  x10,0
  li  x11,0
  li  x12,0
  li  x13,0
  li  x14,0
  li  x15,0
  # x16-x31 deliberately not zeroed here: this file is only used with
  # +enable_cheriot_seq=1 (see directed_testlist.yaml's cheriot-c-tests
  # config), and ibex_decoder.sv's illegal_reg_16 check makes ANY access to
  # a register >= x16 an illegal instruction once cheriot_enable_i is
  # asserted (CHERIoT only has 16 architectural registers). The original
  # crt.S x16-x31 zeroing loop, inherited unmodified from the plain RV32I
  # startup, faults immediately here with no trap handler installed yet --
  # the fault has nowhere to go but the boot vector, producing an infinite
  # reset loop.

  # enable FPU and accelerator if present
  li t0, MSTATUS_FS | MSTATUS_XS
  csrs mstatus, t0

  # make sure XLEN agrees with compilation choice
  li t0, 1
  slli t0, t0, 31
#if __riscv_xlen == 64
  bgez t0, 1f
#else
  bltz t0, 1f
#endif
2:
  li a0, 1
  sw a0, tohost, t0
  j 2b
1:

#ifdef __riscv_flen
  # initialize FPU if we have one
  # NOTE: unexercised by the cheriot-c-tests config (-march=rv32imc, no F
  # extension), so left as plain csrw. If this ever gets compiled with F
  # enabled under +enable_cheriot_seq=1, it needs the same fix as the real
  # "initialize trap vector" block below: csrw mtvec is illegal once
  # cheriot_enable_i is asserted (see REQ_SCR_07) -- use the
  # cspecialr/csetaddr/cspecialw MTCC sequence instead.
  la t0, 1f
  csrw mtvec, t0

  fssr    x0
  fmv.s.x f0, x0
  fmv.s.x f1, x0
  fmv.s.x f2, x0
  fmv.s.x f3, x0
  fmv.s.x f4, x0
  fmv.s.x f5, x0
  fmv.s.x f6, x0
  fmv.s.x f7, x0
  fmv.s.x f8, x0
  fmv.s.x f9, x0
  fmv.s.x f10,x0
  fmv.s.x f11,x0
  fmv.s.x f12,x0
  fmv.s.x f13,x0
  fmv.s.x f14,x0
  fmv.s.x f15,x0
  fmv.s.x f16,x0
  fmv.s.x f17,x0
  fmv.s.x f18,x0
  fmv.s.x f19,x0
  fmv.s.x f20,x0
  fmv.s.x f21,x0
  fmv.s.x f22,x0
  fmv.s.x f23,x0
  fmv.s.x f24,x0
  fmv.s.x f25,x0
  fmv.s.x f26,x0
  fmv.s.x f27,x0
  fmv.s.x f28,x0
  fmv.s.x f29,x0
  fmv.s.x f30,x0
  fmv.s.x f31,x0
1:
#endif

  # initialize trap vector
  #
  # ibex_cs_registers.sv (CSR_MTVEC case) makes any access to the plain mtvec
  # CSR illegal once cheriot_enable_i is asserted -- MTCC supersedes it
  # entirely, set only via cspecialrw (see REQ_SCR_07 in the verification
  # spec). csrw mtvec, t0 here would trap with no handler installed yet,
  # looping back to the boot vector forever.
  #
  # `la t0, trap_entry` lowers to AUIPC+ADDI, and AUIPC is architecturally
  # redefined as CAUIPCC under cheriot_enable_i (deriving a tagged capability
  # from PCC), but the following ADDI is a plain integer ALU op and clears
  # the tag again -- t0 ends up an ordinary untagged address, same as under
  # plain RV32I. So MTCC can't be written directly from t0 (that would leave
  # MTCC untagged/invalid); instead read MTCC's own valid reset capability
  # into a scratch capability register, move its cursor to trap_entry with
  # CSetAddr (preserving tag/bounds/EX permission), and write that back --
  # the same read-adjust-write idiom used above for c2's stack capability.
  #
  #   cspecialr c6, mtcc    = 0x03C0035B (funct7=0x01, SCR=28=11100 (MTCC),
  #                                       rs1=x0=00000, rd=c6=x6=00110)
  #   csetaddr  c6, c6, t0  = 0x2053035B (funct7=0x10, rs2=t0=x5=00101,
  #                                       cs1=rd=c6=x6=00110)
  #   cspecialw mtcc, c6    = 0x03C3005B (funct7=0x01, SCR=28=11100 (MTCC),
  #                                       rs1=c6=x6=00110, rd=x0=00000)
  la t0, trap_entry
  .word 0x03C0035B       # cspecialr c6, mtcc   -- c6 <- MTCC (tag=1, EX=1, full bounds)
  .word 0x2053035B       # csetaddr  c6, c6, t0 -- c6.cursor <- trap_entry, tag preserved
  .word 0x03C3005B       # cspecialw mtcc, c6   -- MTCC <- c6 (valid capability, cursor=trap_entry)

  # initialize global pointer
.option push
.option norelax
  la gp, __global_pointer$
.option pop

  # ── CHERIoT capability global-pointer initialisation ────────────────────────
  # Same problem, and same fix, as the stack pointer below: `la` lowers to
  # AUIPC+ADDI and the ADDI is a plain integer op, so c3/gp ends up tag=0. In
  # CHERIoT mode every SW/LW is promoted to CSC/CLC and faults on an untagged
  # base register.
  #
  # gp is not merely a data pointer here -- trap_entry uses it as the base of its
  # register save area (`SREG sp, 31*REGBYTES(gp)` is its first instruction). With
  # gp untagged that store faults, which re-enters trap_entry, which executes the
  # same store: an unbreakable double-fault loop before handle_trap is ever
  # reached. wb_cheri_clc_csc is the first test to take a trap and hit it.
  #
  # Encodings derived from the c2 sequence below by changing rd/cs1 from x2 to x3:
  #   cspecialr c2, mtdc   = 0x03D0015B -> c3 = 0x03D001DB (rd  bits[11:7] 2->3: +0x80)
  #   csetaddr  c2, c2, t0 = 0x2051015B -> c3 = 0x205181DB (rd +0x80, cs1 bits[19:15] +0x8000)
  mv    t0, gp           # t0 (x5) = integer gp value
  .word 0x03D001DB       # cspecialr c3, mtdc -- c3 ← MTDC (tag=1); x3.int ← 0
  .word 0x205181DB       # csetaddr c3, c3, t0 -- c3.cursor ← t0 (original gp)

  la  tp, _end + 63
  and tp, tp, -64

  # get core id
  csrr a0, mhartid
  # for now, assume only 1 core
  li a1, 1
1:bgeu a0, a1, 1b

  # give each core 128KB of stack + TLS
#define STKSHIFT 17
  add sp, a0, 1
  sll sp, sp, STKSHIFT
  add sp, sp, tp
  sll a2, a0, STKSHIFT
  add tp, tp, a2

  # ── CHERIoT capability stack-pointer initialisation ─────────────────────────
  # In CHERIoT mode (cheriot_enable=IbexMuBiOn) every SW/LW is promoted to
  # CSC/CLC and requires the base register to carry a valid capability tag.
  # x2/c2 was set above by integer arithmetic: tag=0.  Derive c2 from MTDC
  # (machine data capability, SCR 29: tag=1, perms=0x07F, full-memory bounds)
  # and move its cursor to the just-computed integer SP address.
  #
  # ibex CHERIoT valid SCR addresses outside debug mode: 28=MTCC, 29=MTDC, 30=MScratchC,
  # 31=MEPCC (27 ZTOPC is illegal). There is no DDC: SCR 1 is an illegal SCR number.
  #
  # CRITICAL: cspecialr writes the SCR's cursor (0 for MTDC at reset) into the
  # destination register's INTEGER part, clobbering x2=SP.  Save SP to t0
  # (x5) first, then use t0 as the address argument in csetaddr.
  #
  # Encoding derivation:
  #   cspecialr ca0, mtcc = 0x03C0055B (funct7=0x01, SCR=28=11100, rd=a0, rs1=0)
  #   cspecialr ca0, mtdc = 0x03D0055B (SCR=29=11101: set bit20 in 0x03C0055B)
  #   cspecialr c2,  mtdc = 0x03D0015B (rd=x2=2: change bits[11:7] to 00010)
  #   csetaddr  a0, a0, a1 = 0x20B5055B (funct7=0x10, rs2=a1, rs1=a0, rd=a0)
  #   csetaddr  c2, c2, t0 = 0x2051015B (rs2=t0=x5=5: bits[24:20]=00101)
  mv    t0, sp           # t0 (x5) = integer SP value (0x80060000)
  .word 0x03D0015B       # cspecialr c2, mtdc -- c2 ← MTDC (tag=1); x2.int ← 0 (MTDC cursor)
  .word 0x2051015B       # csetaddr c2, c2, t0 -- c2.cursor ← t0 (original SP); x2.int ← SP

  # Skip _init: it uses auipc with rd=x16-x31 (e.g. auipc s4,0x10) which ibex CHERIoT
  # decodes as CAUIPCC c20 and flags as illegal (illegal_reg_cheri: rd[4]=1).
  # Call main(0, NULL) directly; ra=x1=c1 has rd[4]=0, so CAUIPCC c1 is legal.
  li    a0, 0             # argc = 0
  li    a1, 0             # argv = NULL
  call  main              # call main; ra/c1 set as return address (c1 valid CHERIoT)

  # CHERIoT-safe exit: tohost_exit() does `lui x15,0x90000; sw ...,0(x15)` which
  # clears c15.tag (lui is an integer op) → CHERI fault on the store.
  # Instead, derive address capability from MTDC (full-memory cap, tag=1, all perms).
  # Replicates tohost_exit(a0): writes (a0<<8)|CORE_STATUS then the TEST_RESULT
  # word to SIGNATURE_ADDR = 0x8FFFFFF8 (= cfg.signature_addr - 4, which is what
  # core_ibex_base_test.sv actually waits on).
  #
  # LOCAL PATCH (not upstream riscv-isa-sim -- reapply after any vendor resync):
  # the TEST_RESULT payload used to be `li t1, 1`, a literal TEST_PASS. main()'s
  # return value was shifted into the CORE_STATUS word and then never consulted,
  # so every CHERIoT directed test reported PASS no matter what it found --
  # cheriot_cap_readback returned exit code 2 from .Lfail1_perm and the
  # regression still scored it 100% PASS. Derive the payload from a0 instead.
  #
  # Signature word format is (payload << 8) | type, per directed_tests/ibex_macros.h:
  #   pass = (TEST_PASS=0 << 8) | TEST_RESULT=1 = 0x00000001
  #   fail = (TEST_FAIL=1 << 8) | TEST_RESULT=1 = 0x00000101
  #
  # Both t0 and t1 must be computed before the cspecialr below, which overwrites
  # a0 (x10 == c10) with the address capability.
  slli  t0, a0, 8         # t0 = (exit_code << 8) | CORE_STATUS(0)
  sltu  t1, x0, a0        # t1 = (a0 != 0) -> TEST_FAIL(1) else TEST_PASS(0)
  slli  t1, t1, 8         # t1 = payload << 8
  ori   t1, t1, 1         # t1 |= TEST_RESULT
  lui   a1, 0x90000       # a1 = 0x90000000 (integer; c11.tag=0, OK — used as addr only)
  addi  a1, a1, -8        # a1 = 0x8FFFFFF8 (SIGNATURE_ADDR)
  .word 0x03D0055B        # cspecialr c10, mtdc  -- c10 ← MTDC (tag=1, full 4GB bounds)
  .word 0x20B5055B        # csetaddr c10, c10, a1 -- c10.cursor ← 0x8FFFFFF8 (tag preserved)
  fence iorw, iorw
  sw    t0, 0(a0)         # CHERIoT store via c10: first sig word (exit_code<<8 | 0)
  sw    t1, 0(a0)         # CHERIoT store via c10: second sig word (TEST_PASS=1)
1:j 1b                    # infinite loop — testbench ends on tohost write above

  # mtvec.base must be 256 byte aligned - Ibex
  .balign 256
trap_entry:
  #addi sp, sp, -272
  # use shadow address
  SREG sp, 31*REGBYTES(gp)
  # Derive the frame pointer from gp's capability, not with integer arithmetic.
  # `addi sp, gp, 512` is a plain integer op: it produces the right address but
  # clears c2's tag, and the very next instruction (SREG x1, ...(sp)) is a CSC
  # through that untagged base -- it faults, re-enters trap_entry, and loops.
  #
  # CIncAddrImm adds the offset to the cursor while preserving tag and bounds, and
  # needs no scratch register -- which matters here, because only sp has been saved
  # at this point and clobbering anything else would corrupt the trapped context.
  #
  # cincaddrimm ca0, ca0, 4 = 0x0045155B (I-type, funct3=001, imm in bits[31:20])
  #   -> c2, c3, 512        = 0x2001915B (imm=0x200, rs1=3, rd=2)
  .word 0x2001915B       # cincaddrimm c2, c3, 512 -- c2 <- gp cap, cursor gp+512

  SREG x1, 1*REGBYTES(sp)
  SREG x2, 2*REGBYTES(sp)
  SREG x3, 3*REGBYTES(sp)
  SREG x4, 4*REGBYTES(sp)
  SREG x5, 5*REGBYTES(sp)
  SREG x6, 6*REGBYTES(sp)
  SREG x7, 7*REGBYTES(sp)
  SREG x8, 8*REGBYTES(sp)
  SREG x9, 9*REGBYTES(sp)
  SREG x10, 10*REGBYTES(sp)
  SREG x11, 11*REGBYTES(sp)
  SREG x12, 12*REGBYTES(sp)
  SREG x13, 13*REGBYTES(sp)
  SREG x14, 14*REGBYTES(sp)
  SREG x15, 15*REGBYTES(sp)
  # x16-x31 deliberately not saved -- same 16-register constraint as the init path
  # above, which is why the crt.S zeroing loop was dropped there.
  #
  # This block was inherited byte-identical from crt.S, which is plain RV32 and saves
  # all 31 registers. Under cheriot_enable_i only x0-x15 exist: ibex_decoder.sv's
  # illegal_reg_16 fires on raddr_b[4] with rf_ren_b_o, and OPCODE_STORE sets
  # rf_ren_b_o, so `SREG x16` is itself an illegal instruction. It would trap back
  # into trap_entry, re-run the stores below, and hit the same instruction forever --
  # never reaching handle_trap. It has never fired only because no CHERIoT directed
  # test currently takes a trap.
  #
  # Truncating the frame to x1-x15 is safe: nothing indexes the high slots. The
  # handle_trap in syscalls.c is a weak stub that ignores regs[], and the mseccfg
  # per-test overrides read mtval via csrr rather than the saved frame.

  csrr a0, mcause
  csrr a1, mepc
  mv a2, sp
  jal handle_trap
  csrw mepc, a0

  # Remain in M-mode after eret
  #li t0, MSTATUS_MPP
  #csrs mstatus, t0

  LREG x1, 1*REGBYTES(sp)
  LREG x2, 2*REGBYTES(sp)
  LREG x3, 3*REGBYTES(sp)
  LREG x4, 4*REGBYTES(sp)
  LREG x5, 5*REGBYTES(sp)
  LREG x6, 6*REGBYTES(sp)
  LREG x7, 7*REGBYTES(sp)
  LREG x8, 8*REGBYTES(sp)
  LREG x9, 9*REGBYTES(sp)
  LREG x10, 10*REGBYTES(sp)
  LREG x11, 11*REGBYTES(sp)
  LREG x12, 12*REGBYTES(sp)
  LREG x13, 13*REGBYTES(sp)
  LREG x14, 14*REGBYTES(sp)
  LREG x15, 15*REGBYTES(sp)
  # x16-x31 not restored: they were never saved (see the note in the save block).
  # LREG is lw, which writes its destination, so instr_rd[4] with rf_we_or_load trips
  # the same illegal_reg_16 check -- the restore path is as illegal as the save path.

  #addi sp, sp, 272
  LREG sp, 31*REGBYTES(gp)
  mret

.section ".tohost","aw",@progbits
.align 6
.globl tohost
tohost: .dword 0
.align 6
.globl fromhost
fromhost: .dword 0
