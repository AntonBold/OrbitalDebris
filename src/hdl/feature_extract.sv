module feature_extract #(
    parameter NUM_LABELS=1024,
    parameter WIDTH=1920,
    parameter HEIGHT=1080,
    parameter LABEL_SIZE = $clog2(NUM_LABELS)
)(
    input logic i_clk,
    input logic i_rst,
    input logic [$clog2(WIDTH)-1:0] i_x_coord,
    input logic [$clog2(HEIGHT)-1:0] i_y_coord,
    input logic i_valid_coll,
    input logic i_valid_label,
    input logic [LABEL_SIZE-1:0] i_trans_label,
    input logic [LABEL_SIZE-1:0] i_trans_min,
    input logic [LABEL_SIZE-1:0] i_trans_max,

    // control signal from CCA control
    input logic i_frame_done,

    // AXI Bram interface (PS side)
    output logic [31:0] o_bram_addr,
    output logic [31:0] o_bram_wdata,
    output logic [3:0] o_bram_we,
    output logic o_bram_en,

    output logic o_dump_complete
);

// feature tables (32 bits wide except for y)
logic [31:0] area_ram [0:NUM_LABELS-1];
logic [31:0] sum_x_ram [0:NUM_LABELS-1];
logic [19:0] sum_y_ram [0:NUM_LABELS-1];

// zeros table
logic zeros_ram [0:NUM_LABELS-1];

logic [LABEL_SIZE-1:0] addra, addrb;
logic we_a_ft, we_b_zt;

typedef enum logic[3:0] {
    S_accum         = 3'd0,
    S_dump_read     = 3'd1,
    S_dump_w1       = 3'd2,
    S_dump_w2       = 3'd3,
    S_dump_head     = 3'd4,
    S_done          = 3'd5
} state_t;

state_t state, next_state;

assign we_a_ft = i_valid_label;
assign we_b_zt = i_valid_coll;

// inputs to fe table
always_comb begin
    if (i_valid_coll) begin
        addra = i_trans_min;
        addrb = i_trans_max;
    end else begin
        addra = i_trans_label;
        addrb = '0;
    end
end

// read port A
logic [31:0] read_area_a, read_x_a;
logic [19:0] read_y_a;
assign read_area_a  = area_ram[addra] & {32{zeros_ram[addra]}};
assign read_x_a     = sum_x_ram[addra] & {32{zeros_ram[addra]}};
assign read_y_a     = sum_y_ram[addra] & {20{zeros_ram[addra]}};

// read port b
logic [31:0] read_area_b, read_x_b;
logic [19:0] read_y_b;
assign read_area_b  = area_ram[addrb] & {32{zeros_ram[addrb]}};
assign read_x_b     = sum_x_ram[addrb] & {32{zeros_ram[addrb]}};
assign read_y_b     = sum_y_ram[addrb] & {20{zeros_ram[addrb]}};


// accumulator signals and math
logic [31:0] new_area, new_x;
logic [19:0] new_y;

always_comb begin
    if (state != S_accum) begin
        addra = read_ptr;
        addrb = '0;
    end 
    else if (i_valid_coll) begin
        new_area    = read_area_a + read_area_b + 1'b1;
        new_x       = read_x_a + read_x_b + i_x_coord;
        new_y       = read_y_a + read_y_b + i_y_coord;
    end
    else begin
        new_area    = read_area_a + 1'b1;
        new_x       = read_x_a + i_x_coord;
        new_y       = read_y_a + i_y_coord;

    end
end


// writing
always_ff @(posedge i_clk) begin
    if (i_rst) begin

    end else begin
        if (we_a_ft) begin
            area_ram[addra]     <= new_area;
            sum_x_ram[addra]    <= new_x;
            sum_y_ram[addra]    <= new_y;
            zeros_ram[addra]    <= 1'b1;
        end
        if (we_b_zt) begin
            zeros_ram[addrb]    <= 1'b0;
        end
    end
end





// state machine stuff

logic [LABEL_SIZE-1:0] read_ptr;
logic [7:0] valid_centroid_count;
logic [1:0] frame_slot;
logic [31:0] bram_base_addr;
logic [31:0] current_bram_addr;

always_ff @(posedge clk) begin
    if (i_rst) begin
        state <= S_accum;
        read_ptr <= 1;
        valid_centroid_count <= '0;
        frame_slot <= 0;
    end else begin
        state <= next_state;
    end
end

always_comb begin
    next_state  = state;
    o_bram_we   = 4'b0000;
    o_bram_en   = 1'b0;
    o_dump_complete = 1'b0;

    case(state) 
        S_accum: begin
            if (i_frame_done) begin
                next_state = S_dump_read;
            end
        end
        S_dump_read: begin
            if(read_ptr == NUM_LABELS) begin
                next_state = S_dump_head;
            end
            else if (read_area_a > 0) begin
                next_state = S_dump_w1;
            end
            else begin
                next_state = S_dump_read;
            end
        end
        S_dump_w1: begin
            o_bram_en = 1'b1;
            o_bram_we = 4'b1111;
            o_bram_addr = current_bram_addr;
            o_bram_wdata = read_x_a;
            next_state = S_dump_w2;
        end
        S_dump_w2: begin
            o_bram_en = 1'b1;
            o_bram_we = 4'b1111;
            o_bram_addr = current_bram_addr;
            o_bram_wdata = {4'b0, read_y_a, read_area_a, 1'b1};
            next_state = S_dump_read;
        end
        S_dump_head: begin


        end
        S_done: begin

        end
        default: begin

        end
    endcase
end

endmodule