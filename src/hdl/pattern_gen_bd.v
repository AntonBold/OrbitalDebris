`timescale 1ns / 1ps

// Verilog shell around pattern_gen for the pl_ps block design. A BD module
// reference must have a Verilog or VHDL top file (Vivado rejects .sv), so
// scripts/bd/pl_ps.tcl references this instead. No logic here.

module pattern_gen_bd #(
    parameter WIDTH          = 1920,
    parameter HEIGHT         = 1080,
    parameter OBJ1_ENABLE    = 1,
    parameter OBJ1_X_START   = 100,
    parameter OBJ1_Y_START   = 100,
    parameter OBJ1_SIZE      = 5,
    parameter OBJ2_ENABLE    = 1,
    parameter OBJ2_X_START   = 500,
    parameter OBJ2_Y_START   = 500,
    parameter OBJ2_SIZE      = 5,
    parameter COLL_ENABLE    = 1,
    parameter COLL_X_START   = 800,
    parameter COLL_Y_START   = 800,
    parameter COLL_WIDTH     = 15,
    parameter COLL_HEIGHT    = 10,
    parameter COLL_THICKNESS = 3,
    parameter NUM_FRAMES     = 1,
    parameter VBLANK_LINES   = 45
)(
    input  wire       i_clk,
    input  wire       i_rst,
    input  wire       i_enable,

    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tvalid,
    output wire       m_axis_tuser,
    output wire       m_axis_tlast
);

    pattern_gen #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .OBJ1_ENABLE(OBJ1_ENABLE),
        .OBJ1_X_START(OBJ1_X_START),
        .OBJ1_Y_START(OBJ1_Y_START),
        .OBJ1_SIZE(OBJ1_SIZE),
        .OBJ2_ENABLE(OBJ2_ENABLE),
        .OBJ2_X_START(OBJ2_X_START),
        .OBJ2_Y_START(OBJ2_Y_START),
        .OBJ2_SIZE(OBJ2_SIZE),
        .COLL_ENABLE(COLL_ENABLE),
        .COLL_X_START(COLL_X_START),
        .COLL_Y_START(COLL_Y_START),
        .COLL_WIDTH(COLL_WIDTH),
        .COLL_HEIGHT(COLL_HEIGHT),
        .COLL_THICKNESS(COLL_THICKNESS),
        .NUM_FRAMES(NUM_FRAMES),
        .VBLANK_LINES(VBLANK_LINES)
    ) inst (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_enable(i_enable),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tuser(m_axis_tuser),
        .m_axis_tlast(m_axis_tlast)
    );

endmodule
