module cca_top #(
    parameter NUM_LABELS = 1024,
    parameter ROW_SIZE = 1920,
    parameter COL_SIZE = 1080
)(
    input logic         i_clk,
    input logic         i_rst,

    input logic [7:0]   i_tdata,
    input logic         i_tvalid,
    input logic         i_tuser,
    input logic         i_tlast,
    output logic        i_trdy,
    output logic        o_interrupt
);

localparam LABEL_SIZE = $clog2(NUM_LABELS);

// internal signals

logic control_ccl_first_row, control_ccl_first_col;
logic control_fe_frame_done;
logic [23:0] control_fe_frame_count;
logic fe_control_dump_complete;
logic dec_fe_valid_coll, dec_fe_valid_label;
logic [LABEL_SIZE-1:0] dec_fe_trans_label, dec_fe_trans_max, dec_fe_trans_min;

logic [$clog2(ROW_SIZE)-1:0] control_fe_x_coord;
logic [$clog2(COL_SIZE)-1:0] control_fe_y_coord;

cca_control controller (
    .i_clk(i_clk),
    .i_rst(i_rst),
    .i_tuser(i_tuser),
    .i_tlast(i_tlast),
    .i_tvalid(i_tvalid),
    .o_frame_done(control_fe_frame_done),
    .o_frame_count(control_fe_frame_count),
    .o_first_row(control_ccl_first_row),
    .o_first_col(control_ccl_first_col),
    .o_x_coord(control_fe_x_coord),
    .o_y_coord(control_fe_y_coord),
    .i_dump_complete(fe_control_dump_complete),
    .o_interrupt(o_interrupt)
);

ccl_decision  #(
    .NUM_LABELS(NUM_LABELS),
    .ROW_SIZE(ROW_SIZE),
    .COL_SIZE(COL_SIZE)
) decision_top (
    .i_clk(i_clk),
    .i_rst(i_rst),
    .i_valid_pixel(i_tvalid),
    .i_data(i_tdata[0]),
    .i_first_row(control_ccl_first_row),
    .i_first_col(control_ccl_first_col),
    .i_frame_done(control_fe_frame_done),
    .o_valid_label(dec_fe_valid_label),
    .o_valid_coll(dec_fe_valid_coll),
    .o_trans_label(dec_fe_trans_label),
    .o_trans_min(dec_fe_trans_min),
    .o_trans_max(dec_fe_trans_max)
);

feature_extract #(
    .NUM_LABELS(NUM_LABELS),
    .WIDTH(ROW_SIZE),
    .HEIGHT(COL_SIZE)
) fe (
    .i_clk(i_clk),
    .i_rst(i_rst),
    
    .i_x_coord(control_fe_x_coord),
    .i_y_coord(control_fe_y_coord),

    .i_frame_done(control_fe_frame_done),
    .i_frame_count(control_fe_frame_count),

    .i_valid_coll(dec_fe_valid_coll),
    .i_valid_label(dec_fe_valid_label),
    .i_trans_label(dec_fe_trans_label),
    .i_trans_min(dec_fe_trans_min),
    .i_trans_max(dec_fe_trans_max),
    .o_dump_complete(fe_control_dump_complete)

    // BRAM signals can route up to the top level later
);

endmodule