# =============================================================================
# generate_bitstream.tcl  --  synthesize, implement and export the hardware
#
#   vivado -mode batch -source scripts/generate_bitstream.tcl -log build/bit.log -nojournal
#   vivado -mode batch -source scripts/generate_bitstream.tcl -log build/bit.log -nojournal -tclargs 16
#
# The optional argument is the number of parallel jobs (default 8). In the
# GUI, source it from the Tcl console with the project open.
#
# Needs the project from scripts/create_project.tcl. Always rebuilds from
# synthesis, so the result matches the current sources. Outputs:
#   build/debris_tracking/debris_tracking.runs/impl_1/pl_ps_wrapper.bit
#   build/pl_ps.xsa   (bitstream included; scripts/run_board.tcl takes its
#                      psu_init from here, the Vitis platform is built from it)
# =============================================================================

set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize $script_dir/..]
set xpr        $repo_root/build/debris_tracking/debris_tracking.xpr
set xsa        $repo_root/build/pl_ps.xsa
set jobs       [expr {[llength $argv] > 0 ? [lindex $argv 0] : 8}]

if {[current_project -quiet] eq ""} {
    if {![file exists $xpr]} {
        error "no project at $xpr -- run scripts/create_project.tcl first"
    }
    open_project $xpr
}

# If create_project.tcl failed while building the block design, the project
# has only the RTL and Vivado picks some module (e.g. cca_top_bd) as top;
# implementing that fails at write_bitstream with unconstrained I/O.
set top [get_property top [get_filesets sources_1]]
if {$top ne "pl_ps_wrapper" || [get_files -quiet pl_ps.bd] eq ""} {
    error "project top is '$top' and pl_ps.bd is [expr {[get_files -quiet pl_ps.bd] eq "" ? "missing" : "present"}]:\
create_project.tcl did not finish. Check its log for the first ERROR, fix it, delete build/ and re-run it."
}

# synth_1 reset also resets impl_1
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1

set impl [get_runs impl_1]
if {[get_property PROGRESS $impl] ne "100%"} {
    error "impl_1 did not finish (status: [get_property STATUS $impl]) -- see [get_property DIRECTORY $impl]/runme.log"
}

write_hw_platform -fixed -include_bit -force $xsa

set wns [get_property STATS.WNS $impl]
puts "================================================================"
puts "bitstream: [get_property DIRECTORY $impl]/pl_ps_wrapper.bit"
puts "xsa:       $xsa"
puts "WNS:       $wns ns[expr {$wns < 0 ? "  (timing NOT met)" : ""}]"
puts "================================================================"
