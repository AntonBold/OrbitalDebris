`timescale 1ns / 1ps

// Verilog shell around cca_top for the pl_ps block design. A BD module
// reference must have a Verilog or VHDL top file (Vivado rejects .sv), so
// scripts/bd/pl_ps.tcl references this instead. No logic here.

module cca_top_bd #(
    parameter NUM_LABELS = 1024,
    parameter ROW_SIZE   = 1920,
    parameter COL_SIZE   = 1080
)(
    input  wire        clk,
    input  wire        rst,

    input  wire [7:0]  i_tdata,
    input  wire        i_tvalid,
    input  wire        i_tuser,
    input  wire        i_tlast,
    output wire        o_trdy,
    output wire        o_interrupt,

    output wire [31:0] o_bram_addr,
    output wire [31:0] o_bram_wdata,
    output wire [3:0]  o_bram_we,
    output wire        o_bram_en,
    output wire        o_bram_clk
);

    cca_top #(
        .NUM_LABELS(NUM_LABELS),
        .ROW_SIZE(ROW_SIZE),
        .COL_SIZE(COL_SIZE)
    ) inst (
        .clk(clk),
        .rst(rst),
        .i_tdata(i_tdata),
        .i_tvalid(i_tvalid),
        .i_tuser(i_tuser),
        .i_tlast(i_tlast),
        .o_trdy(o_trdy),
        .o_interrupt(o_interrupt),
        .o_bram_addr(o_bram_addr),
        .o_bram_wdata(o_bram_wdata),
        .o_bram_we(o_bram_we),
        .o_bram_en(o_bram_en),
        .o_bram_clk(o_bram_clk)
    );

endmodule
