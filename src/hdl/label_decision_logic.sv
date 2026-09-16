module label_decision_logic #(
    parameter NUM_LABELS = 1024
)(
    input logic i_clk,
    input logic i_rst,
    input logic i_pixel_data,
    input logic first_row,
    input logic first_col,
    input logic [LABEL_SIZE-1:0] i_trans_label_n,
    input logic [LABEL_SIZE-1:0] i_trans_label_w,
    output logic [LABEL_SIZE-1:0] o_labeled_pixel,
    output logic valid_label,
    output logic o_lut_we,
    output logic [LABEL_SIZE-1:0] o_lut_addrd,
    output logic [LABEL_SIZE-1:0] o_lut_dind
);

    localparam LABEL_SIZE = $clog2(NUM_LABELS);

    logic[LABEL_SIZE-1:0] new_label;
    logic inc_new_label;

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            new_label <=1;
        end else if (inc_new_label) begin
            new_label <= new_label+1'b1;
        end
    end

    always_comb begin
        o_lut_we = 1'b0;
        o_lut_addrd = '0;
        o_lut_dind = '0;
        inc_new_label = 1'b0;
        o_labeled_pixel = '0; 
        valid_label = i_pixel_data; // Let downstream know if this is a real object

        // label assignment logic
        casex ({i_pixel_data, i_trans_label_n != 0, i_trans_label_w != 0})
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
        if ((i_trans_label_n != 0) && (i_trans_label_w != 0) && (i_trans_label_n != i_trans_label_w)) begin
            o_lut_we = 1'b1;
            o_lut_addrd = (i_trans_label_n > i_trans_label_w) ? i_trans_label_n : i_trans_label_w; // MAX
            o_lut_dind  = (i_trans_label_n < i_trans_label_w) ? i_trans_label_n : i_trans_label_w; // MIN
        end
    end

endmodule