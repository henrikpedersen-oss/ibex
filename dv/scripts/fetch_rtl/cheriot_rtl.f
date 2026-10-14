// CHERIoT memory subsystem (OpenTitan hw/ip/cheriot) built against this repository's own prim,
// pulp_common_cells and ibex_cheriot_pkg. ${OT_CHERIOT_DIR} is the subsystem fetched by
// ibex/dv/scripts/fetch_rtl.sh opentitan-cheriot (a build's own copy); every other path is relative
// to the ibex_cheriot_verification root, where the builds that use this list run.
+incdir+ibex/vendor/lowrisc_ip/ip/prim/rtl
ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_util_pkg.sv
ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_mubi_pkg.sv
ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_pkg.sv
ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_alert_pkg.sv
ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_subreg_pkg.sv
ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_count_pkg.sv
ibex/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_pkg.sv
${OT_CHERIOT_DIR}/hw/top_earlgrey/rtl/top_pkg.sv
${OT_CHERIOT_DIR}/hw/ip/tlul/rtl/tlul_pkg.sv
ibex/rtl/ibex_pkg.sv
ibex/rtl/ibex_cheriot_pkg.sv
${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl/cheriot_reg_pkg.sv
-y ibex/vendor/lowrisc_ip/ip/prim/rtl
-y ibex/vendor/lowrisc_ip/ip/prim_generic/rtl
-y ibex/vendor/pulp_common_cells/rtl
-y ${OT_CHERIOT_DIR}/hw/vendor/pulp_common_cells/rtl
-y ${OT_CHERIOT_DIR}/hw/ip/tlul/rtl
-y ${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl
${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl/cheriot.sv
