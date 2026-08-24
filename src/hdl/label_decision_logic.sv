module label_decision_logic #(
    parameter NUM_LABELS = 1024
)(
    input logic i_clk,
    input logic i_rst,
    input logic i_pixel_data,
    input logic first_row,
    input logic first_col,
    input logic [LABEL_SIZE-1:0] i_prev_label,
    input logic [LABEL_SIZE-1:0] i_above_label,
    output logic [LABEL_SIZE-1:0] o_labeled_pixel,
    output logic valid_label,
    output logic valid_collision
);

localparam LABEL_SIZE = $clog2(NUM_LABELS);

logic [LABEL_SIZE-1:0] new_label;
logic [LABEL_SIZE-1:0] lx;
logic [LABEL_SIZE-1:0] ly;

always_ff @(posedge i_clk)
begin
    if (i_rst == 1'b1)
        lx <= '0;
    else if (first_row == 1'b1)
        lx <= '0;
    else
        lx <= i_prev_label;
end

always_ff @(posedge i_clk)
begin
    if (i_rst == 1'b1)
        ly <= '0;
    else if (first_col == 1'b1)
        ly <= '0;
    else
        ly <= i_above_label;
end

always_ff @(posedge i_clk)
begin
    if (i_rst == 1'b1)

    else if (i_above_label=='0) &&(i_prev_label == '0)
    begin
        o_labeled_pixel <= new_label;
        new_label <= new_label + 1'b1;
    end
    else if (i_prev_label != '0) && (i_above_label == '0)
    begin
        o_labeled_pixel <= lx;
    end
    else if (i_above_label != '0) && (i_prev_label == '0)
    begin
        o_labeled_pixel <= ly;
    end
    else
        if (lx == ly)
            o_labeled_pixel <= lx;
        else
            o_labeled_pixel <= (lx<ly) ? lx : ly;
end

function logic [LABEL_SIZE-1:0] min(
    input logic [LABEL_SIZE-1:0] lx,
    input logic [LABEL_SIZE-1:0] ly
);
    if (lx < ly)
        return lx;
    else
        return ly;

endfunction

endmodule