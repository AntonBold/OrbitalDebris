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

// feature tables (32 bits wide)
logic [31:0] area_ram [0:NUM_LABELS-1];
logic [31:0] sum_x_ram [0:NUM_LABELS-1];
logic [31:0] sum_y_ram [0:NUM_LABELS-1];

// zeros table
logic zeros_ram [0:NUM_LABELS-1];

logic [LABEL_SIZE-1:0] addra, addrb;
logic we_a_ft, we_b_zt;

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
logic [31:0] read_area_a, read_x_a, read_y_a;
assign read_area_a  = area_ram[addra] & {32{zeros_ram[addra]}};
assign read_x_a     = sum_x_ram[addra] & {32{zeros_ram[addra]}};
assign read_y_a     = sum_y_ram[addra] & {32{zeros_ram[addra]}};

// read port b
logic [31:0] read_area_b, read_x_b, read_y_b;
assign read_area_b  = area_ram[addrb] & {32{zeros_ram[addrb]}};
assign read_x_b     = sum_x_ram[addrb] & {32{zeros_ram[addrb]}};
assign read_y_b     = sum_y_ram[addrb] & {32{zeros_ram[addrb]}};


// accumulator signals and math
logic [31:0] new_area, new_x, new_y;

always_comb begin
    if (i_valid_coll) begin
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

endmodule