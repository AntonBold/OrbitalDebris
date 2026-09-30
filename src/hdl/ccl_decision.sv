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
    output logic [$clog2(NUM_LABELS)-1:0] o_trans_label,
    output logic [$clog2(NUM_LABELS)-1:0] o_trans_min,
    output logic [$clog2(NUM_LABELS)-1:0] o_trans_max
);

    localparam FIFO_DEPTH = ROW_SIZE - 1;
    localparam LABEL_SIZE = $clog2(NUM_LABELS);

    // internal signals
    logic read_en;
    logic [LABEL_SIZE-1:0] fifo_out_data;
    logic fifo_full;
    logic fifo_empty;

    // missing internal wiring signals
    logic lut_we;
    logic [LABEL_SIZE-1:0] lut_addrd;
    logic [LABEL_SIZE-1:0] lut_dind;
    logic [LABEL_SIZE-1:0] lut_doa;
    logic [LABEL_SIZE-1:0] lut_dob;
    logic [LABEL_SIZE-1:0] doe, dof, dog;
    logic [LABEL_SIZE-1:0] next_label;
    logic valid_label;
    logic valid_pixel; // Added missing valid_pixel for FIFO

    assign valid_pixel = i_valid_pixel;
    assign read_en = valid_pixel && !i_first_row; // THE MISSING LINK!

    // internal regs
    logic reg_input_pixel;
    logic [LABEL_SIZE-1:0] reg_label;

    // Continuous assignments for module outputs
    assign o_valid_coll = lut_we;
    assign o_trans_min = lut_dind;
    assign o_trans_max = lut_addrd;
    assign o_trans_label = next_label;
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
        .addre('0),
        .addrf('0),
        .addrg('0),

        .doa(lut_doa),
        .dob(lut_dob),
        .doe(doe),
        .dof(dof),
        .dog(dog)
    );

    fifo #(
        .DATA_WIDTH(LABEL_SIZE),
        .DEPTH(FIFO_DEPTH)
    ) north_label_buffer (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_data_valid(valid_pixel),
        .i_rd_data(read_en),
        .i_data(next_label),
        .o_data(fifo_out_data),
        .o_full(fifo_full),
        .o_empty(fifo_empty)
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

    always_ff @(posedge i_clk) begin
        if(i_rst) begin
            reg_input_pixel <= 1'b0;
            reg_label <= '0;
        end
        else if (i_valid_pixel) begin
            reg_input_pixel <= i_data;
            // The labeling assignment output by decision_logic (next_label) 
            // becomes the reg_label for the NEXT pixel!
            reg_label <= next_label;
        end
    end

endmodule