# ==========================================
# ModelSim / Questa .do script for cca_control
# ==========================================

# Create and map work library
vlib work
vmap work work

# Compile the RTL and Testbench
vlog -sv ../hdl/cca_control.sv
vlog -sv ../tb/cca_control_tb.sv

# Load the simulation with visibility for waveforms
vsim -voptargs="+acc" work.cca_control_tb

# Configure the wave window
view wave
delete wave *

add wave -divider "Testbench Signals"
add wave -position insertpoint sim:/cca_control_tb/*

add wave -divider "DUT Signals"
add wave -position insertpoint sim:/cca_control_tb/dut/*

# Run the simulation
run -all
