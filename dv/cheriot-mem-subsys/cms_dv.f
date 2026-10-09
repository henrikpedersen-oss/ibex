// CHERIoT memory subsystem block-level bench: file list for Verilator (lint). Paths are relative
// to the ibex_cheriot_verification superproject root, which the Makefile runs from.
//
// The RTL comes from opentitan-cheriot/cheriot_rtl.f unchanged (this repository's ibex/vendor prim
// and pulp_common_cells, OpenTitan's TL-UL vendored next to the subsystem): the library set that
// elaborates the subsystem standalone. Library modules are found with -y. Xcelium uses the
// explicit list cms_xlm.f instead, generated from this one (make filelist).
-f opentitan-cheriot/cheriot_rtl.f
+incdir+ibex/vendor/lowrisc_ip/dv/sv/dv_utils
+incdir+ibex/dv/cheriot-mem-subsys/tb

// Testbench
ibex/dv/cheriot-mem-subsys/tb/cms_pkg.sv
ibex/dv/cheriot-mem-subsys/tb/cms_tl_host.sv
ibex/dv/cheriot-mem-subsys/tb/cms_tl_mem.sv
// Functional coverage of the RTL internals: the RTOS SoC's covergroups, bound here as well
ibex/dv/uvm/core_ibex/fcov/core_ibex_trvk_fcov_if.sv
ibex/dv/cheriot-rtos-test-suites/fcov/cheriot_mem_subsys_fcov.sv
ibex/dv/cheriot-mem-subsys/tb/cms_fcov_bind.sv
ibex/dv/cheriot-mem-subsys/tb/cms_tb.sv
