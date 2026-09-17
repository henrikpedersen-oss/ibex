# CHERIoT-Ibex AutoCover — interactive GUI with design loaded.
#
# Loads and elaborates the design, then opens JG for interactive use.
# Requires build/fusesoc to exist (run `make build/fusesoc` first).
#
# Once JG opens:
#   autocover -module { cheri_ex ibex_controller ... }  (check/run)
#   prove -covers -all                                   (run proving)
#   report -cover                                        (view results)

clear -all

analyze -sv12 +define+SYNTHESIS \
  -f_relative_to_file_location build/fusesoc/lowrisc_ibex_ibex_formal_0.1/default-vcs/lowrisc_ibex_ibex_formal_0.1.scr

elaborate -top ibex_top -disable_auto_bbox

clock clk_i
reset ~rst_ni
