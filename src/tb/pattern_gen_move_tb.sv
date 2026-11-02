`timescale 1ns / 1ps

// Small frame (64x48): the mover steps 20 px per frame, so it jumps back to
// its start twice in 6 frames. Row 44 keeps it clear of the U shape
// (y 30-39); touching it would merge them. Checks in pattern_gen_move_env.sv.
module pattern_gen_move_tb;
    pattern_gen_move_env #(.W(64), .H(48), .MX(2), .MY(44), .DX(20), .DY(0), .FRAMES(6)) env ();
endmodule
