`timescale 1ns / 1ps

// Self-checking testbench for pattern_gen's vertical blanking and its
// held-enable (free-running) mode, the way the PS drives i_enable through
// the AXI GPIO in pl_ps.bd.
//
// Part A, 64x48 pattern_gen -> cca_top:
//   - i_enable held high: frames keep coming, each followed by exactly
//     VBLANK_CYCLES idle cycles, one interrupt per frame, no pixel while
//     cca_top is busy
//   - i_enable dropped mid-frame: that frame finishes, then the stream stops
//   - a 1-cycle pulse afterwards: exactly one more frame
// Part B, 1920x1080 pattern_gen alone with the block design's defaults:
//   the gap is 45 lines x 2200 clocks = 99,000 cycles, as in 1080p60.

module pattern_gen_vblank_tb;

    localparam int W = 64, H = 48;
    localparam int VBLANK = 45 * (W + 280);
    localparam int HELD_FRAMES = 4;

    logic clk = 0;
    always #5 clk = ~clk;

    int errors = 0;
    longint cycle = 0;
    always @(posedge clk) cycle++;

    // ------------------------------------------------------------------
    // Part A
    // ------------------------------------------------------------------
    logic rst = 1, en = 0;
    logic [7:0] tdata; logic tvalid, tuser, tlast, trdy, irq;
    logic [31:0] a, d; logic [3:0] we; logic bram_en;

    pattern_gen #(.WIDTH(W), .HEIGHT(H), .OBJ1_X_START(5), .OBJ1_Y_START(5), .OBJ2_X_START(30),
                  .OBJ2_Y_START(20), .COLL_X_START(40), .COLL_Y_START(30)) pg (
        .i_clk(clk), .i_rst(rst), .i_enable(en),
        .m_axis_tdata(tdata), .m_axis_tvalid(tvalid), .m_axis_tuser(tuser), .m_axis_tlast(tlast));
    cca_top #(.ROW_SIZE(W), .COL_SIZE(H)) cca (
        .clk(clk), .rst(rst), .i_tdata(tdata), .i_tvalid(tvalid), .i_tuser(tuser), .i_tlast(tlast),
        .o_trdy(trdy), .o_interrupt(irq), .o_bram_addr(a), .o_bram_wdata(d), .o_bram_we(we),
        .o_bram_en(bram_en), .o_bram_clk());

    // frames = first pixels seen; gaps = idle cycles between a frame's last
    // pixel and the next frame's first pixel
    bit held = 1;
    int frames = 0, irqs = 0, busy_px = 0, px_in_frame = 0, bad_gaps = 0, gaps = 0;
    longint last_px_cycle = -1;
    always @(posedge clk) if (!rst) begin
        if (irq) irqs++;
        if (tvalid && (cca.decision_top.tl.state != 0 || cca.fe.state != 0)) busy_px++;
        if (tvalid) begin
            if (tuser) begin
                // while i_enable is held the gap is exactly VBLANK; after an
                // idle period (pulse) it is only at least VBLANK
                if (frames > 0) begin
                    gaps++;
                    if (held ? cycle - last_px_cycle - 1 != VBLANK : cycle - last_px_cycle - 1 < VBLANK) begin
                        bad_gaps++;
                        $display("FAIL: gap before frame %0d is %0d idle cycles, expected %s%0d",
                                 frames + 1, cycle - last_px_cycle - 1, held ? "" : ">= ", VBLANK);
                    end
                end
                frames++;
                px_in_frame = 0;
            end
            px_in_frame++;
            if (px_in_frame == W * H) last_px_cycle = cycle;
        end
    end

    task automatic check(bit ok, string what);
        if (ok) $display("PASS: %s", what);
        else begin errors++; $display("FAIL: %s", what); end
    endtask

    // ------------------------------------------------------------------
    // Part B
    // ------------------------------------------------------------------
    localparam int FW = 1920, FH = 1080;
    logic en_b = 0;
    logic [7:0] tdata_b; logic tvalid_b, tuser_b, tlast_b;
    pattern_gen pg_full (
        .i_clk(clk), .i_rst(rst), .i_enable(en_b),
        .m_axis_tdata(tdata_b), .m_axis_tvalid(tvalid_b), .m_axis_tuser(tuser_b), .m_axis_tlast(tlast_b));

    int frames_b = 0, px_b = 0;
    longint first_b[2], last_b = -1, gap_b = -1;
    always @(posedge clk) if (!rst && tvalid_b) begin
        if (tuser_b) begin
            if (frames_b < 2) first_b[frames_b] = cycle;
            if (frames_b == 1) gap_b = cycle - last_b - 1;
            frames_b++;
            px_b = 0;
        end
        px_b++;
        if (px_b == FW * FH) last_b = cycle;
    end

    initial begin
        int f0, i0;

        repeat (5) @(negedge clk); rst = 0;
        repeat (1100) @(negedge clk);                       // TL clears after reset

        // ---- A: held enable ----
        en = 1; en_b = 1;
        wait (frames == HELD_FRAMES);
        repeat (W * H / 2) @(negedge clk);                  // mid-frame HELD_FRAMES
        en = 0;
        repeat (3 * (W * H + VBLANK)) @(negedge clk);
        check(frames == HELD_FRAMES && irqs == HELD_FRAMES,
              $sformatf("held enable: %0d frames, %0d interrupts (expected %0d each)", frames, irqs, HELD_FRAMES));
        check(gaps == HELD_FRAMES - 1 && bad_gaps == 0,
              $sformatf("held enable: %0d gaps of %0d idle cycles (%0d wrong)", gaps, VBLANK, bad_gaps));
        check(!tvalid, "enable dropped: stream stopped after the current frame");

        // ---- A: one pulse ----
        held = 0;
        f0 = frames; i0 = irqs;
        @(negedge clk) en = 1;
        @(negedge clk) en = 0;
        repeat (3 * (W * H + VBLANK)) @(negedge clk);
        check(frames == f0 + 1 && irqs == i0 + 1,
              $sformatf("pulse: %0d frame(s), %0d interrupt(s) (expected 1, 1)", frames - f0, irqs - i0));
        check(bad_gaps == 0, $sformatf("%0d wrong gaps in total", bad_gaps));
        check(busy_px == 0, $sformatf("%0d pixels while cca_top was busy (expected 0)", busy_px));

        // ---- B: 1080p gap ----
        wait (frames_b == 2);
        en_b = 0;
        check(gap_b == 99000,
              $sformatf("1920x1080: gap %0d idle cycles (expected 45 x 2200 = 99000)", gap_b));
        check(first_b[1] - first_b[0] == FW * FH + 99000,
              $sformatf("1920x1080: frame period %0d cycles (expected %0d)", first_b[1] - first_b[0], FW * FH + 99000));

        if (errors == 0) $display("PATTERN_GEN_VBLANK_TB PASSED");
        else $fatal(1, "PATTERN_GEN_VBLANK_TB FAILED (%0d errors)", errors);
        $finish;
    end

    initial begin
        #(64'd10 * 3 * (FW * FH + 99000) + 64'd10_000_000);
        $fatal(1, "PATTERN_GEN_VBLANK_TB TIMEOUT");
    end

endmodule
