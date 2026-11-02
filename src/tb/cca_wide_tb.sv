`timescale 1ns / 1ps

// wide suite: 256x64 frames from scripts/golden/cca_golden.py wide.
// All checking lives in cca_env_tb.sv; plusargs are documented there.
module cca_wide_tb;
    cca_env_tb #(.W(256), .H(64), .VEC_DEFAULT("vectors/cca_wide.txt")) env ();
endmodule
