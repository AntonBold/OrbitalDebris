module cca_control #()(
    input logic i_clk,
    input logic i_rst,
    
    input logic i_tuser,
    input logic i_tlast,
    input logic i_tvalid,

    output logic o_first_row,
    output logic o_first_col
);


logic reg_was_prev_pixel_last;
logic reg_is_first_row;

typedef enum logic {
    S_firstrow      = 1'b0,
    S_notfirstrow   = 1'b1n
} state_t;

state_t state, next_state;


always_ff @(posedge clk) begin
    if(i_rst)
    begin
        reg_was_prev_pixel_last <= 1'b0;
    end
    else if (i_tvalid) begin
        reg_was_prev_pixel_last <= i_tlast;
    end
end

always_ff @(posedge clk) begin
    if(i_rst) begin
        state <= S_firstrow;
    end
    else begin
        state <= next_state;
    end
end

always_comb begin
    case (state)
        S_firstrow:
            reg_is_first_row = 1'b1;
        S_notfirstrow:
            reg_is_first_row = 1'b0;
    endcase
end

always_comb begin
    next_state = state;
    if (i_tvalid) begin
        if (i_tuser == 1) begin
            next_state = S_firstrow;
        end
        else if (i_tlast == 1) begin
            next_state = S_notfirstrow;
        end
    end
end

assign o_first_row = i_tuser | first_row;
assign o_first_col = i_tuser | reg_was_prev_pixel_last;