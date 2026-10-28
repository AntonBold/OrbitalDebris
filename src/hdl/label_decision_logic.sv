module label_decision_logic #(
    parameter NUM_LABELS = 1024
)(
    input logic i_clk,
    input logic i_rst,
    input logic i_frame_done,
    input logic i_pixel_data,
    input logic first_row,
    input logic first_col,
    input logic [$clog2(NUM_LABELS)-1:0] i_trans_label_n,
    input logic [$clog2(NUM_LABELS)-1:0] i_trans_label_w,
    output logic [$clog2(NUM_LABELS)-1:0] o_labeled_pixel,
    output logic valid_label,
    output logic o_lut_we,
    output logic [$clog2(NUM_LABELS)-1:0] o_lut_addrd,
    output logic [$clog2(NUM_LABELS)-1:0] o_lut_dind
);

    localparam LABEL_SIZE = $clog2(NUM_LABELS);

    logic[LABEL_SIZE-1:0] new_label;
    logic inc_new_label;

    always_ff @(posedge i_clk) begin
        // Restart labels each frame: the TL and feature tables are cleared
        // per frame, and a free-running counter would eventually wrap to 0
        // (the background label).
        if (i_rst || i_frame_done) begin
            new_label <=1;
        end else if (inc_new_label) begin
            new_label <= new_label+1'b1;
        end
    end

    // label assignment logic
    logic valid_w, valid_n;
    // Ignore the West pixel if we are on the first column of a new row!
    assign valid_w = (first_col) ? 1'b0 : (i_trans_label_w != 0);
    // Same for North on the first row of a frame (paper Fig. 6: i = 0 -> Lx = 0);
    // the line buffer output there still holds the previous frame's last read
    assign valid_n = (first_row) ? 1'b0 : (i_trans_label_n != 0);

    always_comb begin
        o_lut_we = 1'b0;
        o_lut_addrd = '0;
        o_lut_dind = '0;
        inc_new_label = 1'b0;
        o_labeled_pixel = '0; 
        valid_label = i_pixel_data; // Let downstream know if this is a real object

        casex ({i_pixel_data, valid_n, valid_w})
            3'b0XX: o_labeled_pixel = '0;
            3'b100: begin // incoming pixel is foreground, and nw pixels are background
                o_labeled_pixel = new_label;
                inc_new_label = 1'b1;
            end
            3'b110: o_labeled_pixel = i_trans_label_n;
            3'b101: o_labeled_pixel = i_trans_label_w;
            3'b111: o_labeled_pixel = (i_trans_label_n < i_trans_label_w) ? i_trans_label_n : i_trans_label_w; // MIN
            default: o_labeled_pixel = '0;
        endcase 

        // collision condition
        if (i_pixel_data && valid_n && valid_w && (i_trans_label_n != i_trans_label_w)) begin
            o_lut_we = 1'b1;
            o_lut_addrd = (i_trans_label_n > i_trans_label_w) ? i_trans_label_n : i_trans_label_w; // MAX
            o_lut_dind  = (i_trans_label_n < i_trans_label_w) ? i_trans_label_n : i_trans_label_w; // MIN
        end
    end

endmodule