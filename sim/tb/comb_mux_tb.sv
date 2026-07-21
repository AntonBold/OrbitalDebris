`timescale 1ns/10ps

module comb_mux_tb();

    // inputs
    logic [3:0] a, b;
    logic sel;
    // outputs
    logic [3:0] data;
    // tb info
    int errors;
    
    comb_mux mux(
        .a(a),
        .b(b),
        .sel(sel),
        .data(data)
    );

    initial begin
        $display();
        $display("Starting");
        $display();
        $dumpfile("dump.vcd");
        $dumpvars();

        initialize();

        a = 4'd7; // sel = 0
        b = 4'd2; // sel = 1

        #5

        assert (data == 4'd7) else begin
            errors = errors + 1;
            $display("ERROR: Data did not start out at a's value");
        end

        sel = 1'b1; // should select b

        #5
        
        assert (data == 4'd2) else begin
            errors = errors + 1;
            $display("ERROR: Data did not match b input when select was for b");
        end

        #5

        sel = 1'b0;

        #5
        assert (data == 4'd7) else begin
            errors = errors + 1;
            $display("ERROR: Data did not match a input when select was for a");
        end

        #5
        a = 4'd4;
        #5

        assert (data == 4'd4) else begin
            errors = errors + 1;
            $display("ERROR: Data did not match b input when select was for b");
        end
        
        $display("Finished...");
        if(errors == 0) begin
            $display("SUCCESS 0 errors yay");
        end else begin
            $display("FAIL some errors");
        end
        $display();

        $finish;
    end

    function void initialize();
        sel = 0;
    endfunction : initialize


endmodule