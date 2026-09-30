`timescale 1ns / 1ps

module cca_top_tb();

    // We will shrink the frame size down to 200x200 so the simulation 
    // runs in milliseconds instead of minutes, but tests all the same logic!
    parameter SIM_WIDTH = 200;
    parameter SIM_HEIGHT = 200;

    logic clk;
    logic rst;

    // Pattern Generator -> CCA Top signals
    logic [7:0] tdata;
    logic       tvalid;
    logic       tuser;
    logic       tlast;
    logic       trdy;

    // CCA Top -> PS signals
    logic        interrupt;
    logic [31:0] bram_addr;
    logic [31:0] bram_wdata;
    logic [3:0]  bram_we;
    logic        bram_en;

    logic enable_pg;

    // 1. Instantiate the Pattern Generator
    pattern_gen #(
        .WIDTH(SIM_WIDTH),
        .HEIGHT(SIM_HEIGHT),
        // Object 1: 10x10 square
        .OBJ1_X_START(20), .OBJ1_Y_START(20), .OBJ1_SIZE(10),
        // Object 2: 20x20 square
        .OBJ2_X_START(100), .OBJ2_Y_START(100), .OBJ2_SIZE(20),
        // Collision Object: U-Shape
        .COLL_X_START(150), .COLL_Y_START(150), 
        .COLL_WIDTH(20), .COLL_HEIGHT(15), .COLL_THICKNESS(4),
        .NUM_FRAMES(5) 
    ) pg (
        .i_clk(clk),
        .i_rst(rst),
        .i_enable(enable_pg),
        .o_tdata(tdata),
        .o_tvalid(tvalid),
        .o_tuser(tuser),
        .o_tlast(tlast)
    );

    // 2. Instantiate the Top Level DUT
    cca_top #(
        .NUM_LABELS(1024),
        .ROW_SIZE(SIM_WIDTH),
        .COL_SIZE(SIM_HEIGHT)
    ) dut (
        .i_clk(clk),
        .i_rst(rst),
        .i_tdata(tdata),
        .i_tvalid(tvalid),
        .i_tuser(tuser),
        .i_tlast(tlast),
        .i_trdy(trdy),
        .o_interrupt(interrupt),
        .o_bram_addr(bram_addr),
        .o_bram_wdata(bram_wdata),
        .o_bram_we(bram_we),
        .o_bram_en(bram_en)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ==========================================
    // BRAM Sniffer (Scoreboard)
    // ==========================================
    // This block monitors the BRAM bus and prints the formatted centroid data
    // exactly as the ARM processor would read it.
    
    always_ff @(posedge clk) begin
        if (bram_en && bram_we == 4'b1111) begin
            // Is it the Header?
            if (bram_addr == 32'hA000_0000 || bram_addr == 32'hA000_0804 || bram_addr == 32'hA000_1008) begin
                $display("\n==========================================");
                $display("[%0t] BRAM WRITE: FRAME HEADER", $time);
                $display("    Address:  %0h", bram_addr);
                $display("    Frame #:  %0d", bram_wdata[31:8]);
                $display("    Centroids:%0d", bram_wdata[7:0]);
                $display("==========================================\n");
            end 
            // Is it Word 1 (X_sum)?
            else if ((bram_addr % 8) == 4) begin
                $display("[%0t] BRAM WRITE: CENTROID WORD 1", $time);
                $display("    Address:  %0h", bram_addr);
                $display("    X_sum:    %0d", bram_wdata);
            end
            // Is it Word 2 (Y_sum + Meta)?
            else if ((bram_addr % 8) == 0) begin
                $display("[%0t] BRAM WRITE: CENTROID WORD 2", $time);
                $display("    Address:  %0h", bram_addr);
                $display("    Y_sum:    %0d", bram_wdata[27:13]);
                $display("    Area:     %0d", bram_wdata[12:1]);
                $display("    Valid:    %0b\n", bram_wdata[0]);
            end
        end
    end

    // Test Sequence
    initial begin
        rst = 1;
        enable_pg = 0;

        // Give the Translator LUT its 1024 cycles to initialize
        $display("Waiting for Translator LUT initialization...");
        repeat(1050) @(posedge clk);
        rst = 0;
        @(posedge clk);

        $display("Starting Pattern Generator (Frame size: %0dx%0d, 3 Frames)...", SIM_WIDTH, SIM_HEIGHT);
        enable_pg = 1;
        @(posedge clk);
        enable_pg = 0; // It auto-latches and runs for NUM_FRAMES

        // Now we wait for 3 interrupts to fire!
        fork
            begin
                for (int i = 0; i < 5; i++) begin
                    @(posedge interrupt);
                    $display("[%0t] SUCCESS: Interrupt %0d received! Frame processing and dump complete.", $time, i+1);
                end
            end
            begin
                #5000000; // 5 millisecond timeout (plenty of time for 3 frames)
                $display("[%0t] TIMEOUT ERROR: Did not receive all 3 interrupts!", $time);
            end
        join_any
        disable fork;

        #500;
        $finish;
    end

endmodule
