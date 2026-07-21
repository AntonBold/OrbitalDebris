# Verilator simulation Makefile — driven by ./simulate
# Not meant to be called directly; TOP and SRCS come from the script:
#   make sim TOP=<module_name> SRCS="file1.sv file2.sv ..."

SIM_DIR := sim/build
OBJ_DIR := $(SIM_DIR)/obj_dir
BIN     := $(SIM_DIR)/sim
VCD     := dump.vcd

.PHONY: sim clean

sim:
	@if [ -z "$(TOP)" ] || [ -z "$(SRCS)" ]; then \
		echo "Usage: make sim TOP=<module_name> SRCS=\"file1.sv file2.sv ...\""; \
		exit 1; \
	fi
	mkdir -p $(SIM_DIR)
	verilator --binary --timing -Mdir $(OBJ_DIR) -o $(CURDIR)/$(BIN) \
		--top-module $(TOP) $(SRCS) --trace-vcd
	cd $(SIM_DIR) && ./sim
	@echo "Waveform: $(SIM_DIR)/$(VCD)"

clean:
	rm -rf $(SIM_DIR)