`timescale 1ns / 1ps

module cca_control_tb();

    // Clock and Reset
    logic clk;
    logic rst;

    // AXI-Stream Inputs
    logic tuser;
    logic tlast;
    logic tvalid;

    // Module Outputs
    logic first_row;
    logic first_col;
    logic frame_done;
    logic [23:0] frame_count;
    logic [10:0] x_coord;
    logic [10:0] y_coord;
    logic dump_complete;
    logic interrupt;

    // DUT
    cca_control #(
        .WIDTH(1920),
        .HEIGHT(1080)
    ) dut (
        .i_clk(clk),
        .i_rst(rst),
        .i_tuser(tuser),
        .i_tlast(tlast),
        .i_tvalid(tvalid),
        .o_first_row(first_row),
        .o_first_col(first_col),
        .o_frame_done(frame_done),
        .o_frame_count(frame_count),
        .o_x_coord(x_coord),
        .o_y_coord(y_coord),
        .i_dump_complete(dump_complete),
        .o_interrupt(interrupt)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ==========================================
    // TB-Level SystemVerilog Assertions (SVAs)
    // ==========================================
    
    // 1. first_col should always be high on TUSER (Start of Frame)
    property p_first_col_on_tuser;
        @(posedge clk) disable iff (rst)
        (tvalid && tuser) |-> first_col;
    endproperty
    assert property (p_first_col_on_tuser) else $error("SVA: first_col not high on TUSER");

    // 2. first_col should be high on the first valid pixel after TLAST
    property p_first_col_after_tlast;
        @(posedge clk) disable iff (rst)
        (tvalid && tlast) |=> (tvalid[->1] |-> first_col);
    endproperty
    assert property (p_first_col_after_tlast) else $error("SVA: first_col not high after TLAST");

    // ==========================================
    // Stimulus (To be filled later)
    // ==========================================
    initial begin
        rst = 1;
        tuser = 0;
        tlast = 0;
        tvalid = 0;
        dump_complete = 0;
        
        repeat(5) @(posedge clk);
        rst = 0;

        // ==========================================
        // Manual Directed Stimulus
        // ==========================================
        
        // 1. Start of Frame (Row 0, Col 0)
        tvalid = 1; tuser = 1; tlast = 0;
        @(posedge clk);
        
        // 2. Normal pixel (Row 0, Col 1)
        tuser = 0;
        @(posedge clk);
        
        // 3. Pause stream (H-Blanking or stall)
        tvalid = 0;
        repeat(3) @(posedge clk);
        
        // 4. End of Line (Row 0, Col 2)
        tvalid = 1; tlast = 1;
        @(posedge clk);
        
        // 5. Start of new line (Row 1, Col 0)
        tlast = 0;
        @(posedge clk);
        
        // 6. Normal pixel (Row 1, Col 1)
        @(posedge clk);
        
        // Stop stream
        tvalid = 0;

        // Test interrupt loopback
        repeat(5) @(posedge clk);
        $display("Testing Interrupt Pulse...");
        dump_complete = 1;
        @(posedge clk);
        dump_complete = 0;

        #100;
        $finish;
    end

endmodule
