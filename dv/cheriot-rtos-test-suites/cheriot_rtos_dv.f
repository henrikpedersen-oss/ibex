// CHERIoT RTOS test SoC: file list (Xcelium and Verilator)
//
// Environment variables, exported by cheriot_rtos_xlm_build.sh (both simulators expand them in -f
// files):
//   RTOS_TB_DIR     this directory
//   IBEX_ROOT_DIR   the ibex repository this directory is in: the core, and every prim / prim_generic
//                   / dv_utils file (vendor/lowrisc_ip), the same copies the core builds with in the
//                   UVM testbench
//   OT_CHERIOT_DIR  the superproject's opentitan-cheriot/: the CHERIoT memory subsystem
//
// The Sonata IP around the core (TL-UL, top_pkg, UART, rv_timer, rv_plic, rev_ctl, the SRAM model,
// uartdpi and the address-map packages) is vendored under vendor/sonata-system/ (vendor/fetch.sh,
// pinned commit in vendor/VENDORED_FROM, local patches in vendor/patches/). One tlul_pkg: Sonata's,
// which carries the capability bit in a_user/d_user (see vendor/fetch.sh for why not OpenTitan's);
// opentitan-cheriot is patched to build against it (opentitan-cheriot/patches/0001), so none of its
// own hw/ip/tlul is compiled.
//
// Only what the SoC and testbench elaborate is listed (checked with verilator --json-only: every
// file here defines a module, interface or package in the elaborated design), plus the rest of
// the core's own file set and the few modules named in generate branches this configuration does
// not take (prim_count, prim_arbiter_tree, and the icache scrambling RAM prim_ram_1p_scr with its
// prim_ram_1p_adv / prim_subst_perm / prim_prince), in case the elaborator wants them resolved.
//
// Compile defines (passed on the xrun command line):
//   +define+RVFI                                   ibex_top_tracing needs the RVFI ports
//   +define+PRIM_DEFAULT_IMPL=prim_pkg::ImplGeneric

// ------ Include directories --------------------------------------------------------------------
// prim_assert.sv, prim_util_memload.svh, prim_util_get_scramble_params.svh
+incdir+${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl
// dv_fcov_macros.svh (ibex RTL and fcov/)
+incdir+${IBEX_ROOT_DIR}/vendor/lowrisc_ip/dv/sv/dv_utils
+incdir+${IBEX_ROOT_DIR}/rtl

// ------ prim packages ----------------------------------------------------------------------------
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_pkg.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_util_pkg.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_pkg.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_mubi_pkg.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_subreg_pkg.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_count_pkg.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_ram_1p_pkg.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_ram_2p_pkg.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_pad_wrapper_pkg.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_cipher_pkg.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_esc_pkg.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_alert_pkg.sv
// Sonata's: TL_AUW = 21, the a_user width of its tlul_pkg below (OpenTitan's is 23)
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/top_pkg/rtl/top_pkg.sv

// ------ prim SECDED ------------------------------------------------------------------------------
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_28_22_enc.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_28_22_dec.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_39_32_enc.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_39_32_dec.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_64_57_enc.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_64_57_dec.sv
// Named in generate branches this configuration does not take (prim_ram_1p_adv ECC widths, the
// Hamming variants)
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_22_16_enc.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_22_16_dec.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_hamming_22_16_enc.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_hamming_22_16_dec.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_hamming_39_32_enc.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_hamming_39_32_dec.sv

// ------ prim_generic cells -----------------------------------------------------------------------
// The generic implementations under the plain prim_* names (no FuseSoC primgen wrappers).
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_buf.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_clock_gating.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_clock_mux2.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_flop.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_flop_2sync.sv
// prim_diff_decode's (prim_alert_sender, the subsystem's fatal alert)
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_xnor2.sv
// The Sonata SRAM model's data and tag RAMs (tb/cheriot_rtos_tb.sv loads them through .mem)
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_ram_2p.sv
// The icache RAMs
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_ram_1p.sv

// ------ prim modules -----------------------------------------------------------------------------
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_lfsr.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_fifo_sync.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_fifo_sync_cnt.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_count.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_arbiter_ppc.sv
// prim_arbiter_ppc's priority encoder (this ibex vendor/lowrisc_ip revision)
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_leading_one_ppc.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_arbiter_tree.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_subreg.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_subreg_arb.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_subreg_ext.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_reg_we_check.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_intr_hw.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_max_tree.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_diff_decode.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_alert_sender.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_onehot_check.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_sec_anchor_buf.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_sec_anchor_flop.sv
// Named by ibex_top for ICacheScramble = 1 (off here).
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_ram_1p_adv.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_ram_1p_scr.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_subst_perm.sv
${IBEX_ROOT_DIR}/vendor/lowrisc_ip/ip/prim/rtl/prim_prince.sv

// ------ TL-UL (Sonata's, with the capability bit) ------------------------------------------------
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_pkg.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_data_integ_enc.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_data_integ_dec.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_cmd_intg_gen.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_cmd_intg_chk.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_rsp_intg_gen.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_rsp_intg_chk.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_fifo_sync.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_err.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_err_resp.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_socket_1n.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_socket_m1.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_adapter_reg.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_adapter_host.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_adapter_sram.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_sram_byte.sv

// ------ ibex / CHERIoT core (this repository) ----------------------------------------------------
// pulp_common_cells: ibex_trvk (the load barrier) instantiates stream_fork and stream_join_dynamic.
${IBEX_ROOT_DIR}/vendor/pulp_common_cells/rtl/stream_fork.sv
${IBEX_ROOT_DIR}/vendor/pulp_common_cells/rtl/stream_join_dynamic.sv
${IBEX_ROOT_DIR}/rtl/ibex_pkg.sv
${IBEX_ROOT_DIR}/rtl/ibex_cheriot_pkg.sv
${IBEX_ROOT_DIR}/rtl/ibex_cheriot_ex.sv
${IBEX_ROOT_DIR}/rtl/ibex_tracer_pkg.sv
${IBEX_ROOT_DIR}/rtl/ibex_tracer.sv
${IBEX_ROOT_DIR}/rtl/ibex_alu.sv
${IBEX_ROOT_DIR}/rtl/ibex_branch_predict.sv
${IBEX_ROOT_DIR}/rtl/ibex_compressed_decoder.sv
${IBEX_ROOT_DIR}/rtl/ibex_controller.sv
${IBEX_ROOT_DIR}/rtl/ibex_csr.sv
${IBEX_ROOT_DIR}/rtl/ibex_cs_registers.sv
${IBEX_ROOT_DIR}/rtl/ibex_counter.sv
${IBEX_ROOT_DIR}/rtl/ibex_decoder.sv
${IBEX_ROOT_DIR}/rtl/ibex_dummy_instr.sv
${IBEX_ROOT_DIR}/rtl/ibex_ex_block.sv
${IBEX_ROOT_DIR}/rtl/ibex_wb_stage.sv
${IBEX_ROOT_DIR}/rtl/ibex_id_stage.sv
${IBEX_ROOT_DIR}/rtl/ibex_icache.sv
${IBEX_ROOT_DIR}/rtl/ibex_if_stage.sv
${IBEX_ROOT_DIR}/rtl/ibex_load_store_unit.sv
${IBEX_ROOT_DIR}/rtl/ibex_lockstep.sv
${IBEX_ROOT_DIR}/rtl/ibex_multdiv_slow.sv
${IBEX_ROOT_DIR}/rtl/ibex_multdiv_fast.sv
${IBEX_ROOT_DIR}/rtl/ibex_prefetch_buffer.sv
${IBEX_ROOT_DIR}/rtl/ibex_fetch_fifo.sv
${IBEX_ROOT_DIR}/rtl/ibex_register_file_ff.sv
${IBEX_ROOT_DIR}/rtl/ibex_register_file_fpga.sv
${IBEX_ROOT_DIR}/rtl/ibex_register_file_latch.sv
${IBEX_ROOT_DIR}/rtl/ibex_pmp.sv
${IBEX_ROOT_DIR}/rtl/ibex_core.sv
${IBEX_ROOT_DIR}/rtl/ibex_trvk.sv
${IBEX_ROOT_DIR}/rtl/ibex_top.sv
${IBEX_ROOT_DIR}/rtl/ibex_top_tracing.sv

// ------ Sonata address map and peripherals (vendor/sonata-system) --------------------------------
// ADDR_SPACE_* / ADDR_MASK_* only; the crossbar is cheriot_rtos_xbar.sv.
${RTOS_TB_DIR}/vendor/sonata-system/rtl/bus/tl_main_pkg.sv
${RTOS_TB_DIR}/vendor/sonata-system/rtl/bus/tl_ifetch_pkg.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/uart/rtl/uart_reg_pkg.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/uart/rtl/uart_reg_top.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/uart/rtl/uart_rx.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/uart/rtl/uart_tx.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/uart/rtl/uart_core.sv
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/ip/uart/rtl/uart.sv
${RTOS_TB_DIR}/vendor/sonata-system/rtl/ip/rev_ctl/rtl/rev_ctl_reg_pkg.sv
${RTOS_TB_DIR}/vendor/sonata-system/rtl/ip/rev_ctl/rtl/rev_ctl_reg_top.sv
${RTOS_TB_DIR}/vendor/sonata-system/rtl/ip/rev_ctl/rtl/rev_ctl.sv
${RTOS_TB_DIR}/vendor/sonata-system/rtl/system/autogen/rv_plic/rtl/rv_plic_gateway.sv
${RTOS_TB_DIR}/vendor/sonata-system/rtl/system/autogen/rv_plic/rtl/rv_plic_target.sv
${RTOS_TB_DIR}/vendor/sonata-system/rtl/system/autogen/rv_plic/rtl/rv_plic_reg_pkg.sv
${RTOS_TB_DIR}/vendor/sonata-system/rtl/system/autogen/rv_plic/rtl/rv_plic_reg_top.sv
${RTOS_TB_DIR}/vendor/sonata-system/rtl/system/autogen/rv_plic/rtl/rv_plic.sv
${RTOS_TB_DIR}/vendor/sonata-system/rtl/system/sram.sv
${RTOS_TB_DIR}/vendor/sonata-system/rtl/system/rv_timer.sv

// ------ OpenTitan CHERIoT memory subsystem (lowRISC/opentitan PR #31515) -------------------------
${OT_CHERIOT_DIR}/hw/vendor/pulp_common_cells/rtl/stream_fork_dynamic.sv
${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl/cheriot_reg_pkg.sv
${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl/cheriot_regs_reg_top.sv
${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl/cheriot_rmw_filter.sv
${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl/cheriot_wtrc.sv
${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl/cheriot_tag_filter.sv
${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl/cheriot_access_check.sv
${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl/cheriot_socket_m1.sv
${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl/cheriot_tbre_mover.sv
${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl/cheriot_trvk_core.sv
${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl/cheriot_trvk_tlul.sv
${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl/cheriot_tbre.sv
${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl/cheriot.sv

// ------ The SoC ----------------------------------------------------------------------------------
// The Sonata integration glue for the subsystem (cheriot_rev_ctl_tbre, cheriot_mem_subsys) began
// as an uncommitted addition to a sonata-system checkout; these are this flow's own copies.
${RTOS_TB_DIR}/rtl/cheriot_rev_ctl_tbre.sv
${RTOS_TB_DIR}/rtl/cheriot_mem_subsys.sv
${RTOS_TB_DIR}/rtl/cheriot_rtos_default_rsp.sv
${RTOS_TB_DIR}/rtl/cheriot_rtos_xbar.sv
${RTOS_TB_DIR}/rtl/cheriot_rtos_soc.sv

// ------ Functional coverage (sampled with +enable_ibex_fcov=1) -----------------------------------
${IBEX_ROOT_DIR}/dv/uvm/core_ibex/fcov/core_ibex_trvk_fcov_if.sv
${RTOS_TB_DIR}/fcov/cheriot_mem_subsys_fcov.sv
${RTOS_TB_DIR}/fcov/cheriot_mem_subsys_fcov_bind.sv

// ------ Testbench --------------------------------------------------------------------------------
${RTOS_TB_DIR}/vendor/sonata-system/vendor/lowrisc_ip/dv/dpi/uartdpi/uartdpi.sv
${RTOS_TB_DIR}/tb/cheriot_rtos_tb.sv
