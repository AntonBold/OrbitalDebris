`timescale 1ns / 1ps

// Self-checking testbench for sync_debouncer (STABLE_CYCLES shortened to 50).
//
// Part 1, debouncer alone: bouncing presses and releases, plus glitches
//   shorter than STABLE_CYCLES. Expect exactly one 1-cycle pulse per press,
//   none on release, none for glitches, and each pulse only after the button
//   has been stable for STABLE_CYCLES.
// Part 2, button -> sync_debouncer -> pattern_gen -> cca_top (as in pl_ps.bd,
//   NUM_FRAMES = 1): a press held for several frame times must produce
//   exactly one frame and no pixels while cca_top is busy.

module sync_debouncer_tb;

    localparam int STABLE = 50;
    localparam int W = 64, H = 48;

    logic clk = 0;
    always #5 clk = ~clk;

    int errors = 0;

    // ------------------------------------------------------------------
    // Part 1: debouncer alone
    // ------------------------------------------------------------------
    logic btn = 0, pulse;
    sync_debouncer #(.STABLE_CYCLES(STABLE)) dut (.sys_clk(clk), .button(btn), .sync_deb_signal(pulse));

    int pulses = 0, pulse_len = 0;
    longint last_change = 0, cycle = 0;
    always @(posedge clk) begin
        cycle++;
        if (pulse) begin
            pulse_len++;
            if (pulse_len == 1) pulses++;
            if (pulse_len == 2) begin errors++; $display("FAIL: pulse longer than 1 cycle at cycle %0d", cycle); end
            // +2 for the synchronizer
            if (cycle - last_change < STABLE) begin
                errors++;
                $display("FAIL: pulse %0d cycles after the last bounce (needs >= %0d)", cycle - last_change, STABLE);
            end
        end else pulse_len = 0;
    end

    int unsigned rng = 32'hBEEF;
    function automatic int unsigned rnd();
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
        return rng;
    endfunction

    task automatic set_btn(logic v);
        @(negedge clk);
        if (btn != v) last_change = cycle;
        btn = v;
    endtask

    // Toggle randomly for `cycles` (contact bounce), then settle at `final_v`
    task automatic bounce(int cycles, logic final_v);
        repeat (cycles) begin
            set_btn(rnd() % 2);
            repeat (rnd() % 8) @(negedge clk);
        end
        set_btn(final_v);
    endtask

    task automatic expect_pulses(int n, string what);
        if (pulses != n) begin
            errors++;
            $display("FAIL: %s: %0d pulse(s) so far, expected %0d", what, pulses, n);
        end else $display("PASS: %s (%0d pulse(s) so far)", what, pulses);
    endtask

    // ------------------------------------------------------------------
    // Part 2: button -> debouncer -> pattern_gen -> cca_top
    // ------------------------------------------------------------------
    logic rst = 1, btn2 = 0, en;
    logic [7:0] tdata; logic tvalid, tuser, tlast, trdy, irq;
    logic [31:0] a, d; logic [3:0] we; logic bram_en;

    sync_debouncer #(.STABLE_CYCLES(STABLE)) deb2 (.sys_clk(clk), .button(btn2), .sync_deb_signal(en));
    pattern_gen #(.WIDTH(W), .HEIGHT(H), .OBJ1_X_START(5), .OBJ1_Y_START(5), .OBJ2_X_START(30),
                  .OBJ2_Y_START(20), .COLL_X_START(40), .COLL_Y_START(30)) pg (
        .i_clk(clk), .i_rst(rst), .i_enable(en),
        .m_axis_tdata(tdata), .m_axis_tvalid(tvalid), .m_axis_tuser(tuser), .m_axis_tlast(tlast));
    cca_top #(.ROW_SIZE(W), .COL_SIZE(H)) cca (
        .clk(clk), .rst(rst), .i_tdata(tdata), .i_tvalid(tvalid), .i_tuser(tuser), .i_tlast(tlast),
        .o_trdy(trdy), .o_interrupt(irq), .o_bram_addr(a), .o_bram_wdata(d), .o_bram_we(we),
        .o_bram_en(bram_en), .o_bram_clk());

    int frames = 0, irqs = 0, busy_px = 0;
    always @(posedge clk) if (!rst) begin
        if (tvalid && tuser) frames++;
        if (irq) irqs++;
        if (tvalid && (cca.decision_top.tl.state != 0 || cca.fe.state != 0)) busy_px++;
    end

    initial begin
        // ---- part 1 ----
        repeat (10) @(negedge clk);
        bounce(20, 1); repeat (3 * STABLE) @(negedge clk);
        expect_pulses(1, "bouncy press");
        bounce(20, 0); repeat (3 * STABLE) @(negedge clk);
        expect_pulses(1, "bouncy release gives no pulse");
        set_btn(1); repeat (STABLE / 2) @(negedge clk); set_btn(0); repeat (3 * STABLE) @(negedge clk);
        expect_pulses(1, "glitch shorter than STABLE_CYCLES ignored");
        set_btn(1); repeat (20 * STABLE) @(negedge clk);
        expect_pulses(2, "long clean press: one pulse");
        bounce(30, 0); repeat (3 * STABLE) @(negedge clk);
        bounce(30, 1); repeat (3 * STABLE) @(negedge clk);
        bounce(30, 0); repeat (3 * STABLE) @(negedge clk);
        expect_pulses(3, "third press");

        // ---- part 2 ----
        repeat (5) @(negedge clk); rst = 0;
        repeat (1100) @(negedge clk);                 // TL clears after reset
        btn2 = 1;
        repeat (5 * W * H) @(negedge clk);            // held ~5 frame times
        btn2 = 0;
        repeat (20000) @(negedge clk);
        if (frames == 1 && irqs == 1 && busy_px == 0)
            $display("PASS: held press -> %0d frame, %0d interrupt, %0d pixels while busy", frames, irqs, busy_px);
        else begin
            errors++;
            $display("FAIL: held press -> %0d frames, %0d interrupts, %0d pixels while busy (expected 1, 1, 0)",
                     frames, irqs, busy_px);
        end

        if (errors == 0) $display("SYNC_DEBOUNCER_TB PASSED");
        else $fatal(1, "SYNC_DEBOUNCER_TB FAILED (%0d errors)", errors);
        $finish;
    end

endmodule
