# CHERIoT-Ibex AutoCover — bare JasperGold entry point for syntax exploration.
#
# Dumps all available JG commands to /tmp/jg_cmds.txt on startup so you can
# grep for the correct SPS/BPS/cover command names without typing anything.
#
# After opening, also try interactively:
#   help check_sps
#   help check_bps
#   check_sps -help

set f [open /tmp/jg_cmds.txt w]
puts $f [info commands]
close $f
puts "Command list written to /tmp/jg_cmds.txt"
