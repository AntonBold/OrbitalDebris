`timescale 1ns / 1ps

// Testbench-only AXI4-Stream frame driver for cca_top.
//
// Load a frame into pix[][] (hierarchically), set the knobs, then call
// send_frame() on a falling edge. Each pixel is driven on a falling edge and
// held for one cycle, so the DUT samples it cleanly on the rising edge;
// send_frame() returns on the falling edge after the last pixel, with tvalid
// already low. Knobs are cleared by clear_knobs().
//
// Knobs:
//   gap_pct          chance (%) of a tvalid-low cycle before each pixel
//   drop_tlast_row   row whose tlast is suppressed           (malformed)
//   extra_tlast_*    extra tlast at (row, x)                 (malformed)
//   no_tuser         suppress tuser on the first pixel       (malformed)
//   rows             number of rows to send (-1 = H)         (malformed)
//   len_row/len_val  send len_val pixels on row len_row      (malformed)
//   abort_at         stop after this many pixels (reset injection)
// Pixels outside pix[][] (long lines, extra rows) are background.

module axis_frame_driver #(
    parameter W = 64,
    parameter H = 48
)(
    input  logic       clk,
    output logic [7:0] tdata,
    output logic       tvalid,
    output logic       tuser,
    output logic       tlast
);

    logic pix [0:H-1][0:W-1];

    int gap_pct;
    int drop_tlast_row;
    int extra_tlast_row, extra_tlast_x;
    bit no_tuser;
    int rows;
    int len_row, len_val;
    int abort_at;

    int unsigned rng_state = 32'h1234_5678;   // xorshift32: same sequence in every simulator
    longint pixels_sent = 0;
    longint gap_cycles  = 0;
    bit     in_frame    = 1'b0;

    initial begin
        tdata  = '0;
        tvalid = 1'b0;
        tuser  = 1'b0;
        tlast  = 1'b0;
        clear_knobs();
    end

    function automatic void clear_knobs();
        gap_pct         = 0;
        drop_tlast_row  = -1;
        extra_tlast_row = -1;
        extra_tlast_x   = -1;
        no_tuser        = 1'b0;
        rows            = -1;
        len_row         = -1;
        len_val         = -1;
        abort_at        = -1;
    endfunction

    function automatic void set_seed(int unsigned s);
        rng_state = (s == 0) ? 32'h1234_5678 : s;
    endfunction

    function automatic int unsigned next_rand();
        rng_state ^= rng_state << 13;
        rng_state ^= rng_state >> 17;
        rng_state ^= rng_state << 5;
        return rng_state;
    endfunction

    task automatic idle(int cycles);
        repeat (cycles) begin
            tvalid = 1'b0;
            tuser  = 1'b0;
            tlast  = 1'b0;
            @(negedge clk);
        end
    endtask

    // Returns 1 if the frame was aborted early (abort_at)
    task automatic send_frame(output bit aborted);
        int nrows, len, k;
        nrows   = (rows < 0) ? H : rows;
        k       = 0;
        aborted = 1'b0;
        in_frame = 1'b1;
        for (int y = 0; y < nrows; y++) begin
            len = (y == len_row) ? len_val : W;
            for (int x = 0; x < len; x++) begin
                if (gap_pct > 0) begin
                    while ((next_rand() % 100) < gap_pct) begin
                        idle(1);
                        gap_cycles++;
                    end
                end
                tvalid = 1'b1;
                tdata  = {7'b0, (y < H && x < W) ? pix[y][x] : 1'b0};
                tuser  = (x == 0 && y == 0 && !no_tuser);
                tlast  = ((x == len - 1) && (y != drop_tlast_row)) ||
                         ((y == extra_tlast_row) && (x == extra_tlast_x));
                @(negedge clk);
                pixels_sent++;
                k++;
                if (abort_at >= 0 && k >= abort_at) begin
                    aborted = 1'b1;
                    break;
                end
            end
            if (aborted) break;
        end
        tvalid = 1'b0;
        tuser  = 1'b0;
        tlast  = 1'b0;
        in_frame = 1'b0;
    endtask

endmodule
