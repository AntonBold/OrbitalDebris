`timescale 1ns / 1ps

// Verilog shell around pix_2to1 for the block design. A BD module
// reference must have a Verilog or VHDL top file (Vivado rejects .sv), so
// scripts/bd/pl_ps.tcl references this instead. No wire here.

module pix_2to1_bd (
    input wire aclk,
    input wire aresetn,
    input wire [15:0] s_axis_tdata,
    input wire s_axis_tvalid,
    input wire s_axis_tuser,
    input wire s_axis_tlast,
    output wire s_axis_tready,
    output wire [7:0] m_axis_tdata,
    output wire m_axis_tvalid,
    output wire m_axis_tuser,
    output wire m_axis_tlast,
    input wire m_axis_tready
);

    pix_2to1 inst ( .aclk(aclk),
                    .aresetn(aresetn),
                    .s_axis_tdata(s_axis_tdata),
                    .s_axis_tvalid(s_axis_tvalid),
                    .s_axis_tuser(s_axis_tuser),
                    .s_axis_tlast(s_axis_tlast),
                    .s_axis_tready(s_axis_tready),
                    .m_axis_tdata(m_axis_tdata),
                    .m_axis_tvalid(m_axis_tvalid),
                    .m_axis_tuser(m_axis_tuser),
                    .m_axis_tlast(m_axis_tlast),
                    .m_axis_tready(m_axis_tready)
    );


endmodule
