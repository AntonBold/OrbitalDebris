#=============================
#
#	save_bd.tcl
# export live block design to tracked tcl
#  - run from vivado console with project open any time BD is changed and want to capture in git
#
#=============================

set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize $script_dir/..]

set bd_name "top_level"
set out_tcl "$repo_root/src/bd/$bd_name.tcl"

set bd_objs [get_files -quiet *.bd]
if {[llength
