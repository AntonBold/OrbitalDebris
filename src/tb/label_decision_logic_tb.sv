`timescale 1ns / 1ps

module label_decision_logic_tb();

    parameter NUM_LABELS = 1024;
    localparam LABEL_SIZE = $clog2(NUM_LABELS);

    logic clk;
    logic rst;
    logic pixel_data;
    logic first_row;
    logic first_col;
    logic [LABEL_SIZE-1:0] trans_label_n;
    logic [LABEL_SIZE-1:0] trans_label_w;
    
    logic [LABEL_SIZE-1:0] labeled_pixel;
    logic valid_label;
    logic lut_we;
    logic [LABEL_SIZE-1:0] lut_addrd;
    logic [LABEL_SIZE-1:0] lut_dind;

    label_decision_logic #(
        .NUM_LABELS(NUM_LABELS)
    ) dut (
        .i_clk(clk),
        .i_rst(rst),
        .i_pixel_data(pixel_data),
        .first_row(first_row),
        .first_col(first_col),
        .i_trans_label_n(trans_label_n),
        .i_trans_label_w(trans_label_w),
        .o_labeled_pixel(labeled_pixel),
        .valid_label(valid_label),
        .o_lut_we(lut_we),
        .o_lut_addrd(lut_addrd),
        .o_lut_dind(lut_dind)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ==========================================
    // TB-Level SystemVerilog Assertions (SVAs)
    // ==========================================

    // 1. Collision correctly asserts lut_we
    property p_collision_we;
        @(posedge clk) disable iff (rst)
        (pixel_data && (trans_label_n != 0) && (trans_label_w != 0) && (trans_label_n != trans_label_w)) 
        |-> lut_we;
    endproperty
    assert property (p_collision_we) else $error("SVA: lut_we not asserted during collision");

    // 2. Collision correctly maps MAX to Address and MIN to Data
    property p_collision_max_min;
        @(posedge clk) disable iff (rst)
        (lut_we) |-> 
        ((lut_addrd >= lut_dind) && 
         (lut_addrd == trans_label_n || lut_addrd == trans_label_w) &&
         (lut_dind == trans_label_n || lut_dind == trans_label_w));
    endproperty
    assert property (p_collision_max_min) else $error("SVA: Collision MAX/MIN mapping is incorrect");

    // ==========================================
    // Stimulus (To be filled later)
    // ==========================================
    initial begin
        rst = 1;
        pixel_data = 0;
        first_row = 0;
        first_col = 0;
        trans_label_n = 0;
        trans_label_w = 0;

        repeat(5) @(posedge clk);
        rst = 0;

        // ==========================================
        // Manual Directed Stimulus
        // ==========================================

        // Case 0: Background Pixel
        pixel_data = 0; trans_label_n = 0; trans_label_w = 0;
        @(posedge clk);
        
        // Case 1: New Object (Foreground, no neighbors)
        pixel_data = 1; trans_label_n = 0; trans_label_w = 0;
        @(posedge clk);
        
        // Case 2: Continuing Object (Foreground, North is valid)
        pixel_data = 1; trans_label_n = 5; trans_label_w = 0;
        @(posedge clk);
        
        // Case 3: Continuing Object (Foreground, West is valid)
        pixel_data = 1; trans_label_n = 0; trans_label_w = 4;
        @(posedge clk);

        // Case 4: Collision! (Merge 7 and 3)
        // Since it's purely combinational, we can read the outputs instantly.
        pixel_data = 1; trans_label_n = 3; trans_label_w = 7;
        #1;
        $display("Collision Test: MAX=%0d, MIN=%0d, WE=%0b", lut_addrd, lut_dind, lut_we);
        @(posedge clk);

        #100;
        $finish;
    end

endmodule
