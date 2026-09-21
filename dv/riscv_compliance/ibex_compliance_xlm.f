// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Xcelium file list for ibex RISC-V compliance testbench.
// Written for the dv_hmp branch of SamuelRiedel/ibex-private, which carries
// the CHERIoT RTL.  On this branch prim_generic files use the plain prim_*
// module names (no prim_generic_ prefix) and there are no common/prim wrappers.
//
// Required env vars (set by build_xlm.sh):
//   PRJ_DIR        - root of the ibex-private repo
//   LOWRISC_IP_DIR - ${PRJ_DIR}/vendor/lowrisc_ip

+incdir+${LOWRISC_IP_DIR}/ip/prim/rtl

// Packages (must precede any module that imports them)
${LOWRISC_IP_DIR}/ip/prim_generic/rtl/prim_pkg.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_assert.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_util_pkg.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_count_pkg.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_pkg.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_mubi_pkg.sv
${LOWRISC_IP_DIR}/ip/prim_generic/rtl/prim_ram_1p_pkg.sv

// Prim generic implementations (define module prim_* directly)
${LOWRISC_IP_DIR}/ip/prim_generic/rtl/prim_clock_gating.sv
${LOWRISC_IP_DIR}/ip/prim_generic/rtl/prim_clock_mux2.sv
${LOWRISC_IP_DIR}/ip/prim_generic/rtl/prim_buf.sv
${LOWRISC_IP_DIR}/ip/prim_generic/rtl/prim_flop.sv
${LOWRISC_IP_DIR}/ip/prim_generic/rtl/prim_and2.sv
${LOWRISC_IP_DIR}/ip/prim_generic/rtl/prim_ram_1p.sv

// Prim modules
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_count.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_22_16_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_22_16_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_64_57_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_64_57_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_hamming_22_16_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_hamming_22_16_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_hamming_39_32_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_hamming_39_32_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_hamming_72_64_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_hamming_72_64_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_ram_1p_adv.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_ram_1p_scr.sv

// Shared lowRISC crypto/prim code used by ibex_lockstep / ICacheScramble
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_cipher_pkg.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_lfsr.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_28_22_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_28_22_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_39_32_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_39_32_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_64_57_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_64_57_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_72_64_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_72_64_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_prince.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_subst_perm.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_28_22_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_28_22_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_39_32_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_39_32_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_72_64_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_72_64_dec.sv

// Shared simulation RTL (bus crossbar, SRAM model)
${PRJ_DIR}/shared/rtl/bus.sv
${PRJ_DIR}/shared/rtl/ram_1p.sv

// Ibex core RTL
+incdir+${PRJ_DIR}/rtl
${PRJ_DIR}/rtl/ibex_pkg.sv

// CHERIoT capability RTL (cheri_ex imports ibex_pkg, so must come after it)
${PRJ_DIR}/rtl/ibex_cheriot_pkg.sv
${PRJ_DIR}/rtl/ibex_cheriot_ex.sv
// TRVK dependencies (stream cells + prim FIFO/SECDED). TRVK is new in this
// RTL and did not exist in ibex-private, so none of these were listed.
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_fifo_sync_cnt.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_fifo_sync.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_hamming_76_68_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_hamming_76_68_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_22_16_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_22_16_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_hamming_22_16_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_hamming_22_16_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_hamming_39_32_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_hamming_39_32_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_hamming_72_64_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_hamming_72_64_enc.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_hamming_76_68_dec.sv
${LOWRISC_IP_DIR}/ip/prim/rtl/prim_secded_inv_hamming_76_68_enc.sv
${PRJ_DIR}/vendor/pulp_common_cells/rtl/stream_fork.sv
${PRJ_DIR}/vendor/pulp_common_cells/rtl/stream_join_dynamic.sv
${PRJ_DIR}/rtl/ibex_trvk.sv
${PRJ_DIR}/rtl/ibex_tracer_pkg.sv
${PRJ_DIR}/rtl/ibex_tracer.sv
${PRJ_DIR}/rtl/ibex_alu.sv
${PRJ_DIR}/rtl/ibex_branch_predict.sv
${PRJ_DIR}/rtl/ibex_compressed_decoder.sv
${PRJ_DIR}/rtl/ibex_controller.sv
${PRJ_DIR}/rtl/ibex_csr.sv
${PRJ_DIR}/rtl/ibex_cs_registers.sv
${PRJ_DIR}/rtl/ibex_counter.sv
${PRJ_DIR}/rtl/ibex_decoder.sv
${PRJ_DIR}/rtl/ibex_dummy_instr.sv
${PRJ_DIR}/rtl/ibex_ex_block.sv
${PRJ_DIR}/rtl/ibex_wb_stage.sv
${PRJ_DIR}/rtl/ibex_id_stage.sv
${PRJ_DIR}/rtl/ibex_icache.sv
${PRJ_DIR}/rtl/ibex_if_stage.sv
${PRJ_DIR}/rtl/ibex_load_store_unit.sv
${PRJ_DIR}/rtl/ibex_lockstep.sv
${PRJ_DIR}/rtl/ibex_multdiv_slow.sv
${PRJ_DIR}/rtl/ibex_multdiv_fast.sv
${PRJ_DIR}/rtl/ibex_prefetch_buffer.sv
${PRJ_DIR}/rtl/ibex_fetch_fifo.sv
${PRJ_DIR}/rtl/ibex_register_file_ff.sv
${PRJ_DIR}/rtl/ibex_register_file_fpga.sv
${PRJ_DIR}/rtl/ibex_register_file_latch.sv
${PRJ_DIR}/rtl/ibex_pmp.sv
${PRJ_DIR}/rtl/ibex_core.sv
${PRJ_DIR}/rtl/ibex_top.sv
${PRJ_DIR}/rtl/ibex_top_tracing.sv

// Compliance testbench RTL
+incdir+${PRJ_DIR}/dv/riscv_compliance/rtl
${PRJ_DIR}/dv/riscv_compliance/rtl/riscv_testutil.sv
${PRJ_DIR}/dv/riscv_compliance/rtl/ibex_riscv_compliance.sv

// Testbench top
${PRJ_DIR}/dv/riscv_compliance/tb/tb_riscv_compliance.sv
