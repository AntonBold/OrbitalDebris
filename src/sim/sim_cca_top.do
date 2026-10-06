# ==========================================
# ModelSim / Questa .do script for cca_top (Integration Test)
# ==========================================

vlib work
vmap work work

# Compile all modules in the datapath
vlog -sv ../hdl/translator_lut.sv
vlog -sv ../hdl/label_decision_logic.sv
vlog -sv ../hdl/fifo.sv
vlog -sv ../hdl/cca_control.sv
vlog -sv ../hdl/ccl_decision.sv
vlog -sv ../hdl/feature_extract.sv
vlog -sv ../hdl/pattern_gen.sv
vlog -sv ../hdl/cca_top.sv

# Compile the integration testbench
vlog -sv ../tb/cca_top_tb.sv

# Load simulation
vsim -voptargs="+acc" work.cca_top_tb

# Setup Waveform
view wave
delete wave *

add wave -divider "AXI-Stream Video Interface"
add wave -position insertpoint sim:/cca_top_tb/clk
add wave -position insertpoint sim:/cca_top_tb/tuser
add wave -position insertpoint sim:/cca_top_tb/tlast
add wave -position insertpoint sim:/cca_top_tb/tvalid
add wave -position insertpoint sim:/cca_top_tb/tdata

add wave -divider "AXI BRAM Interface (PS)"
add wave -position insertpoint sim:/cca_top_tb/interrupt
add wave -position insertpoint sim:/cca_top_tb/bram_en
add wave -position insertpoint sim:/cca_top_tb/bram_we
add wave -position insertpoint sim:/cca_top_tb/bram_addr
add wave -radix hex -position insertpoint sim:/cca_top_tb/bram_wdata

add wave -divider "Internal Core Tracking"
add wave -position insertpoint sim:/cca_top_tb/dut/controller/row_counter
add wave -position insertpoint sim:/cca_top_tb/dut/controller/col_counter
add wave -position insertpoint sim:/cca_top_tb/dut/decision_top/next_label
add wave -position insertpoint sim:/cca_top_tb/dut/decision_top/lut_we

add wave -divider "Feature Extract Dump"
add wave -position insertpoint sim:/cca_top_tb/dut/fe/state
add wave -position insertpoint sim:/cca_top_tb/dut/fe/read_ptr
add wave -position insertpoint sim:/cca_top_tb/dut/fe/valid_centroid_count

run -all
