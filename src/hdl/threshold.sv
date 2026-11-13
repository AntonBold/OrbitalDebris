`timescale 1ns/1ps

// Video threshold: HDMI RX Subsystem AXI4-Stream (2 px/beat, RGB 8 bits per
// component, 48-bit tdata, pixel 0 in the low 24 bits) -> binarized stream
// (16-bit tdata, 2 px/beat). Output contract: docs/hdmi-cca_interface.md v0.2.
//
//   m_axis_tdata[0] = pixel 0 is foreground
//   m_axis_tdata[8] = pixel 1 is foreground
//   all other output bits are 0
//
// Method, modelled on MATLAB:
//   grey       = rgb2gray(pixel) = round(0.2989 R + 0.5870 G + 0.1140 B)
//   foreground = grey > THR        (imbinarize: values above the threshold are 1)
// THR is the grey level 0..255 (MATLAB level x 255, rounded down). THR 0 makes
// every pixel but pure black foreground; THR 255 makes none foreground.
// Rounding to the nearest integer is an assumption (the MATLAB page for
// rgb2gray does not say how uint8 results are rounded).
//
// Byte lanes of each 24-bit pixel, from the low byte up: G = [7:0], B = [15:8],
// R = [23:16]. This is the order the Vivado metadata of the RXSS output gives
// (G_B_R_444).
//
// Purely combinational (latency 0):
//   - tvalid, tuser and tlast pass straight through, so they stay on the beat
//     of their pixels and blanking stays tvalid low. Nothing is buffered.
//   - tready passes straight back, so no beat is dropped or duplicated under
//     backpressure, and the output is stable while stalled as long as the
//     input is (AXI4-Stream requires that of the source).
//   - There is no state, so there is nothing to clear in reset. aclk and
//     aresetn are present so Vivado infers a normal interface.
//
// THR has no default on purpose: whoever instantiates this block has to choose.
// The Vivado wrapper (threshold_bd.v) is where the value is set.

module threshold #(
    parameter int THR
) (
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic        aclk,
    input  logic        aresetn,
    /* verilator lint_on UNUSEDSIGNAL */

    input  logic [47:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tuser,
    input  logic        s_axis_tlast,

    output logic [15:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tuser,
    output logic        m_axis_tlast
);

    if (THR < 0 || THR > 255) begin : g_chk_thr $error("threshold: THR must be 0..255"); end

    // With S = 2989 R + 5870 G + 1140 B (the weights x 10000):
    //   grey = (S + 5000) / 10000, rounded down  ->  grey > THR  <=>  S >= THR*10000 + 5000
    // so one integer compare against a constant replaces the divide and the round.
    // S is at most 9999 * 255 = 2,549,745, which fits in 22 bits; LIM is at most
    // 2,555,000, so THR = 255 is never reached (no pixel is foreground).
    localparam int LIM = THR * 10000 + 5000;

    // THR = 255 makes the compare constant false, which lint flags. That is allowed.
    /* verilator lint_off CMPCONST */
    function automatic logic is_fg(input logic [23:0] pix);
        logic [21:0] s;
        s = 22'(pix[23:16]) * 22'd2989      // R
          + 22'(pix[7:0])   * 22'd5870      // G
          + 22'(pix[15:8])  * 22'd1140;     // B
        return s >= 22'(LIM);
    endfunction
    /* verilator lint_on CMPCONST */

    logic [1:0] fg;
    always_comb begin
        fg[0] = is_fg(s_axis_tdata[23:0]);
        fg[1] = is_fg(s_axis_tdata[47:24]);
    end

    assign m_axis_tdata  = {7'b0, fg[1], 7'b0, fg[0]};
    assign m_axis_tvalid = s_axis_tvalid;
    assign m_axis_tuser  = s_axis_tuser;
    assign m_axis_tlast  = s_axis_tlast;
    assign s_axis_tready = m_axis_tready;

endmodule
