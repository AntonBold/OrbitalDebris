# =============================================================================
# create_project.tcl  --  regenerate the Vivado project from tracked sources
#
#   vivado -mode batch -source scripts/create_project.tcl
#   vivado -mode gui   -source scripts/create_project.tcl
#
# Everything Vivado generates lands in build/ (gitignored), including the
# block design and its IP output products. Nothing in build/ is a source of
# truth; delete it and re-run.
#
# Sources, all referenced in place (nothing is copied):
#   src/hdl/*.sv, *.v        RTL (also the module references in the BD)
#   src/xdc/*.xdc            constraints
#   scripts/bd/pl_ps.tcl     block design (built from Tcl, not a .bd file)
#   src/tb/*.sv              simulation sources
#
# Project top: pl_ps_wrapper for now. top.sv is empty until the HDMI path is
# integrated; switch top_module to "top" then. src/bd/hdmi_rx is still empty
# and is not added.
# =============================================================================

# ---- paths ------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]
if {[catch {exec git -C $script_dir rev-parse --show-toplevel} repo_root]} {
    error "not a git checkout (or git not on PATH): $repo_root"
}
set repo_root [file normalize $repo_root]

set proj_name  "debris_tracking"
set build_dir  $repo_root/build
set part       "xczu5ev-sfvc784-1-e"
set board_part "digilentinc.com:gzu_5ev:part0:1.1"
set top_module "pl_ps_wrapper"

# cca_top's label table size. 1024 doesn't route: the translator LUT and the
# zeros table synthesize to flip-flops with 1024:1 read muxes. 256 matches
# the 256-centroid BRAM slot and passes the full-HD golden suite.
set cca_num_labels 256

# ---- version guard ----------------------------------------------------------
set required_version "2025.2"
if {[version -short] ne $required_version} {
    puts "WARNING: built with Vivado $required_version, running [version -short]"
}

# ---- board files ------------------------------------------------------------
# MUST come before create_project.
set_param board.repoPaths [list $repo_root/boards]

# ---- project ----------------------------------------------------------------
file mkdir $build_dir
create_project -force $proj_name $build_dir/$proj_name -part $part
set_property board_part      $board_part    [current_project]
set_property target_language Verilog        [current_project]

# ---- RTL --------------------------------------------------------------------
# Added before the block design: its module-reference cells (cca_top,
# pattern_gen, sync_debouncer) resolve against modules in sources_1.
set rtl_files [lsort [concat \
    [glob -nocomplain -directory $repo_root/src/hdl *.sv] \
    [glob -nocomplain -directory $repo_root/src/hdl *.v]]]
add_files -norecurse -fileset sources_1 $rtl_files
set sv_files [get_files -quiet -of_objects [get_filesets sources_1] *.sv]
if {[llength $sv_files] > 0} {
    set_property file_type SystemVerilog $sv_files
}
update_compile_order -fileset sources_1

# ---- constraints ------------------------------------------------------------
set xdc_files [lsort [glob -nocomplain -directory $repo_root/src/xdc *.xdc]]
if {[llength $xdc_files] > 0} {
    add_files -norecurse -fileset constrs_1 $xdc_files
}

# ---- block design -----------------------------------------------------------
source $repo_root/scripts/bd/pl_ps.tcl
create_pl_ps $repo_root $cca_num_labels

set bd_file [get_files pl_ps.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top -force]
add_files -norecurse $wrapper
close_bd_design [current_bd_design]

# ---- top / compile order ----------------------------------------------------
set_property top $top_module [get_filesets sources_1]
update_compile_order -fileset sources_1

# ---- simulation fileset -----------------------------------------------------
set tb_files [glob -nocomplain $repo_root/src/tb/*.sv]
if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 -norecurse $tb_files
    update_compile_order -fileset sim_1
    if {[llength [get_files -quiet -of_objects [get_filesets sim_1] tb_top.sv]] == 1} {
        set_property top tb_top [get_filesets sim_1]
    } else {
        puts "NOTE: no tb_top.sv found, letting Vivado infer sim top"
    }
} else {
    puts "NOTE: no testbenches in src/tb, skipping sim fileset"
}

puts "Project created at $build_dir/$proj_name/$proj_name.xpr (top: $top_module, cca_top NUM_LABELS = $cca_num_labels)"
