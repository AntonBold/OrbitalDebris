`timescale 1ns / 1ps

// directed suite: 64x48 frames from scripts/golden/cca_golden.py directed.
// All checking lives in cca_env_tb.sv; plusargs are documented there.
module cca_directed_tb;
    cca_env_tb #(.W(64), .H(48), .VEC_DEFAULT("vectors/cca_directed.txt")) env ();
endmodule
