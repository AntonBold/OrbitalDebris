// Test mux for simulate.sh and makefile

module comb_mux(
    input logic sel,
    input [3:0] a, b,
    output [3:0] data
);

    always_comb begin : comb_mux
        if(sel) begin
            data = b;
        end else if (~sel) begin
            data = a;
        end else begin
            data = 'x;
        end
    end
endmodule