// CHERIoT memory subsystem built against Sonata's own libraries: sonata-system's TL-UL (with the
// capability bit in a_user/d_user) and top_pkg, the prim of its inner vendor/lowrisc_ibex (as
// ibex/dv/cheriot-rtos-test-suites/cheriot_rtos_dv.f uses it) and that tree's prim_buf/prim_flop wrappers. Needs
// patches/0001 (applied by fetch.sh). Paths are relative to the repository root.
//   verilator --lint-only -Wno-fatal +define+PRIM_DEFAULT_IMPL=prim_pkg::ImplGeneric \
//     --top-module cheriot -f opentitan-cheriot/cheriot_rtl_sonata.f
+incdir+sonata-system/vendor/lowrisc_ibex/vendor/lowrisc_ip/ip/prim/rtl
sonata-system/vendor/lowrisc_ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_util_pkg.sv
sonata-system/vendor/lowrisc_ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_mubi_pkg.sv
sonata-system/vendor/lowrisc_ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_pkg.sv
sonata-system/vendor/lowrisc_ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_alert_pkg.sv
sonata-system/vendor/lowrisc_ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_subreg_pkg.sv
sonata-system/vendor/lowrisc_ibex/dv/uvm/core_ibex/common/prim/prim_pkg.sv
sonata-system/vendor/lowrisc_ip/ip/top_pkg/rtl/top_pkg.sv
sonata-system/vendor/lowrisc_ip/ip/tlul/rtl/tlul_pkg.sv
ibex/rtl/ibex_pkg.sv
ibex/rtl/ibex_cheriot_pkg.sv
opentitan-cheriot/hw/ip/cheriot/rtl/cheriot_reg_pkg.sv
-y sonata-system/vendor/lowrisc_ibex/vendor/lowrisc_ip/ip/prim/rtl
-y sonata-system/vendor/lowrisc_ibex/vendor/lowrisc_ip/ip/prim_generic/rtl
-y ibex/vendor/pulp_common_cells/rtl
-y opentitan-cheriot/hw/vendor/pulp_common_cells/rtl
-y sonata-system/vendor/lowrisc_ip/ip/tlul/rtl
-y opentitan-cheriot/hw/ip/cheriot/rtl
opentitan-cheriot/hw/ip/cheriot/rtl/cheriot.sv
-y sonata-system/vendor/lowrisc_ibex/dv/uvm/core_ibex/common/prim
