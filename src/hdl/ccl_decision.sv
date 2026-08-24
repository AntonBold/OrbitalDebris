module ccl_decision #(
    parameter NUM_LABELS = 1024,
    parameter ROW_SIZE = 1920,
    parameter COL_SIZE  = 1080
    )(
    input logic i_clk,
    input logic i_rst,
    input logic i_valid_pixel,
    input logic [LABEL_SIZE-1:0] i_data,
    output logic valid_label,
    output logic valid_cell,
    output logic [LABEL_SIZE-1:0] trans_label,
    output logic [LABEL_SIZE-1:0] trans_min,
    output logic [LABEL_SIZE-1:0] trans_max
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

    // internal modules
    translator_lut #(
        .DEPTH(NUM_LABELS)
    ) tl (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .addra(addra),
        .addrb(addrb),
        .addrd(addrd),
        .addre(addre),
        .addrf(addrf),
        .addrg(addrg),
        .dind(dind),
        .doa(doa),
        .dob(dob),
        .doe(doe),
        .dof(dof),
        .dog(dog)
    );

    fifo #(
        .DATA_DEPTH(LABEL_SIZE),
        .DEPTH(FIFO_DEPTH)
        ) lb (
            .i_clk(i_clk),
            .i_rst(i_rst),
            .i_data_valid(valid_pixel),
            .i_rd_data(read_en),
            .i_data(),
            .o_data(fifo_out_data),
            .full(fifo_full),
            .empty(fifo_empty),
        );

    always_ff @(posedge clk) begin
        if(i_rst) begin
            // reset something
        end
        else if (i_valid_pixel) begin
            reg_input_pixel <= i_data[0];
            reg_label <= next_label;
        end



    end

endmodule