# =============================================================================
# create_project.tcl  --  regenerate the Vivado project from tracked sources
#
#   vivado -mode batch -source scripts/create_project.tcl
#   vivado -mode gui   -source scripts/create_project.tcl
#
# Everything Vivado generates lands in build/ (gitignored). Nothing in build/
# is a source of truth; delete it and re-run.
#
# Two block designs live side by side (pl_ps, hdmi_rx), each wrapped but
# neither set as the project top. top.sv instantiates both wrapper modules
# plus the CCL pipeline and is the actual project top.
# =============================================================================

# ---- paths ------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]
if {[catch {exec git -C $script_dir rev-parse --show-toplevel} repo_root]} {
    error "not a git checkout (or git not on PATH): $repo_root"
}
set repo_root [file normalize $repo_root]

set proj_name  "debris_tracking"
set build_dir  $repo_root/build
set part       "xczu5ev-sfvc784-1-e"          ;# verify against your board
set board_part "digilentinc.com:gzu_5ev:part0:1.1"

# ---- version guard ----------------------------------------------------------
set required_version "2025.2"
if {[version -short] ne $required_version} {
    puts "WARNING: built with Vivado $required_version, running [version -short]"
}

# ---- board files --------------------------------------------------------
# MUST come before create_project.
set_param board.repoPaths [list $repo_root/boards]

# ---- project ----------------------------------------------------------------
file mkdir $build_dir
create_project -force $proj_name $build_dir/$proj_name -part $part
set_property board_part      $board_part [current_project]
set_property target_language VHDL        [current_project]
set_property ip_output_repo  $build_dir/$proj_name/ip_cache [current_project]

# ---- RTL --------------------------------------------------------------------
# top.sv must exist before the BD sections below -- Add Module in each BD
# resolves against modules already present in sources_1.
set rtl_files [list \
    $repo_root/src/hdl/top.sv \
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
#     $repo_root/src/constraints/pins.xdc \
#     $repo_root/src/constraints/timing.xdc \
# ]

# ---- block designs ------------------------------------------------------
# Each BD is created and lives permanently at src/bd/<name>/<name>.bd --
# own directory, owned by one person, referenced in place (like the .sv
# files). Nothing to copy or export; the tracked file is the live file.
#   pl_ps.bd    -- Zynq PS + AXI4-Lite BRAM controller  (you)
#   hdmi_rx.bd  -- HDMI RX + AXI-Stream master           (teammate)
#
# Neither BD is set as project top -- both become sub-blocks instantiated
# by top.sv.

proc add_bd {repo_root name} {
    set src_bd "$repo_root/src/bd/$name/$name.bd"
    if {![file exists $src_bd]} {
        puts "NOTE: no tracked .bd for $name yet, skipping"
        return
    }
    add_files -norecurse -fileset sources_1 $src_bd

    set bd_file [get_files -quiet -of_objects [get_filesets sources_1] "$name.bd"]
    if {[llength $bd_file] != 1} {
        error "expected exactly one BD file named $name.bd, got: $bd_file"
    }

    # -top intentionally omitted: this BD is a sub-block, not project top.
    set wrapper [make_wrapper -files $bd_file -force]
    add_files -norecurse $wrapper
    puts "Added BD $name -> wrapper $wrapper"
}

add_bd $repo_root "pl_ps"
add_bd $repo_root "hdmi_rx"

# ---- top / compile order -----------------------------------------------
# top.sv (in src/hdl/) instantiates pl_ps_wrapper and hdmi_rx_wrapper.
set_property top top [get_filesets sources_1]
update_compile_order -fileset sources_1

# ---- simulation fileset -----------------------------------------------------
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