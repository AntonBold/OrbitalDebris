module line_buffer  #(
    parameter DATA_WIDTH    = 8,
    parameter DEPTH         = 1920
)(
    input logic i_clk,
    input logic i_rst, // assuming active high
    input logic i_data_valid,
    input logic i_rd_data,
    input logic [DATA_WIDTH-1:0] i_data,

    output logic [(DATA_WIDTH * 2)-1:0] o_data, // *2 because want to read N and NE pixel at once
    output logic full,
    output logic empty
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    // mem array
    logic [DATA_WIDTH-1:0] buffer [0:DEPTH-1];

    // rd and wr pointers - 1 bit extra for full and empty checking
    logic [ADDR_WIDTH:0] wr_ptr, rd_ptr;

    // synchronous buffer write and read to infer bram

    // buffer writing
    always_ff @(posedge i_clk) begin
        if(i_rst) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end
        else if (i_data_valid && !full) begin
            buffer[wr_ptr[ADDR_WIDTH-1:0]] <= i_data;
            wr_ptr <= wr_ptr + 1'b1;
        end
        else if (i_rd_data && !empty) begin
            // n pixel msB, ne pixel lsB
            o_data <= {buffer[rd_ptr[ADDR_WIDTH-1:0]], buffer[rd_ptr[ADDR_WIDTH-1:0] + 1]};
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

    assign full = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
                  (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
    assign empty = (wr_ptr == rd_ptr);
endmodule