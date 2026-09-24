# ==========================================
# ModelSim / Questa .do script for translator_lut
# ==========================================

# Create and map work library
vlib work
vmap work work

# Compile the RTL and Testbench
vlog -sv ../hdl/translator_lut.sv
vlog -sv ../tb/translator_lut_tb.sv

# Load the simulation with visibility for waveforms
vsim -voptargs="+acc" work.translator_lut_tb

# Configure the wave window
view wave
delete wave *

add wave -divider "Testbench Signals"
add wave -position insertpoint sim:/translator_lut_tb/*

add wave -divider "DUT Signals"
add wave -position insertpoint sim:/translator_lut_tb/dut/*

# Run the simulation
run -all
