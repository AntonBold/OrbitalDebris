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
    output logic        i_trdy
);

localparam LABEL_SIZE = $clog2(NUM_LABELS);

// internal signals

logic control_ccl_first_row, control_ccl_first_col;
logic dec_fe_valid_coll, dec_fe_valid_label;
logic [LABEL_SIZE-1:0] dec_fe_trans_label, dec_fe_trans_max, dec_fe_trans_min;


cca_control controller (
    .i_clk(i_clk),
    .i_rst(i_rst),
    .i_tuser(i_tuser),
    .i_tlast(i_tlast),
    .i_tvalid(i_tvalid),
    .o_first_row(control_ccl_first_row),
    .o_first_col(control_ccl_first_col)
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
    .o_valid_label(dec_fe_valid_label),
    .o_valid_coll(dec_fe_valid_coll),
    .o_trans_label(dec_fe_trans_label),
    .o_trans_min(dec_fe_trans_min),
    .o_trans_max(dec_fe_trans_max)
);

feature_extract #(
) fe (
    .i_clk(i_clk),
    .i_rst(i_rst),
    /* will need some control signals from control unit */
    .valid_coll(dec_fe_valid_coll),
    .valid_label(dec_fe_valid_label),
    .trans_label(dec_fe_trans_label),
    .trans_min(dec_fe_trans_min),
    .trans_max(dec_fe_trans_max)

    // will also need to assemble data out ??
);

endmodule