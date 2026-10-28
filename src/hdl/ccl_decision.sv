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
    input logic [$clog2(ROW_SIZE)-1:0] i_x_coord,
    input logic [$clog2(COL_SIZE)-1:0] i_y_coord,
    output logic [$clog2(ROW_SIZE)-1:0] o_x_coord,
    output logic [$clog2(COL_SIZE)-1:0] o_y_coord,
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

    // internal wiring signals
    logic lut_we;
    logic [LABEL_SIZE-1:0] lut_addrd;
    logic [LABEL_SIZE-1:0] lut_dind;
    logic [LABEL_SIZE-1:0] lut_doa;
    logic [LABEL_SIZE-1:0] lut_dob;
    logic [LABEL_SIZE-1:0] doe, dof, dog;
    logic [LABEL_SIZE-1:0] next_label;
    logic valid_label;
    logic valid_pixel; 

    assign valid_pixel = i_valid_pixel;
    assign read_en = valid_pixel && !i_first_row;

    // internal regs
    logic reg_input_pixel;
    logic [LABEL_SIZE-1:0] reg_label;
    logic [$clog2(ROW_SIZE)-1:0] reg_x_coord;
    logic [$clog2(COL_SIZE)-1:0] reg_y_coord;
    logic reg_first_row;
    logic reg_first_col;

    // reg_valid: the registered pixel is new this cycle. Decisions, TL
    // writes and feature updates happen once per pixel, not again on every
    // idle (tvalid low) cycle while the pixel sits in reg_input_pixel.
    logic reg_valid;
    logic decide_pixel;
    assign decide_pixel = reg_input_pixel && reg_valid;

    // TL update uses the second-lookup values: TL[max(DOF,DOG)] = min(DOF,DOG).
    // Writing TL[max(DOA,DOB)] instead can overwrite a label that already
    // points somewhere (DOA/DOB are only one hop from the stored labels) and
    // lose an equivalence the feature table has already merged.
    logic tl_we;
    logic [LABEL_SIZE-1:0] tl_addrd, tl_dind;
    assign tl_we    = lut_we && (dof != dog);
    assign tl_dind  = (dof < dog) ? dof : dog;
    assign tl_addrd = (dof < dog) ? dog : dof;

    // Paper Sec. 4.1: the line buffer stores the *translated* R2 label
    // (DOE), read after this cycle's TL update. The update isn't in the TL
    // array until the clock edge, so forward it.
    logic [LABEL_SIZE-1:0] r2_translated;
    assign r2_translated = (tl_we && tl_addrd == reg_label) ? tl_dind : doe;

    // One write per pixel, carrying the previous pixel's label. Skip it for
    // the first pixel of a frame: R2 then holds a label from the last frame.
    logic fifo_we;
    assign fifo_we = reg_valid && !(reg_first_row && reg_first_col);

    // Continuous assignments for module outputs
    // Second TL access for Extract Feature (paper: FT(TL(TL(Lj)))).
    // dof/dog are TL(DOA)/TL(DOB); if both resolve to the same label the
    // pixel joins an already-merged object, so it's not a collision for FE.
    assign o_valid_coll = tl_we;
    assign o_trans_min = tl_dind;
    assign o_trans_max = tl_addrd;
    assign o_trans_label = (next_label == lut_doa) ? dof :
                           (next_label == lut_dob) ? dog : next_label;
    assign o_valid_label = valid_label;
    assign o_x_coord = reg_x_coord;
    assign o_y_coord = reg_y_coord;

    // internal modules
    translator_lut #(
        .DEPTH(NUM_LABELS)
    ) tl (
        .i_clk(i_clk),
        .i_rst(i_rst | i_frame_done),

        .dind(tl_dind),
        .i_we(tl_we),
        .addrd(tl_addrd),

        .addra(fifo_out_data),
        .addrb(reg_label),
        .addre(reg_label),
        .addrf(lut_doa),
        .addrg(lut_dob),

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
        // Cleared each frame like the TL, otherwise row 1 of the next frame
        // reads the previous frame's last row as its north neighbors
        .i_rst(i_rst | i_frame_done),
        .i_data_valid(fifo_we),
        .i_rd_data(read_en),
        .i_data(r2_translated),
        .o_data(fifo_out_data),
        .o_full(fifo_full),
        .o_empty(fifo_empty)
    );

    label_decision_logic #(
        .NUM_LABELS(NUM_LABELS)
    ) decision_block (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_frame_done(i_frame_done),
        .i_pixel_data(decide_pixel),
        .first_row(reg_first_row),
        .first_col(reg_first_col),
        .i_trans_label_n(lut_doa),
        .i_trans_label_w(lut_dob),
        .o_labeled_pixel(next_label),
        .valid_label(valid_label),
        .o_lut_we(lut_we),
        .o_lut_addrd(lut_addrd),
        .o_lut_dind(lut_dind)  
    );

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            reg_valid <= 1'b0;
            reg_label <= '0;
        end else begin
            reg_valid <= i_valid_pixel;
            // The label decided this cycle is the west neighbour of the next
            // pixel. Capture it while the decision is valid, not when the
            // next pixel arrives (by then an idle gap would have zeroed it).
            if (reg_valid) begin
                reg_label <= next_label;
            end
        end
    end

    always_ff @(posedge i_clk) begin
        if(i_rst) begin
            reg_input_pixel <= 1'b0;
            reg_x_coord <= '0;
            reg_y_coord <= '0;
            reg_first_row <= 1'b0;
            reg_first_col <= 1'b0;
        end
        else if (i_valid_pixel) begin
            reg_input_pixel <= i_data;
            // Coordinates and row/col flags travel with the pixel so they
            // line up with it in the decision logic and at the output
            // (same register, same enable).
            reg_x_coord <= i_x_coord;
            reg_y_coord <= i_y_coord;
            reg_first_row <= i_first_row;
            reg_first_col <= i_first_col;
        end
    end

endmodule