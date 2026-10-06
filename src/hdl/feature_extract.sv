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
    input logic [23:0] i_frame_count,

    // AXI Bram interface (PS side)
    output logic [31:0] o_bram_addr,
    output logic [31:0] o_bram_wdata,
    output logic [3:0] o_bram_we,
    output logic o_bram_en,

    output logic o_dump_complete
);

// initialize RAMs for simulation by declaring initial values
logic [31:0] area_ram [0:NUM_LABELS-1] = '{default: '0};
logic [31:0] sum_x_ram [0:NUM_LABELS-1] = '{default: '0};
logic [19:0] sum_y_ram [0:NUM_LABELS-1] = '{default: '0};

// zeros table defaults to 1 (unmerged)
logic zeros_ram [0:NUM_LABELS-1] = '{default: 1'b1};

logic [LABEL_SIZE-1:0] addra, addrb;
logic we_a_ft, we_b_zt;



// state machine signals

logic [LABEL_SIZE:0] read_ptr;
logic [7:0] valid_centroid_count;
logic [1:0] frame_slot;
logic [31:0] frame_base_addr;
logic [31:0] word_offset;


typedef enum logic[2:0] {
    S_accum         = 3'd0,
    S_dump_addr     = 3'd1,
    S_dump_read     = 3'd2,
    S_dump_w1       = 3'd3,
    S_dump_w2       = 3'd4,
    S_dump_head     = 3'd5,
    S_done          = 3'd6
} state_t;

state_t state, next_state;

logic dump_clear_we;
assign we_a_ft = i_valid_label || dump_clear_we;
assign we_b_zt = i_valid_coll;

// inputs to fe table
always_comb begin
    if (state != S_accum) begin
        addra = read_ptr;
        addrb = '0;
    end 
    else if (i_valid_coll) begin
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
        new_area    = '0;
        new_x       = '0;
        new_y       = '0;
        if (state != S_accum) begin
            new_area    = '0;
            new_x       = '0;
            new_y       = '0;
        end
        else if (i_valid_coll) begin
            new_area    = read_area_a + read_area_b + 1'b1;
            new_x       = read_x_a + read_x_b + i_x_coord;
            new_y       = read_y_a + read_y_b + i_y_coord;
        end
        else if (i_valid_label) begin
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

// state machine

always_ff @(posedge i_clk) begin
    if (i_rst) begin
        state <= S_accum;
        read_ptr <= 1;
        valid_centroid_count <= '0;
        frame_slot <= 0;
    end else begin
        state <= next_state;

        // counter logic
        if (dump_clear_we) begin
            read_ptr <= read_ptr + 1'b1;
        end
        // reset
        if (state == S_done) begin
            read_ptr <= 1;
            valid_centroid_count <= '0;
            if (frame_slot == 2'd2)
                frame_slot <= '0;
            else
                frame_slot <= frame_slot + 1'b1;
        end

        if (state == S_dump_w2) begin
            valid_centroid_count <= valid_centroid_count + 1'b1;
        end
    end
end

always_comb begin
    next_state  = state;
    o_bram_we   = 4'b0000;
    o_bram_en   = 1'b0;
    o_dump_complete = 1'b0;
    dump_clear_we = 1'b0;

    case(state) 
        S_accum: begin
            if (i_frame_done) begin
                next_state = S_dump_addr;
            end
        end
        S_dump_addr: begin
            if(read_ptr == NUM_LABELS) begin
                next_state = S_dump_head;
            end
            else begin
                next_state = S_dump_read;
            end
        end
        S_dump_read: begin
            if (read_area_a > 0) begin
                next_state = S_dump_w1;
            end
            else begin
                next_state = S_dump_addr;
                dump_clear_we = 1'b1;
            end
        end
        S_dump_w1: begin
            o_bram_en = 1'b1;
            o_bram_we = 4'b1111;
            o_bram_addr = frame_base_addr + word_offset;
            o_bram_wdata = read_x_a;
            next_state = S_dump_w2;
        end
        S_dump_w2: begin
            o_bram_en = 1'b1;
            o_bram_we = 4'b1111;
            o_bram_addr = frame_base_addr + word_offset;
            // Pack: 4 bits padding, 15 bits Y_sum, 12 bits Area, 1 bit Valid
            o_bram_wdata = {4'b0, read_y_a[14:0], read_area_a[11:0], 1'b1};
            next_state = S_dump_addr;
            dump_clear_we = 1'b1;
        end
        S_dump_head: begin
            o_bram_en = 1'b1;
            o_bram_we = 4'b1111;
            o_bram_addr = frame_base_addr;
            o_bram_wdata = {i_frame_count, valid_centroid_count};
            next_state = S_done;
        end
        S_done: begin
            o_bram_en = 1'b0;
            o_bram_we = 4'b0;
            next_state = S_accum;
            o_dump_complete = 1'b1;
        end
        default: begin
            next_state  = S_accum;
            o_bram_we   = 4'b0000;
            o_bram_en   = 1'b0;
            o_dump_complete = 1'b0;
        end
    endcase
end


// bram address handling

always_comb begin
    case (frame_slot)
        2'd0: frame_base_addr = 32'h0000_0000;
        2'd1: frame_base_addr = 32'h0000_0804;
        2'd2: frame_base_addr = 32'h0000_1008;
        default: frame_base_addr = 32'h0000_0000;
    endcase
end

always_ff @(posedge i_clk) begin
    if(state == S_accum) begin
        word_offset <= 32'd4;
    end else if (state == S_dump_w1 || state == S_dump_w2) begin
        word_offset <= word_offset + 32'd4;
    end
end

endmodule