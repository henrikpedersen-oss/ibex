# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# IO timing constraints for ibex_top with BaseIsa=BaseIsaRV32IorCHERIoT.
# Used by syn_setup_cheriot.sh; see ibex_top_lr_synth_conf.tcl for the base config.

set lr_synth_outputs [list {instr_req_o        70.0} \
                           {instr_addr_o        70.0} \
                           {data_req_o          70.0} \
                           {data_we_o           70.0} \
                           {data_be_o           70.0} \
                           {data_addr_o         70.0} \
                           {data_wdata_o        70.0} \
                           {data_tag_o          70.0} \
                           {trvk_revbm_req_o    70.0} \
                           {trvk_revbm_addr_o   70.0} \
                           {core_sleep_o        80.0}]

set lr_synth_inputs [list {test_en_i             0.0} \
                          {hart_id_i              0.0} \
                          {boot_addr_i            0.0} \
                          {cheriot_enable_i       0.0} \
                          {trvk_heap_base_addr_i  0.0} \
                          {instr_gnt_i           30.0} \
                          {instr_rvalid_i        30.0} \
                          {instr_rdata_i         30.0} \
                          {instr_err_i           30.0} \
                          {data_gnt_i            30.0} \
                          {data_rvalid_i         30.0} \
                          {data_rdata_i          30.0} \
                          {data_tag_i            30.0} \
                          {data_err_i            30.0} \
                          {trvk_revbm_gnt_i      30.0} \
                          {trvk_revbm_rvalid_i   30.0} \
                          {trvk_revbm_rdata_i    30.0} \
                          {trvk_revbm_err_i      30.0} \
                          {irq_software_i        10.0} \
                          {irq_timer_i           10.0} \
                          {irq_external_i        10.0} \
                          {irq_fast_i            10.0} \
                          {irq_nm_i              10.0} \
                          {debug_req_i           10.0} \
                          {fetch_enable_i         0.0}]

set lr_synth_clk_input  clk_i
set lr_synth_rst_input  rst_ni

set lr_synth_clk_period    4000.0
set lr_synth_abc_clk_uprate 2000.0
