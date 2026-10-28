`timescale 1ns / 1ps

// full suite: 1920x1080 frames from scripts/golden/cca_golden.py full.
// All checking lives in cca_env_tb.sv; plusargs are documented there.
module cca_full_tb;
    cca_env_tb #(.W(1920), .H(1080), .VEC_DEFAULT("vectors/cca_full.txt")) env ();
endmodule
