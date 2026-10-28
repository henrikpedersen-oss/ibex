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
// CHERIoT-Ibex's implementation-defined CSRs in the model's platform (GAP-CS-3): the bench
// inputs (counter values, scrambling-key valid, mcounteren_writable_i) are pushed through it.
#include "ibex_platform_csrs.h"

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
extern uint64_t rv_clint_base;
extern uint64_t rv_clint_size;
extern bool     rv_enable_fdext;
extern bool     rv_enable_zfinx;
extern bool     rv_enable_misaligned;
extern bool     rv_enable_vext;
extern bool     rv_enable_writable_misa;
extern uint64_t zmarchid;
extern uint64_t zMSHWM;
extern uint64_t zMSHWMB;
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

// Second memory region mapped by the next init, in the platform's ROM segment (writable like
// RAM: within_phys_mem() accepts either segment for loads, stores and fetches). Default none.
// The UVM bench uses it for a window at address 0 (+far_code_windows, ibex_cosim_scoreboard.sv).
static uint64_t s_rom_base = 0;
static uint64_t s_rom_size = 0;

void cheriot_sail_cosim_set_rom(const svBitVecVal *base_p, const svBitVecVal *size_p) {
  s_rom_base = (uint64_t)base_p[0];
  s_rom_size = (uint64_t)size_p[0];
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
  // ibex has no vector unit. The platform default (true) set misa.V, so a misa read differed in
  // bit 21 (TestRIG cheriot_unstructured 2026-10-11, csrrw misa: rtl 0x40801016, model 0x40a01016)
  // and vector encodings would execute in the model. The RISC-V bridge already clears it.
  rv_enable_vext = false;
  // ibex performs misaligned loads/stores in hardware (split into two bus accesses); the
  // model must not trap on them. The sail-riscv platform default is false.
  rv_enable_misaligned = true;
  // "On Ibex, misa is hard-wired, i.e. it will remain unchanged after any write" (cs_registers.rst).
  // The platform default (true) let a csrw clear misa.C (TestRIG csr generator 2026-10-18: rtl
  // 0x40801016, model 0x40801012). The RISC-V bridge already sets it.
  rv_enable_writable_misa = false;
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
  // marchid "reads as 0xCE1 to indicate the CHERIoT architecture" in CHERIoT mode (cs_registers.rst,
  // Machine Architecture ID). The model's init leaves it 0 (TestRIG csr generator 2026-10-18).
  zmarchid = UINT64_C(0xCE1);
  // mshwm and mshwmb: "Reset Value: 0x0000_0000" (cs_registers.rst, Machine Stack High Watermark
  // and its Base). CHERIoT-Sail's init never writes them, so a re-initialisation would keep the
  // previous test's watermark. (The TestRIG mshwm mismatches of 2026-10-19 were a different cause:
  // the model lowered MSHWM only on stores to RAM; see VENDORED_FROM.)
  zMSHWM  = UINT64_C(0);
  zMSHWMB = UINT64_C(0);
  // mepc: "Reset Value: 0x0000_0000" (cs_registers.rst, Machine Exception PC), so MEPCC, whose
  // address is mepc, resets with address 0 (its metadata, the executable root, is init's). The
  // model's init leaves the address at the boot PC: a CSpecialR of MEPCC before the first trap read
  // 0x80000000 in the model and 0 on the RTL (UVM cheriot_rand_* seeds 6447-6458, 2026-10-25, once
  // the scoreboard compared full capability results).
  zMEPCC.zaddress = UINT64_C(0);
  zmepc           = UINT64_C(0);
  // MTCC: the RTL resets mtvec to {boot_addr[31:8], 8'h00} and MTCC reads it with bits [1:0] = 0
  // (ibex_cs_registers.sv). The model traps through MTCC's address, which init leaves at
  // root_cap_exe's 0x80000000, and its set_mtvec is a no-op, so the zmtvec line below has no
  // effect. The UVM bench boots at 0x80000000 and agreed by coincidence; the RTOS SoC boots at
  // 0x00100000 and did not (found by review 2026-10-25).
  zMTCC.zaddress  = (uint64_t)(boot_addr & ~0xffu);

  // CHERIoT-Ibex RVFI-DII mode: RAM starts at 0x80000000, no ROM unless set_rom() asked for one.
  // These globals are in riscv_platform_impl.c, linked into our .so.
  rv_ram_base    = UINT64_C(0x80000000);
  rv_ram_size    = s_ram_size;
  rv_rom_base    = s_rom_base;
  rv_rom_size    = s_rom_size;
  rv_htif_tohost = UINT64_C(0);
  // No CLINT, as in the RISC-V bridge: ibex has no core-local timer (its interrupts are pins), so
  // 0x02000000-0x020bffff is not a device on the DUT's bus. Sail's default CLINT made a store
  // there succeed in the model and fault on the TestRIG bench (QuickCheckVEngine's interrupt
  // template clears MSIP with `sw x0, 0(CLINT)`; testrig_cheriot_interrupt, 2026-10-09), and its
  // mtime/mtimecmp could raise a timer interrupt the stimulus never raised.
  rv_clint_base  = UINT64_C(0);
  rv_clint_size  = UINT64_C(0);

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

// Handover from RISC-V (ePMP) mode at the CHERIoT lock, for a bench that switches modes inside one
// run (eg2_top_verification's EG2 chip scoreboard; REQ_SOC_07 there, RFC CHERIoT Ibex "Handover to
// CHERIoT Mode Software"). Call after init(); the state comes from the RISC-V-mode model.
//
// set_gpr_int: x<idx> (1..15) holds an integer: an untagged capability whose address is the value.
void cheriot_sail_cosim_set_gpr_int(const svBitVecVal *idx_p, const svBitVecVal *val_p) {
  assert(s_initialized && "cheriot_sail_cosim_init() must be called first");
  struct zCapability *const gprs[] = {&zx1, &zx2,  &zx3,  &zx4,  &zx5,  &zx6,  &zx7, &zx8,
                                      &zx9, &zx10, &zx11, &zx12, &zx13, &zx14, &zx15};
  const uint32_t idx = idx_p[0];
  assert(idx >= 1 && idx <= 15);
  struct zCapability c = znull_cap;
  c.zaddress = val_p[0];
  *gprs[idx - 1] = c;
}

// handover: execution continues at next_pc with PCC the executable root; MTCC and MEPCC are the
// executable root with the addresses of mtvec (mode bits cleared) and mepc; MTDC and MScratchC
// stay the memory and sealing roots init() made. mstatus.MIE/MPIE, mie, mcause and mtval carry
// over from the RISC-V-mode model.
void cheriot_sail_cosim_handover(const svBitVecVal *next_pc_p, const svBitVecVal *mtvec_p,
                                 const svBitVecVal *mepc_p, const svBitVecVal *mstatus_p,
                                 const svBitVecVal *mie_p, const svBitVecVal *mcause_p,
                                 const svBitVecVal *mtval_p) {
  assert(s_initialized && "cheriot_sail_cosim_init() must be called first");
  const uint64_t kMie = UINT64_C(1) << 3, kMpie = UINT64_C(1) << 7;
  zPC            = next_pc_p[0];
  zPCC.zaddress  = next_pc_p[0];
  zMTCC.zaddress = mtvec_p[0] & ~UINT64_C(3);
  zmtvec.zbits   = mtvec_p[0];
  zMEPCC.zaddress = mepc_p[0];
  zmepc          = mepc_p[0];
  zmstatus.zbits = (zmstatus.zbits & ~(kMie | kMpie)) | (mstatus_p[0] & (kMie | kMpie));
  zmie.zbits     = mie_p[0];
  zmcause.zbits  = mcause_p[0];
  zmtval         = mtval_p[0];
}

// The DUT's pending interrupts (its mip) for the next step, from set_mip(); s_mip_set is false
// until a bench calls it, and then mip stays what the model's own state makes it (as before
// 2026-10-27).
static bool s_mip_set = false;
static uint64_t s_mip = 0;

// The interrupt lines are the bench's, not the model's: before a step the model's mip is the
// DUT's, so a csrr mip reads what the DUT read (2026-10-27: chip_sw_eg2_connectivity_cheriot read
// mip 0x880 on the chip, 0 in the model, which saw pending bits only in take_interrupt()). Bits
// the model would take as an interrupt at the start of this step (mstatus.MIE and the bit in mie)
// are left out: the DUT retired an instruction, so it did not take one here; take_interrupt() is
// the only way in. That leaves one difference: a csrr mip in the cycles between such an
// interrupt arriving and the DUT taking it reads the bit on the DUT and not in the model, a
// mismatch the bench reports rather than hides.
static void apply_pending_mip(void) {
  if (!s_mip_set) return;
  const bool mie_set = (zmstatus.zbits >> 3) & 1;
  zmip.zbits = s_mip & ~(mie_set ? zmie.zbits : UINT64_C(0));
}

void cheriot_sail_cosim_set_mip(const svBitVecVal *mip_p) {
  s_mip_set = true;
  s_mip = (uint64_t)mip_p[0];
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
    // Each of these steps is a synchronous exception (a fetch fault to MTCC) the model does not
    // execute; Ibex records it in cpuctrlsts as any other (ibex_cs_registers.sv:936-946).
    ibex_csr_sync_exception(UNIT);
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

  apply_pending_mip();

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
    char buf[480];
    snprintf(buf, sizeof(buf),
             "cheriot-sail model cannot execute insn=0x%08x at pc=0x%08x (step %lld, "
             "Sail %s): not compared",
             insn, pc, (long long)s_step_no, sail_recovery_msg);
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
  // Also skip mcycle (0xB00, 0xB80 and the cycle aliases 0xC00, 0xC80; time 0xC01/0xC81 is illegal
  // on both sides): it is pushed but sampled at retirement, not when the CSR was read.
  // minstret(h) and instret(h) are compared: retired instructions are architectural and the model
  // counts them itself, as ibex_sail_rvfi_cmp does for RISC-V Sail and TestRIG (until 2026-10-21
  // they were skipped here, so cheriot_minstret_exact's cosim never compared them).
  //   opcode SYSTEM = 0x73; funct3 != 0 distinguishes CSR from ECALL/EBREAK.
  // The HPM counters (mhpmcounter3-31(h), hpmcounter3-31(h)) are compared: their values are
  // pushed before every step from the RVFI record (cheriot_sail_cosim_set_mhpmcounter), which
  // holds the value the instruction read, as the Spike cosim relies on (spike_cosim.cc).
  uint32_t csr_addr      = (insn >> 20) & 0xfff;
  bool is_csr_insn       = ((insn & 0x7f) == 0x73) && (((insn >> 12) & 0x7) != 0);
  bool is_counter_csr    = false;
  if (is_csr_insn) {
    switch (csr_addr) {
      case 0xB00: case 0xB80:                                      // mcycle(h)
      case 0xC00: case 0xC01: case 0xC80: case 0xC81:              // cycle(h), time(h)
        is_counter_csr = true;
        break;
      default:
        break;
    }
  }
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

// The DUT's instruction at `pc` took a bus error (an error response to its fetch, load or store)
// that the model cannot produce: in RVFI-DII it executes the instruction word it is given, and
// its memory never errors. Like Spike's set_iside_error() and notify_dside_access(.., error), the
// error is an event the bench gives the model; the model takes the access fault itself (its own
// mtvec/MTCC, mepc/MEPCC, mcause, mtval and cpuctrlsts) instead of executing the instruction, as
// its step() does for a fetch that fails (riscv_step.sail: handle_mem_exception, tick_pc).
// kind 0: instruction access fault, 1: load access fault, 2: store/AMO access fault; tval the
// address that faulted. 2026-10-25, EG2 chip bench review R12 (chip_sw_rram_uncorr_fetch_cheriot:
// the model ran on past a fetch the chip faulted on, and diverged).
int cheriot_sail_cosim_step_bus_error(const svBitVecVal *pc_p, int kind,
                                      const svBitVecVal *tval_p) {
  const uint32_t pc   = pc_p[0];
  const uint32_t tval = tval_p[0];
  assert(s_initialized && "cheriot_sail_cosim_init() must be called first");

  zrvfi_zzero_exec_packet(UNIT);
  bool pc_diverged = false;
  if (zPC != (uint64_t)pc) {
    char buf[160];
    snprintf(buf, sizeof(buf),
             "cheriot-sail model PC 0x%08llx differs from DUT PC 0x%08x at step %lld (bus error): "
             "the two diverged on an earlier step",
             (unsigned long long)zPC, pc, (long long)s_step_no);
    s_errors.emplace_back(buf);
    pc_diverged = true;
  }
  if (s_pcc_mtcc_loop) {
    ibex_csr_sync_exception(UNIT);
    s_step_no++;
    return pc_diverged ? -1 : 0;
  }

  struct zExceptionType e;
  switch (kind) {
    case 0:
      e.kind = Kind_zE_Fetch_Access_Fault;
      e.variants.zE_Fetch_Access_Fault = UNIT;
      break;
    case 1:
      e.kind = Kind_zE_Load_Access_Fault;
      e.variants.zE_Load_Access_Fault = UNIT;
      break;
    case 2:
      e.kind = Kind_zE_SAMO_Access_Fault;
      e.variants.zE_SAMO_Access_Fault = UNIT;
      break;
    default: {
      char buf[96];
      snprintf(buf, sizeof(buf), "cheriot_sail_cosim_step_bus_error: no access kind %d", kind);
      s_errors.emplace_back(buf);
      return -1;
    }
  }

  sail_recovery_buf_active = 1;
  if (setjmp(sail_recovery_buf) != 0) {
    sail_recovery_buf_active = 0;
    char buf[400];
    snprintf(buf, sizeof(buf),
             "cheriot-sail model cannot take the bus error at pc=0x%08x (step %lld, Sail %s)", pc,
             (long long)s_step_no, sail_recovery_msg);
    s_errors.emplace_back(buf);
    s_step_no++;
    return -1;
  }
  zhandle_mem_exception((uint64_t)tval, e);
  ztick_pc(UNIT);
  zext_post_step_hook(UNIT);
  sail_recovery_buf_active = 0;
  s_step_no++;

  if (have_exception) {
    have_exception = false;
    s_errors.emplace_back("cheriot-sail model raised a Sail exception taking a bus error at step " +
                          std::to_string(s_step_no - 1));
    return -1;
  }
  return pc_diverged ? -1 : 0;
}

// The same condition take_interrupt() checks first; reads the model's state only.
int cheriot_sail_cosim_irq_would_take(const svBitVecVal *mip_p) {
  if (!s_initialized) {
    return 0;
  }
  const bool mie_set = (zmstatus.zbits >> 3) & 1;
  return mie_set && ((uint64_t)mip_p[0] & zmie.zbits) != 0;
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
  s_mip_set = false;
  s_mip = 0;
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

// minstret is the model's own count (architectural, compared), but a model that starts mid-run
// (EG2's handover from Spike) must start from the instructions already retired.
void cheriot_sail_cosim_set_minstret(uint64_t minstret) {
  zminstret = minstret;
}

// Bench inputs of CHERIoT-Ibex's platform CSRs (cheriot-sail-model/sail-riscv/c_emulator/
// ibex_platform_csrs.c, spec GAP-CS-3). Pushed before every step, like mcycle. Only values that
// depend on timing or on the bench are pushed: what the counters counted (the RVFI record's
// mhpmcounters/mhpmcountersh, the value the instruction reads), the scrambling-key handshake and
// the mcounteren_writable_i pin. Reset values, WARL masks and cpuctrlsts' trap/MRET side effects
// are the model's.
void cheriot_sail_cosim_set_mhpmcounter(uint32_t idx, uint64_t value) {
  ibex_platform_set_mhpmcounter(idx, value);
}

void cheriot_sail_cosim_set_cpuctrlsts(unsigned int value) {
  ibex_platform_set_cpuctrlsts(value);
}

void cheriot_sail_cosim_set_ic_scr_key_valid(svBit valid) {
  ibex_platform_set_ic_scr_key_valid(valid != 0);
}

void cheriot_sail_cosim_set_mcounteren_writable(svBit writable) {
  ibex_platform_set_mcounteren_writable(writable != 0);
}

// The build's MHPMCounterNum: which mhpmcounter/mhpmevent CSRs count and the mcounteren /
// mcountinhibit mask. Configuration, so set before init.
void cheriot_sail_cosim_set_mhpm_counter_num(uint32_t num) {
  ibex_platform_set_mhpm_counter_num(num);
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

// The privilege the model is at now, in the RISC-V encoding of rvfi_mode (0 U, 1 S, 3 M). Read
// before a step, it is the privilege the next instruction executes at. CHERIoT is M-mode only.
uint32_t cheriot_sail_cosim_get_priv(void) {
  switch (zcur_privilege) {
    case zUser:       return 0;
    case zSupervisor: return 1;
    default:          return 3;
  }
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
