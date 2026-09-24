# ==========================================
# ModelSim / Questa .do script for label_decision_logic
# ==========================================

# Create and map work library
vlib work
vmap work work

# Compile the RTL and Testbench
vlog -sv ../hdl/label_decision_logic.sv
vlog -sv ../tb/label_decision_logic_tb.sv

# Load the simulation with visibility for waveforms
vsim -voptargs="+acc" work.label_decision_logic_tb

# Configure the wave window
view wave
delete wave *

add wave -divider "Testbench Signals"
add wave -position insertpoint sim:/label_decision_logic_tb/*

add wave -divider "DUT Signals"
add wave -position insertpoint sim:/label_decision_logic_tb/dut/*

# Run the simulation
run -all
