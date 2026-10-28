# Verilator simulation Makefile — driven by ./simulate
# Not meant to be called directly; TOP and SRCS come from the script:
#   make sim TOP=<module_name> SRCS="file1.sv file2.sv ..." [SIM_ARGS="+plusargs"]

SIM_DIR := sim/build
# Per-testbench build dir and binary: with a shared one, switching back to a
# TB whose objects were already up to date skipped the relink and ran the
# previously built TB instead.
OBJ_DIR := $(SIM_DIR)/obj_dir/$(TOP)
BIN     := $(SIM_DIR)/sim_$(TOP)
VCD     := dump.vcd

.PHONY: sim clean

sim:
	@if [ -z "$(TOP)" ] || [ -z "$(SRCS)" ]; then \
		echo "Usage: make sim TOP=<module_name> SRCS=\"file1.sv file2.sv ...\""; \
		exit 1; \
	fi
	mkdir -p $(OBJ_DIR)
	rm -f $(SIM_DIR)/$(VCD)
	# -Wno-fatal: lint warnings still print but don't stop the build
	verilator --binary --timing -Wno-fatal -Mdir $(OBJ_DIR) -o $(CURDIR)/$(BIN) \
		--top-module $(TOP) $(SRCS) --trace-vcd
	cd $(SIM_DIR) && ./sim_$(TOP) $(SIM_ARGS)
	@echo "Waveform: $(SIM_DIR)/$(VCD)"

clean:
	rm -rf $(SIM_DIR)