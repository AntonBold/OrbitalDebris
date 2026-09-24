module cca_control #(
    parameter WIDTH = 1920,
    parameter HEIGHT = 1080
)(
    input logic i_clk,
    input logic i_rst,
    
    input logic i_tuser,
    input logic i_tlast,
    input logic i_tvalid,
    
    // Additional outputs for BRAM logic
    output logic o_frame_done,
    output logic [23:0] o_frame_count,

    output logic o_first_row,
    output logic o_first_col,
    output logic [$clog2(WIDTH)-1:0] o_x_coord,
    output logic [$clog2(HEIGHT)-1:0] o_y_coord;
    
    input  logic i_dump_complete,
    output logic o_interrupt
);


logic reg_was_prev_pixel_last;
logic reg_is_first_row;

typedef enum logic {
    S_firstrow      = 1'b0,
    S_notfirstrow   = 1'b1n
} state_t;

state_t state, next_state;


logic [23:0] frame_count;

always_ff @(posedge i_clk) begin
    if(i_rst)
    begin
        reg_was_prev_pixel_last <= 1'b0;
        frame_count <= '0;
        o_frame_done <= 1'b0;
    end
    else if (i_tvalid) begin
        reg_was_prev_pixel_last <= i_tlast;
        
        // Frame counting logic (increments on first pixel)
        if (i_tuser) begin
            if (frame_count != 24'hFFFFFF) begin
                frame_count <= frame_count + 1'b1;
            end
        end
        
        // Very simple V-blank detection: tlast goes high in S_notfirstrow.
        // (You might want to tie this to a specific row counter later if your tlast is per-line!)
    end
end

always_ff @(posedge i_clk) begin
    if (i_rst) begin
        o_interrupt <= 1'b0;
    end else begin
        // i_dump_complete is a 1-cycle pulse from feature_extract
        o_interrupt <= i_dump_complete;
    end
end

assign o_frame_count = frame_count;

always_ff @(posedge i_clk) begin
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

assign o_first_row = i_tuser | reg_is_first_row;
assign o_first_col = i_tuser | reg_was_prev_pixel_last;

logic [$clog2(WIDTH)-1:0] row_counter;
logic [$clog2(HEIGHT)-1:0] col_counter;

always_ff @(posedge i_clk) begin
    if (i_rst) begin
        row_counter <= '0;
        col_counter <= '0;
        o_frame_done <= 1'b0;
    end
    else begin
        o_frame_done <= 1'b0;
        if (i_tvalid) begin

            if (i_tuser) begin
                // start of  anew frame -- reset row and col counter
                row_counter <= '0;
                col_counter <= '0;
            end
            else if (i_tlast) begin
                row_counter <= '0;
                if (col_counter == HEIGHT - 1) begin
                    o_frame_done <= 1'b1;
                    col_counter <= '0;
                end else begin
                    col_counter <= col_counter + 1'b1;
                end
            end else begin
                row_counter <= row_counter + 1'b1;
            end
        end
    end
end

assign o_x_coord = row_counter;
assign o_y_coord = col_counter;

endmodule