// CHERIoT instruction definitions, added for the lowRISC CHERIoT-Ibex
// verification effort. Encodings are taken from ibex/rtl/ibex_decoder.sv
// (OPCODE_CHERI, lines 804-892) and cross-checked against the hand-written
// .word encodings in dv/uvm/core_ibex/directed_tests/cheriot_*/.
//
// All of these use major opcode 0x5b and are decoded only when
// cheriot_enable_i == IbexMuBiOn, so a test using them must also pass
// +enable_cheriot_seq=1 on the RTL side or every one is an illegal instruction.
//
// FORMAT CHOICE: the format only decides which fields riscv-dv randomises,
// because riscv_custom_instr::convert2asm() emits a raw `.word` rather than a
// mnemonic (the toolchain is stock -march=rv32imc and cannot assemble CHERIoT
// mnemonics -- see directed_testlist.yaml:101). So:
//   I_FORMAT -> rd + rs1 randomised. Used for the single-source ops, where the
//               rs2 field is a fixed sub-opcode rather than a register, and for
//               the two genuine immediate forms.
//   R_FORMAT -> rd + rs1 + rs2 randomised. Used for the two-source ops.
//
// DELIBERATELY OMITTED -- these trap on essentially every random operand, and
// would turn a random program into a stream of CHERI faults (cause 28) rather
// than useful stimulus. They need a directed stream that first establishes a
// valid, in-bounds, correctly-permissioned capability:
//   clc / csc       tag, sealed, LD/SD/MC permission, bounds, 8-byte alignment
//   cjalr           tag, seal/sentry, EX permission
//   cspecialrw      ASR permission, and only SCRs 28-31 are legal outside debug
//
// Note that cseal/cunseal/ctestsubset are included: the RTL is explicit that
// they do NOT raise exceptions (ibex_cheriot_ex.sv:813-816) and merely clear the
// result tag when the operands are unsuitable, which is safe to randomise.
// Likewise csetbounds*/csetaddr/cincaddr*/candperm/csethigh clear the tag rather
// than faulting.

// ---- Capability inspection: funct3=000, funct7=0x7f, sub-op in instr[24:20] --
// rd is an INTEGER result, cs1 is a capability register. Cannot trap.
`DEFINE_CUSTOM_INSTR(CGETPERM,        I_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CGETTYPE,        I_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CGETBASE,        I_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CGETLEN,         I_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CGETTAG,         I_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CGETADDR,        I_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CGETHIGH,        I_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CGETTOP,         I_FORMAT, ARITHMETIC, RV32X)

// ---- Single-source, same encoding family -----------------------------------
// crrl/cram are integer-in/integer-out; cmove/ccleartag are capability-to-
// capability. All four cannot trap.
`DEFINE_CUSTOM_INSTR(CRRL,            I_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CRAM,            I_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CMOVE,           I_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CCLEARTAG,       I_FORMAT, ARITHMETIC, RV32X)

// ---- Two-source: funct3=000, funct7 is the sub-opcode ----------------------
`DEFINE_CUSTOM_INSTR(CSETBOUNDS,      R_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CSETBOUNDSEXACT, R_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CSETBOUNDSRNDN,  R_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CSEAL,           R_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CUNSEAL,         R_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CANDPERM,        R_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CSETADDR,        R_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CINCADDR,        R_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CSUB,            R_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CSETHIGH,        R_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CTESTSUBSET,     R_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CISEQUAL,        R_FORMAT, ARITHMETIC, RV32X)

// ---- Immediate forms -------------------------------------------------------
// The whole of instr[31:20] is the immediate and no funct7 is checked, so every
// 12-bit value is legal for both. cincaddrimm treats it as signed, csetboundsimm
// as unsigned -- irrelevant to encoding, both just occupy instr[31:20].
`DEFINE_CUSTOM_INSTR(CINCADDRIMM,     I_FORMAT, ARITHMETIC, RV32X)
`DEFINE_CUSTOM_INSTR(CSETBOUNDSIMM,   I_FORMAT, ARITHMETIC, RV32X)
