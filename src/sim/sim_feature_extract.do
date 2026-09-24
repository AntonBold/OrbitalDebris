# ==========================================
# ModelSim / Questa .do script for feature_extract
# ==========================================

# Create and map work library
vlib work
vmap work work

# Compile the RTL and Testbench
vlog -sv ../hdl/feature_extract.sv
vlog -sv ../tb/feature_extract_tb.sv

# Load the simulation with visibility for waveforms
vsim -voptargs="+acc" work.feature_extract_tb

# Configure the wave window
view wave
delete wave *

add wave -divider "Testbench Signals"
add wave -position insertpoint sim:/feature_extract_tb/*

add wave -divider "DUT Internal Logic"
# For the feature extractor, it is highly useful to see the internal RAMs and State Machine
add wave -position insertpoint sim:/feature_extract_tb/dut/state
add wave -position insertpoint sim:/feature_extract_tb/dut/read_ptr
add wave -position insertpoint sim:/feature_extract_tb/dut/current_bram_addr
add wave -position insertpoint sim:/feature_extract_tb/dut/area_ram
add wave -position insertpoint sim:/feature_extract_tb/dut/zeros_ram

# Run the simulation
run -all
