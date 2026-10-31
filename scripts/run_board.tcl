# =============================================================================
# run_board.tcl  --  program the Genesys ZU and start debris_app over JTAG
#
#   xsdb scripts/run_board.tcl
#
# Vitis's Run/Debug launch hangs on this board: after the FSBL it resets the
# A53 and the ELF download fails with "Memory write error at 0x0 ... EDITR
# not ready". This does the same job without the FSBL: psu_init from the
# .xsa (clocks, DDR, PS-PL interface), then the bitstream, then the app.
#
# Needs: board in JTAG boot mode and powered; build/pl_ps.xsa and the
# bitstream (scripts/generate_bitstream.tcl); vitis/debris_app built. Open the serial
# terminal (UART0, 115200) before running. Close Vitis's debug session
# first so it isn't holding the JTAG cable.
# =============================================================================

set repo_root [file normalize [file dirname [info script]]/..]
set xsa  $repo_root/build/pl_ps.xsa
set bit  $repo_root/build/debris_tracking/debris_tracking.runs/impl_1/pl_ps_wrapper.bit
set elf  $repo_root/vitis/debris_app/build/debris_app.elf
set init_dir $repo_root/build/psinit

foreach f [list $xsa $bit $elf] {
    if {![file exists $f]} { error "missing $f" }
}

# psu_init.tcl comes from the same .xsa as the bitstream
file mkdir $init_dir
exec unzip -o -q $xsa psu_init.tcl -d $init_dir

connect
targets -set -nocase -filter {name =~ "*PSU*"}
rst -system
after 1000

source $init_dir/psu_init.tcl
psu_init
after 1000
psu_ps_pl_isolation_removal
psu_ps_pl_reset_config

targets -set -nocase -filter {name =~ "*A53*#0"}
rst -processor

# DDR check before the download, so a DDR problem says so instead of
# failing partway through dow
mwr 0x0 0x12345678
if {[mrd -value 0x0] != 0x12345678} {
    error "DDR check failed: wrote 0x12345678 to 0x0, read [format 0x%08x [mrd -value 0x0]]"
}
puts "DDR ok"

fpga -file $bit
puts "PL programmed: $bit"

dow $elf
con
puts "debris_app running: watch the serial terminal. FREE_RUN 1 in main.c streams frames on its own; with FREE_RUN 0, press BTN2 (btn\[2\], pin B10) for a frame"
