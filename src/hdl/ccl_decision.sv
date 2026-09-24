module ccl_decision #(
    parameter NUM_LABELS = 1024,
    parameter ROW_SIZE = 1920,
    parameter COL_SIZE  = 1080
    )(
    input logic i_clk,
    input logic i_rst,
    input logic i_valid_pixel,
    input logic i_data,
    input logic i_first_row,
    input logic i_first_col,
    input logic i_frame_done,
    output logic o_valid_label,
    output logic o_valid_coll,
    output logic [LABEL_SIZE-1:0] o_trans_label,
    output logic [LABEL_SIZE-1:0] o_trans_min,
    output logic [LABEL_SIZE-1:0] o_trans_max
);

    localparam FIFO_DEPTH = ROW_SIZE - 1;
    localparam LABEL_SIZE = $clog2(NUM_LABELS);

    // internal signals
    logic read_en;
    logic [LABEL_SIZE-1:0] fifo_out_data;
    logic fifo_full;
    logic fifo_empty;

    // internal regs

    logic reg_input_pixel;
    logic [LABEL_SIZE-1:0] reg_label;


    assign o_valid_coll = lut_we;
    assign o_trans_label = next_label;
    assign o_trans_min = lut_dind;
    assign o_trans_max = lut_addrd;
    assign o_valid_label = valid_label;

    // internal modules
    translator_lut #(
        .DEPTH(NUM_LABELS)
    ) tl (
        .i_clk(i_clk),
        .i_rst(i_rst | i_frame_done),

        .dind(lut_dind),
        .i_we(lut_we),
        .addrd(lut_addrd),

        .addra(fifo_out_data),
        .addrb(reg_label),
        .addre(addre),
        .addrf(addrf),
        .addrg(addrg),

        .doa(lut_doa),
        .dob(lut_dob),
        .doe(doe),
        .dof(dof),
        .dog(dog)
    );

    fifo #(
        .DATA_DEPTH(LABEL_SIZE),
        .DEPTH(FIFO_DEPTH)
    ) north_label_buffer (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_data_valid(valid_pixel),
        .i_rd_data(read_en),
        .i_data(next_label),
        .o_data(fifo_out_data),
        .full(fifo_full),
        .empty(fifo_empty),
        );

    label_decision_logic #(
        .NUM_LABELS(NUM_LABELS)
    ) decision_block (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_pixel_data(reg_input_pixel),
        .first_row(i_first_row),
        .first_col(i_first_col),
        .i_trans_label_n(lut_doa),
        .i_trans_label_w(lut_dob),
        .o_labeled_pixel(next_label),
        .valid_label(valid_label),
        .o_lut_we(lut_we),
        .o_lut_addrd(lut_addrd),
        .o_lut_dind(lut_dind)  
    );

    always_ff @(posedge clk) begin
        if(i_rst) begin
            // reset something
        end
        else if (i_valid_pixel) begin
            reg_input_pixel <= i_data;
            reg_label <= next_label;
        end



    end

endmodule