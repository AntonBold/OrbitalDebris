# =============================================================================
# create_project.tcl  --  regenerate the Vivado project from tracked sources
#
#   vivado -mode batch -source scripts/create_project.tcl
#   vivado -mode gui   -source scripts/create_project.tcl
#
# Everything Vivado generates lands in build/ (gitignored). Nothing in build/
# is a source of truth; delete it and re-run.
# =============================================================================

# ---- paths ------------------------------------------------------------------
# info script works whether launched from repo root or scripts/
set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize $script_dir]

set proj_name  "debris_tracking"
set build_dir  $repo_root/build
set part       "xczu5ev-sfvc784-1-e"          ;# verify against your board
set board_part "digilentinc.com:gzu_5ev:part0:1.1"   ;# see note below

# ---- version guard ----------------------------------------------------------
# Vivado project files are not forward/backward compatible. Fail loudly rather
# than let a teammate silently upgrade the .xpr.
set required_version "2025.2"
if {[version -short] ne $required_version} {
    puts "WARNING: built with Vivado $required_version, running [version -short]"
}

# ---- board files ------------------------------------------------------------
set_param board.repoPaths [list $repo_root/boards]


# ---- project ----------------------------------------------------------------
file mkdir $build_dir
create_project -force $proj_name $build_dir/$proj_name -part $part
set_property board_part      $board_part [current_project]
set_property target_language Verilog     [current_project]

# Keep generated IP inside the project, never beside the tracked sources.
set_property ip_output_repo $build_dir/$proj_name/ip_cache [current_project]

# ---- RTL --------------------------------------------------------------------
# Prefer an explicit list over glob: a stray scratch file in src/hdl/ silently
# entering the build is a bad afternoon. If the list gets long, read it from a
# manifest file (src/hdl/files.f) and keep that tracked.
set rtl_files [list \
    $repo_root/src/hdl/ccl_decision.sv \
    $repo_root/src/hdl/comb_mux.sv \
    $repo_root/src/hdl/fifo.sv \
    $repo_root/src/hdl/label_decision_logic.sv \
    $repo_root/src/hdl/translator_lut.sv \
]
add_files -norecurse -fileset sources_1 $rtl_files
set_property file_type SystemVerilog [get_files *.sv]

# ---- constraints ------------------------------------------------------------
# add_files -norecurse -fileset constrs_1 [list \
    
# ]

# Optional: force ordering if you split early/late constraints
# set_property PROCESSING_ORDER LATE [get_files timing.xdc]

# ---- block design -----------------------------------------------------------
# Regenerate the BD (and every IP inside it) into the project.
# To refresh this file after editing the BD in the GUI:
#   write_bd_tcl -force $repo_root/src/bd/top_level.tcl
set bd_tcl $repo_root/src/bd/system_bd.tcl
if {[file exists $bd_tcl]} {
    source $bd_tcl

    set bd_file [get_files -of_objects [get_filesets sources_1] *.bd]
    if {[llength $bd_file] != 1} {
      error "expected only one BD, got : $bd_file"
    }

    set wrapper [make_wrapper -files $bd_file -top -force]
    add_files -norecurse $wrapper
} else {
    puts "NOTE: no BD tcl yet, skipping"
}

# ---- simulation fileset -----------------------------------------------------
# XSim for BD/AXI-level tests the Verilator flow can't reach.
set tb_files [glob -nocomplain $repo_root/sim/tb/*.sv]

if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 -norecurse $tb_files
    update_compile_order -fileset sim_1

    if {[llength [get_files -quiet -of_objects [get_filesets sim_1] tb_top.sv]] == 1} {
        set_property top tb_top [get_filesets sim_1]
    } else {
        puts "NOTE: no tb_top.sv found, letting Vivado infer sim top"
    }
} else {
    puts "NOTE: no testbenches in sim/tb, skipping sim fileset"
}

puts "Project created at $build_dir/$proj_name/$proj_name.xpr"