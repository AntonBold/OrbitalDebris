`timescale 1ns / 1ps

// Full 1920x1080 frames with the block design's settings (scripts/bd/pl_ps.tcl:
// pattern_gen defaults + MOVE_ENABLE, cca_top NUM_LABELS = 256).
// Checks in pattern_gen_move_env.sv.
module pattern_gen_move_full_tb;
    pattern_gen_move_env #(
        .W(1920), .H(1080),
        .O1X(100), .O1Y(100), .O2X(500), .O2Y(500), .CX(800), .CY(800),
        .MX(300), .MY(60), .MS(3), .DX(4), .DY(0),
        .FRAMES(3), .NUM_LABELS(256)
    ) env ();
endmodule
