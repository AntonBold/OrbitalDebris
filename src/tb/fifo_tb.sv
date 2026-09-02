`timescale 1ns/10ps

module fifo_tb();

    localparam LINE_DEPTH = 1919;
    localparam SIZE_LD = $clog2(LINE_DEPTH);

    // system
    logic clk, rst;
    int errors;

    // inputs
    logic data_valid, read_en;
    logic [7:0] data;

    // outputs
    logic full, empty;
    logic [7:0] out_data; // 2 bytes because of reading 2 at once


    // test bench internals
    logic [7:0] n_data;
    logic [7:0] wr_data;
    logic[7:0] expected;

    fifo #(
        .DEPTH(LINE_DEPTH)
    ) uut (
        .i_clk(clk),
        .i_rst(rst),
        .i_data_valid(data_valid),
        .i_rd_data(read_en),
        .i_data(data),
        .o_data(out_data),
        .full(full),
        .empty(empty)
    );

    // clk gen
    always #5 clk = ~clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars();
        $display();
        $display("Starting");
        initialize();
        repeat(5) @(posedge clk);
        reset(5);
        assert (empty == 1'b1) else begin
            errors = errors + 1;
            $display("ERROR: empty flag was not high in initial state (no stuff in fifo)");
        end
        for(int i = 0; i < LINE_DEPTH; i = i + 1) begin
            wr_data = i[7:0];
            write_data(wr_data);
        end
        assert (full == 1'b1) else begin
            errors = errors + 1;
            $display("ERROR: full flag not high after depth number of bytes written");
        end
        assert (empty == 1'b0) else begin
            errors = errors + 1;
            $display("ERROR: empty flag was high when fifo should have been full");
        end

        read_data(n_data); // [0] read out
        
        assert (full == 1'b0) else begin
            errors = errors + 1;
            $display("ERROR: full flag high after reading something when it was full");
        end
        assert (empty == 1'b0) else begin
            errors = errors + 1;
            $display("ERROR: empty flag was after reading something when it was full");
        end
        assert(n_data == 8'd0) else begin
            errors = errors + 1;
            $display("ERROR: first pixel read not expected value (0)");
        end

        read_data(n_data); // [1 2] read out

        assert (full == 1'b0) else begin
            errors = errors + 1;
            $display("ERROR: full flag high after reading something when it was full");
        end
        assert (empty == 1'b0) else begin
            errors = errors + 1;
            $display("ERROR: empty flag was after reading something when it was full");
        end
        assert(n_data == 8'd1) else begin
            errors = errors + 1;
            $display("ERROR: second pixel read not expected value (1)");
        end

        for(int i = 0; i < LINE_DEPTH - 2; i = i + 1) begin

            read_data(n_data);
            expected = (8'd2 + i[7:0]);
            assert(n_data == expected) else begin
                errors = errors + 1;
                $display("ERROR: did not receive correct n data in loop. actual: %d expected: %d", n_data, expected);
            end
        end

        assert(empty == 1'b1) else begin
            errors = errors + 1;
            $display("ERROR: empty flag not asserted when all values were read");
        end


        $display("Finished");
        if(errors == 0) begin
            $display("SUCCESS 0 errors yay");
        end else begin
            $display("FAIL some errors");
        end
        $display();

        $finish;
    end

    task write_data(input logic [7:0] dbyte);
        data = dbyte;
        pulse_valid();
    endtask : write_data

    task read_data(
        output logic [7:0] n_data,
    );
        pulse_read();
        n_data = out_data[7:0];
        @(posedge clk);
    endtask : read_data

    task read_write(
        input logic [7:0] i_d,
        output logic [7:0] n_data,
    );
        read_data(n_data);
        write_data(i_d);
    endtask : read_write

    task pulse_read();
        @(posedge clk);
        read_en = 1'b1;
        @(posedge clk);
        read_en = 1'b0;
        @(posedge clk);
    endtask : pulse_read

    task pulse_valid();
        @(posedge clk);
        data_valid = 1'b1;
        @(posedge clk);
        data_valid = 1'b0;
        @(posedge clk);
    endtask : pulse_valid

    task reset(input int n = 10);
        rst = 1'b1;
        repeat(n) @(posedge clk);
        rst = 1'b0;
        repeat(n) @(posedge clk);
    endtask : reset


    function void initialize();
        clk = 0;
        rst = 0;
        data_valid = 0;
        read_en = 0;
        errors = 0;
    endfunction : initialize


endmodule