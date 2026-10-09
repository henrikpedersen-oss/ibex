// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// DPI bridge between the RISC-V (non-CHERI) Sail model, generated in RVFI-DII mode, and its two
// users: the ibex_dii_agent (TestRIG) scoreboard and the UVM cosim scoreboard's RISC-V Sail
// checker. Same shape as cheriot_sail/cheriot_sail_cosim_dpi.cc without the capability state.
// Built with hidden visibility so its Sail symbols cannot clash with the CHERIoT model's when
// both libraries are linked into one simulation.
//
// The model is configured to Ibex's architectural choices (the ones the ISA leaves to the
// implementation), never from DUT state: see riscv_sail_cosim_init().

#include "riscv_sail_cosim_dpi.h"

#include <csetjmp>
#include <cstdio>
#include <string>
#include <vector>

#include <gmp.h>

extern "C" {
#include "sail.h"
#include "sail_failure.h"
#include "riscv_rvfi_model_RV32.h"

void model_init(void);
void model_fini(void);

// Referenced by riscv_platform*.c but defined in riscv_sim.c, which is not linked.
bool config_print_instr       = false;
bool config_print_reg         = false;
bool config_print_mem_access  = false;
bool config_print_platform    = false;
bool config_print_exception   = false;
FILE *trace_log               = nullptr;

extern uint64_t rv_ram_base;
extern uint64_t rv_ram_size;
extern uint64_t rv_rom_base;
extern uint64_t rv_rom_size;
extern uint64_t rv_clint_base;
extern uint64_t rv_clint_size;
extern uint64_t rv_htif_tohost;
extern uint64_t rv_pmp_count;
extern uint64_t rv_pmp_grain;
extern bool     rv_enable_fdext;
extern bool     rv_enable_zfinx;
extern bool     rv_enable_vext;
extern bool     rv_enable_misaligned;
extern bool     rv_enable_writable_misa;
extern bool     rv_mtval_has_illegal_inst_bits;

// Sail runtime (rts.c): store one byte into the model's sparse memory.
void write_mem(uint64_t addr, uint64_t byte_val);
}  // extern "C"

static bool s_initialized = false;
static int64_t s_step_no  = 0;
static std::vector<std::string> s_errors;

// Applied by the next init. The defaults are the TestRIG bench's (core_ibex_testrig_tb_top.sv):
// 8 MiB RAM at 0x80000000 and no PMP. The UVM cosim calls riscv_sail_cosim_configure() first.
static uint64_t s_ram_base  = UINT64_C(0x80000000);
static uint64_t s_ram_size  = UINT64_C(0x800000);
static uint64_t s_pmp_count = 0;
static uint64_t s_pmp_grain = 0;

void riscv_sail_cosim_configure(const svBitVecVal *ram_base_p, const svBitVecVal *ram_size_p,
                                int pmp_count, int pmp_grain) {
  s_ram_base  = (uint64_t)ram_base_p[0];
  s_ram_size  = (uint64_t)ram_size_p[0];
  s_pmp_count = (uint64_t)pmp_count;
  s_pmp_grain = (uint64_t)pmp_grain;
}

static uint64_t lbits_low64(lbits *v) {
  return (uint64_t)mpz_get_ui(*v->bits);
}

void riscv_sail_cosim_init(const svBitVecVal *boot_addr_p) {
  uint32_t boot_addr = boot_addr_p[0];
  if (s_initialized) {
    model_fini();
  }
  // The core has no F/D and FS is read-only zero; legalize_mstatus() only clears FS when Zfinx
  // is on, so both are needed. Must precede zinit_model(), which builds misa/mstatus from them.
  rv_enable_fdext = false;
  rv_enable_zfinx = true;
  // ibex performs misaligned loads/stores in hardware (split into two bus accesses); the
  // model must not trap on them. The sail-riscv platform default is false.
  rv_enable_misaligned = true;
  // Further implementation choices, all Ibex's (the sail-riscv platform defaults differ):
  // - no V extension;
  // - misa is read-only (WARL, ibex_cs_registers.sv CSR_MISA write is ignored);
  // - on an illegal instruction mtval holds the instruction word (ibex_controller.sv);
  // - PMP regions and granularity are configuration parameters (PMPNumRegions, PMPGranularity).
  rv_enable_vext                 = false;
  rv_enable_writable_misa        = false;
  rv_mtval_has_illegal_inst_bits = true;
  rv_pmp_count                   = s_pmp_count;
  rv_pmp_grain                   = s_pmp_grain;
  model_init();
  zinit_model(UNIT);
  // Match ibex_cs_registers.sv MSTATUS_RST_VAL (mpie=1, mpp=U): MPIE=bit 7, MPP=[12:11]. mpp=U is
  // legal here: standard RISC-V mode has U-mode (misa.U=1), unlike CHERIoT mode.
  zmstatus.zbits = (zmstatus.zbits & ~UINT64_C(0x1800)) | UINT64_C(0x80);
  zext_rvfi_init(UNIT);

  // RAM as configured (TestRIG default: 8 MiB at 0x80000000, as the CHERIoT model and
  // core_ibex_testrig_tb_top.sv). No ROM, no HTIF, and no CLINT: ibex has no core-local timer
  // (its timer interrupt is a pin), so the CLINT range must be plain memory, as on the DUT's bus.
  rv_ram_base    = s_ram_base;
  rv_ram_size    = s_ram_size;
  rv_rom_base    = UINT64_C(0);
  rv_rom_size    = UINT64_C(0);
  rv_clint_base  = UINT64_C(0);
  rv_clint_size  = UINT64_C(0);
  rv_htif_tohost = UINT64_C(0);

  // Ibex's reset PC is {boot_addr[31:8], 8'h80} (ibex_if_stage.sv PC_BOOT).
  zPC          = (uint64_t)((boot_addr & ~0xffu) | 0x80u);
  // Ibex's reset mtvec is {boot_addr[31:8], 6'b0, 2'b01}: vectored mode, the only mode it
  // implements (ibex_cs_registers.sv). Exceptions go to the base in either mode, which is why
  // TestRIG (no interrupts) never saw the old direct-mode value; interrupts do not.
  zmtvec.zbits = (uint64_t)((boot_addr & ~0xffu) | 0x1u);

  s_step_no = 0;
  s_errors.clear();
  have_exception = false;
  s_initialized = true;
}

int riscv_sail_cosim_step(const svBitVecVal *insn_p, const svBitVecVal *pc_p) {
  uint32_t insn = insn_p[0];
  uint32_t pc   = pc_p[0];

  if (!s_initialized) {
    s_errors.emplace_back("riscv-sail step before init");
    return -1;
  }

  // RVFI-DII instruction packet: insn[31:0], time[47:32], cmd[55:48] (1 = execute).
  uint64_t pkt = (uint64_t)insn | ((uint64_t)(s_step_no & 0xffff) << 32) | ((uint64_t)0x01 << 48);
  zrvfi_set_instr_packet(pkt);
  zrvfi_zzero_exec_packet(UNIT);

  // The model runs on its own PC and is not resynced to the RTL: divergence is the
  // scoreboard's to report (next-pc / trap-target checks), not the bridge's to hide.
  (void)pc;

  sail_int sail_step;
  CREATE(sail_int)(&sail_step);
  CONVERT_OF(sail_int, mach_int)(&sail_step, s_step_no);

  // sail_match_failure()/sail_assert() longjmp back here instead of exiting the simulator.
  sail_recovery_buf_active = 1;
  if (setjmp(sail_recovery_buf) != 0) {
    sail_recovery_buf_active = 0;
    KILL(sail_int)(&sail_step);
    char buf[128];
    snprintf(buf, sizeof(buf), "riscv-sail could not step insn=0x%08x pc=0x%08x", insn, pc);
    s_errors.emplace_back(buf);
    s_step_no++;
    return -1;
  }
  // zstep() returns false when a trap was taken before any instruction ran (a
  // fetch fault or an interrupt); riscv_sim.c's RVFI-DII loop still sends that
  // trace, so it is compared like any other step, not treated as a failure.
  (void)zstep(sail_step);
  sail_recovery_buf_active = 0;
  KILL(sail_int)(&sail_step);
  s_step_no++;

  // A Sail `throw` leaves have_exception set, and every later zstep() would
  // return at once; riscv_sim.c stops here. Report it and clear it.
  if (have_exception) {
    have_exception = false;
    s_errors.emplace_back("riscv-sail model raised a Sail exception at step " +
                          std::to_string(s_step_no - 1));
    return -1;
  }
  return 0;
}

void riscv_sail_cosim_set_mcycle(uint64_t mcycle) {
  zmcycle = mcycle;
}

void riscv_sail_cosim_write_mem_byte(const svBitVecVal *addr_p, const svBitVecVal *data_p) {
  if (!s_initialized) {
    s_errors.emplace_back("riscv-sail write_mem_byte before init");
    return;
  }
  write_mem((uint64_t)addr_p[0], (uint64_t)(data_p[0] & 0xffu));
}

// The DUT entered an interrupt handler. The model cannot see the IRQ pins, so it is given the
// pending bits (mip) and nothing else: whether the interrupt is enabled, which one wins, and
// where it goes come from the model's own privilege level, mstatus, mie and mtvec.
int riscv_sail_cosim_take_interrupt(const svBitVecVal *mip_p) {
  if (!s_initialized) {
    s_errors.emplace_back("riscv-sail take_interrupt before init");
    return -1;
  }
  const uint64_t saved_mip = zmip.zbits;
  zmip.zbits = (uint64_t)mip_p[0];

  zrvfi_zzero_exec_packet(UNIT);
  sail_int sail_step;
  CREATE(sail_int)(&sail_step);
  CONVERT_OF(sail_int, mach_int)(&sail_step, s_step_no);
  sail_recovery_buf_active = 1;
  if (setjmp(sail_recovery_buf) != 0) {
    sail_recovery_buf_active = 0;
    KILL(sail_int)(&sail_step);
    zmip.zbits = saved_mip;
    s_errors.emplace_back("riscv-sail could not take the interrupt (Sail failure)");
    return -1;
  }
  const bool stepped = zstep(sail_step);
  sail_recovery_buf_active = 0;
  KILL(sail_int)(&sail_step);
  // mip is an input: restore it so the pending bits are not left latched in the model.
  zmip.zbits = saved_mip;

  if (have_exception) {
    have_exception = false;
    s_errors.emplace_back("riscv-sail model raised a Sail exception taking an interrupt");
    return -1;
  }
  if (stepped) {
    char buf[200];
    snprintf(buf, sizeof(buf),
             "DUT took an interrupt the model did not: model executed an instruction instead "
             "(mip=0x%08x mie=0x%08llx mstatus=0x%08llx)",
             mip_p[0], (unsigned long long)zmie.zbits, (unsigned long long)zmstatus.zbits);
    s_errors.emplace_back(buf);
    return -1;
  }
  return 0;
}

// Mirrors the model's own decision (dispatchInterrupt; ibex has no S-mode, so no delegation): an
// interrupt is taken when one of the pending bits is enabled in mie, and the hart runs below M-mode
// or has mstatus.MIE set. Reads the model's state only.
int riscv_sail_cosim_irq_would_take(const svBitVecVal *mip_p) {
  if (!s_initialized) {
    return 0;
  }
  const uint64_t enabled = (uint64_t)mip_p[0] & zmie.zbits;
  const bool mie_set = (zmstatus.zbits >> 3) & 1;
  return enabled != 0 && (zcur_privilege != zMachine || mie_set);
}

uint32_t riscv_sail_cosim_get_mcause(void) {
  return (uint32_t)(zmcause.zbits & 0xffffffffULL);
}

uint32_t riscv_sail_cosim_get_mtval(void) {
  return (uint32_t)(zmtval & 0xffffffffULL);
}

void riscv_sail_cosim_cleanup(void) {
  if (s_initialized) {
    model_fini();
    s_initialized = false;
  }
  s_step_no = 0;
  s_errors.clear();
}

uint32_t riscv_sail_cosim_get_pc_wdata(void) {
  return (uint32_t)z_get_RVFI_DII_Execution_Packet_PC_rvfi_pc_wdata(zrvfi_pc_data);
}

svBit riscv_sail_cosim_get_trap(void) {
  return z_get_RVFI_DII_Execution_Packet_InstMetaData_rvfi_trap(zrvfi_inst_data) != 0;
}

uint32_t riscv_sail_cosim_get_rd_addr(void) {
  if (!zrvfi_int_data_present) return 0;
  return (uint32_t)z_get_RVFI_DII_Execution_Packet_Ext_Integer_rvfi_rd_addr(zrvfi_int_data);
}

uint32_t riscv_sail_cosim_get_rd_wdata(void) {
  if (!zrvfi_int_data_present) return 0;
  return (uint32_t)z_get_RVFI_DII_Execution_Packet_Ext_Integer_rvfi_rd_wdata(zrvfi_int_data);
}

uint32_t riscv_sail_cosim_get_mem_addr(void) {
  if (!zrvfi_mem_data_present) return 0;
  return (uint32_t)z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_addr(zrvfi_mem_data);
}

uint32_t riscv_sail_cosim_get_mem_rmask(void) {
  if (!zrvfi_mem_data_present) return 0;
  return (uint32_t)z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_rmask(zrvfi_mem_data);
}

uint32_t riscv_sail_cosim_get_mem_wmask(void) {
  if (!zrvfi_mem_data_present) return 0;
  return (uint32_t)z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_wmask(zrvfi_mem_data);
}

uint64_t riscv_sail_cosim_get_mem_rdata(void) {
  if (!zrvfi_mem_data_present) return 0;
  lbits v;
  CREATE(lbits)(&v);
  z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_rdata(&v, zrvfi_mem_data);
  uint64_t r = lbits_low64(&v);
  KILL(lbits)(&v);
  return r;
}

uint64_t riscv_sail_cosim_get_mem_wdata(void) {
  if (!zrvfi_mem_data_present) return 0;
  lbits v;
  CREATE(lbits)(&v);
  z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_wdata(&v, zrvfi_mem_data);
  uint64_t r = lbits_low64(&v);
  KILL(lbits)(&v);
  return r;
}

int riscv_sail_cosim_get_num_errors(void) {
  return (int)s_errors.size();
}

const char *riscv_sail_cosim_get_error(int index) {
  if (index < 0 || (size_t)index >= s_errors.size()) return "";
  return s_errors[(size_t)index].c_str();
}

void riscv_sail_cosim_clear_errors(void) {
  s_errors.clear();
}
