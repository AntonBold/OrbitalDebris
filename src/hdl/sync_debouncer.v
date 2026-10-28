`timescale 1ns / 1ps

// Push-button input for pattern_gen's i_enable: synchronize, debounce, and
// output a single-cycle pulse per press.
//
// A pulse (not the button level) so one press gives one burst of
// pattern_gen frames: while i_enable stays high, pattern_gen restarts right
// after each frame with a 1-cycle gap, far below the ~2,600 idle cycles
// cca_top needs between frames (docs/hdmi-cca_interface.md, Frame Timing).
//
// Debounce: the synchronized button must hold a new value for STABLE_CYCLES
// consecutive clocks before the debounced level changes. Mechanical bounce
// lasts milliseconds, so the default is 20 ms at 100 MHz. The pulse fires on
// the debounced press (0 -> 1), never on release.

module sync_debouncer #(
    parameter integer STABLE_CYCLES = 2000000
)(
    input  wire sys_clk,
    input  wire button,             // active high
    output reg  sync_deb_signal     // 1-cycle pulse per press
);

    // 2-FF synchronizer: the button is asynchronous to sys_clk
    reg button_sync_1 = 1'b0;
    reg button_sync_2 = 1'b0;

    reg button_state = 1'b0;        // debounced level
    reg [$clog2(STABLE_CYCLES + 1) - 1:0] stable_count = 0;

    initial sync_deb_signal = 1'b0;

    always @(posedge sys_clk) begin
        button_sync_1 <= button;
        button_sync_2 <= button_sync_1;

        sync_deb_signal <= 1'b0;
        if (button_sync_2 == button_state) begin
            // no change pending (or it bounced back): restart the count
            stable_count <= 0;
        end else if (stable_count == STABLE_CYCLES - 1) begin
            // new value held long enough: accept it
            stable_count <= 0;
            button_state <= button_sync_2;
            if (button_sync_2)
                sync_deb_signal <= 1'b1;
        end else begin
            stable_count <= stable_count + 1'b1;
        end
    end

endmodule
