// Translator Lut - Spagnolo et al.
// indexed by a provisional label, stores the label as it
// currently translates

module translator_lut #(
        parameter DEPTH = 1024,
        localparam ADDR_SIZE = $clog2(DEPTH),
        localparam DATA_WIDTH = ADDR_SIZE
    )(
        input logic i_clk,
        input logic i_rst,

        // write port
        input logic [DATA_WIDTH-1:0] dind,
        input logic i_we,
        input logic [ADDR_SIZE-1:0] addrd,

        // read ports
        // a/b - decision time lookup of west and north neighbors
        input logic [ADDR_SIZE-1:0] addra,
        input logic [ADDR_SIZE-1:0] addrb,
        // e - resolve r2 before it is stored in the buffer
        input logic [ADDR_SIZE-1:0] addre,
        // f/g - second translation hop on a collision, for extract feature block
        input logic [ADDR_SIZE-1:0] addrf,
        input logic [ADDR_SIZE-1:0] addrg,

        output logic [DATA_WIDTH-1:0] doa,
        output logic [DATA_WIDTH-1:0] dob,
        output logic [DATA_WIDTH-1:0] doe,
        output logic [DATA_WIDTH-1:0] dof,
        output logic [DATA_WIDTH-1:0] dog
    );

    (* ram_style = "distributed" *)
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // reads - combinational, one array, five readers
    assign doa = mem[addra];
    assign dob = mem[addrb];
    assign doe = mem[addre];
    assign dof = mem[addrf];
    assign dog = mem[addrg];

    always_ff @(posedge i_clk) begin
        if (i_rst) begin

        end
        else if (i_we) begin
            mem[addrd] <= dind
        end
    end

endmodule