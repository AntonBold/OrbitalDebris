`timescale 1ns/1ps

// Block-design shell for threshold.sv. Vivado module references reject .sv,
// so this logic-free Verilog top instantiates threshold.
//
// Input is an AXI4-Stream slave interface (s_axis, 48-bit RGB, 2 px/beat), so
// it connects straight to the register slice output. The binarized output is
// loose scalar pins (bin_*), because the centroiding hierarchy takes scalar
// pins (s_axis_tdata[15:0], s_axis_tvalid, s_axis_tuser, s_axis_tlast, and
// s_axis_tready as an output). X_INTERFACE_IGNORE stops Vivado from grouping
// the bin_* pins into an interface by name.
//
// Method (MATLAB): grey = rgb2gray(pixel), foreground = grey > THR. The value
// of THR is NOT decided yet: the parameter below is a PLACEHOLDER until the
// video side and the centroiding side agree (hdmi-cca_interface.md, open
// question THR-3). Vivado shows it as a module parameter, so it can be changed
// in the block design without editing RTL.

module threshold_bd #(
    parameter integer THR = 32      // PLACEHOLDER: grey level 0..255, foreground = grey > THR
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis, ASSOCIATED_RESET aresetn" *)
    input  wire        aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        aresetn,

    // video side: AXI4-Stream slave (inferred from the s_axis_ names)
    input  wire [47:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tuser,
    input  wire        s_axis_tlast,

    // centroiding side: scalar pins
    (* X_INTERFACE_IGNORE = "true" *) output wire [15:0] bin_tdata,
    (* X_INTERFACE_IGNORE = "true" *) output wire        bin_tvalid,
    (* X_INTERFACE_IGNORE = "true" *) input  wire        bin_tready,
    (* X_INTERFACE_IGNORE = "true" *) output wire        bin_tuser,
    (* X_INTERFACE_IGNORE = "true" *) output wire        bin_tlast
);

    threshold #(
        .THR(THR)
    ) u_threshold (
        .aclk         (aclk),
        .aresetn      (aresetn),
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tuser (s_axis_tuser),
        .s_axis_tlast (s_axis_tlast),
        .m_axis_tdata (bin_tdata),
        .m_axis_tvalid(bin_tvalid),
        .m_axis_tready(bin_tready),
        .m_axis_tuser (bin_tuser),
        .m_axis_tlast (bin_tlast)
    );

endmodule
