`timescale 1ns / 1ps

module feature_extract_tb();

    parameter NUM_LABELS = 1024;
    parameter WIDTH = 1920;
    parameter HEIGHT = 1080;
    localparam LABEL_SIZE = $clog2(NUM_LABELS);

    logic clk;
    logic rst;
    logic [$clog2(WIDTH)-1:0] x_coord;
    logic [$clog2(HEIGHT)-1:0] y_coord;
    logic valid_coll;
    logic valid_label;
    logic [LABEL_SIZE-1:0] trans_label;
    logic [LABEL_SIZE-1:0] trans_min;
    logic [LABEL_SIZE-1:0] trans_max;
    
    logic frame_done;
    logic [23:0] frame_count;

    logic [31:0] bram_addr;
    logic [31:0] bram_wdata;
    logic [3:0]  bram_we;
    logic        bram_en;
    logic        dump_complete;

    feature_extract #(
        .NUM_LABELS(NUM_LABELS),
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) dut (
        .i_clk(clk),
        .i_rst(rst),
        .i_x_coord(x_coord),
        .i_y_coord(y_coord),
        .i_valid_coll(valid_coll),
        .i_valid_label(valid_label),
        .i_trans_label(trans_label),
        .i_trans_min(trans_min),
        .i_trans_max(trans_max),
        .i_frame_done(frame_done),
        .i_frame_count(frame_count),
        .o_bram_addr(bram_addr),
        .o_bram_wdata(bram_wdata),
        .o_bram_we(bram_we),
        .o_bram_en(bram_en),
        .o_dump_complete(dump_complete)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ==========================================
    // TB-Level SystemVerilog Assertions (SVAs)
    // ==========================================

    // 1. Zeros Table Invalidation during Collision
    // We check that when valid_coll is high, Port B write enable is triggered
    property p_zeros_table_we;
        @(posedge clk) disable iff (rst)
        valid_coll |-> dut.we_b_zt;
    endproperty
    assert property (p_zeros_table_we) else $error("SVA: Zeros table not invalidated on collision");

    // 2. BRAM Write Enable should only be active during DUMP states, not ACCUMULATE
    property p_bram_we_isolation;
        @(posedge clk) disable iff (rst)
        (dut.state == 3'd0 /* S_accum */) |-> (bram_we == 4'b0000);
    endproperty
    assert property (p_bram_we_isolation) else $error("SVA: BRAM WE active during ACCUMULATE state");

    // ==========================================
    // Stimulus (To be filled later)
    // ==========================================
    initial begin
        rst = 1;
        x_coord = 0; y_coord = 0;
        valid_coll = 0; valid_label = 0;
        trans_label = 0; trans_min = 0; trans_max = 0;
        frame_done = 0; frame_count = 0;

        repeat(5) @(posedge clk);
        rst = 0;

        // ==========================================
        // Manual Directed Stimulus
        // ==========================================
        
        // Wait for initialize (although FE doesn't have its own INIT state, it relies on rst)
        repeat(2) @(posedge clk);

        // Pixel 1: Valid label 1 at (10, 10)
        valid_label = 1; valid_coll = 0; trans_label = 1;
        x_coord = 10; y_coord = 10;
        @(posedge clk);

        // Pixel 2: Valid label 2 at (20, 20)
        valid_label = 1; valid_coll = 0; trans_label = 2;
        x_coord = 20; y_coord = 20;
        @(posedge clk);

        // Pixel 3: Collision! Merging Label 2 into 1 at (21, 20)
        valid_label = 1; valid_coll = 1; trans_min = 1; trans_max = 2;
        x_coord = 21; y_coord = 20;
        @(posedge clk);
        
        valid_coll = 0; valid_label = 0;
        repeat(2) @(posedge clk);

        // Trigger Frame Dump
        frame_done = 1;
        frame_count = 1;
        @(posedge clk);
        frame_done = 0;

        // Wait for state machine to finish dumping BRAM
        wait(dump_complete == 1'b1);
        @(posedge clk);

        #100;
        $finish;
    end

endmodule
