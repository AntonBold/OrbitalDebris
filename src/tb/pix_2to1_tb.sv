`timescale 1ns/1ps

// Self-checking testbench for pix_2to1 (docs/pix_2to1_spec.md).
//
// Structure:
//   - in_q:  beats waiting to be driven on s_axis (filled by the tests)
//   - driver: drives in_q onto s_axis, with optional random gaps (gap_pct)
//   - m_axis_tready: random backpressure (stall_pct)
//   - scoreboard: every accepted input beat pushes 2 expected pixels onto
//     exp_q (with a model of the start-of-frame gate); every accepted output
//     pixel pops one and compares
//
// Short lines (LINE_BEATS) keep the waveform readable. Test 5 runs two full
// 1920x1080 frames at the real rate.

module pix_2to1_tb;

    localparam int LINE_BEATS = 4;      // beats per line in the short tests
    localparam int TIMEOUT    = 10000;  // cycles before drain() gives up

    // Test 5: real 1080p30 timing seen at 75 MHz. A 2200-px line at 74.25 MHz
    // lasts ~2222 clocks: 960 beats at 1 beat / 2 clocks = 1920, + ~300 h-blank.
    // 45 blank lines = ~100,000 clocks of v-blank.
    localparam int FULL_BEATS = 960;
    localparam int FULL_LINES = 1080;
    localparam int H_IDLE     = 300;
    localparam int V_IDLE     = 45 * 2222;
    localparam int MIN_GAP    = 3000;   // hdmi-cca_interface.md, Frame Timing

    // ---------------- DUT signals ----------------
    logic        aclk = 0;
    logic        aresetn;
    logic [15:0] s_axis_tdata;
    logic        s_axis_tvalid, s_axis_tuser, s_axis_tlast, s_axis_tready;
    logic [7:0]  m_axis_tdata;
    logic        m_axis_tvalid, m_axis_tuser, m_axis_tlast, m_axis_tready;

    pix_2to1 dut (.*);

    always #5 aclk = ~aclk;

    // ---------------- TB state ----------------
    typedef struct packed {
        logic p0, p1, user, last;
        logic [31:0] idle_after;    // cycles to hold tvalid low after this beat
    } beat_t;

    typedef struct packed {
        logic [7:0] data;
        logic       user, last;
        int         t_in;   // cycle its beat was accepted (pixel 0 only, else -1)
    } pix_t;

    beat_t in_q[$];
    pix_t  exp_q[$];

    int  errors      = 0;
    int  pix_out     = 0;
    int  gap_pct     = 0;   // % chance the driver idles instead of sending
    int  stall_pct   = 0;   // % chance m_axis_tready is low
    bit  check_stall = 0;   // enforce P2-5 (s_axis_tready low <= 1 cycle)
    bit  tb_gate_open;      // TB model of the start-of-frame gate
    int  stall_cnt;
    logic rst_d = 0;        // aresetn was low last cycle
    beat_t drv_b;           // beat being driven
    pix_t  exp_p;           // expected pixel being compared
    int  idle_cnt    = 0;   // driver: idle cycles left before the next beat
    int  cyc         = 0;   // cycle counter
    bit  check_lat   = 0;   // measure latency (only valid with m_axis_tready held high)
    int  lat_min     = '1 >> 1;
    int  lat_max     = 0;

    // ---------------- driver ----------------
    // AXI rule: once tvalid is high, hold the beat until tready accepts it.
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            s_axis_tvalid <= 0;
        end else if (!s_axis_tvalid || s_axis_tready) begin
            if (idle_cnt > 0) begin
                s_axis_tvalid <= 0;
                idle_cnt <= idle_cnt - 1;
            end else if (in_q.size() > 0 && $urandom_range(99) >= gap_pct) begin
                drv_b = in_q.pop_front();
                idle_cnt <= drv_b.idle_after;
                s_axis_tvalid <= 1;
                s_axis_tdata  <= (16'($urandom) & 16'hFEFE) |{7'b0, drv_b.p1, 7'b0, drv_b.p0};  // junk in don't-care bits
                s_axis_tuser  <= drv_b.user;
                s_axis_tlast  <= drv_b.last;
            end else begin
                s_axis_tvalid <= 0;
            end
        end
    end

    // ---------------- backpressure ----------------
    always_ff @(posedge aclk)
        m_axis_tready <= ($urandom_range(99) >= stall_pct);

    // ---------------- scoreboard ----------------
    always @(posedge aclk) cyc <= cyc + 1;
    always @(posedge aclk) rst_d <= !aresetn;

    always @(posedge aclk) begin
        if (!aresetn) begin
            // P2-7. Reset is synchronous, so skip the first cycle of reset.
            if (rst_d && m_axis_tvalid) err("m_axis_tvalid high during reset");
            if (rst_d && s_axis_tready) err("s_axis_tready high during reset");
            tb_gate_open = 0;
            stall_cnt    = 0;
        end else begin
            // input side: build the expected output
            if (s_axis_tvalid && s_axis_tready) begin
                if (s_axis_tuser) tb_gate_open = 1;
                if (tb_gate_open) begin
                    exp_q.push_back('{data: {7'b0, s_axis_tdata[0]}, user: s_axis_tuser, last: 1'b0, t_in: cyc});
                    exp_q.push_back('{data: {7'b0, s_axis_tdata[8]}, user: 1'b0, last: s_axis_tlast, t_in: -1});
                end
            end

            // output side: compare
            if (m_axis_tvalid && m_axis_tready) begin
                if (exp_q.size() == 0) begin
                    err($sformatf("unexpected output pixel (data=%h user=%b last=%b)",
                                  m_axis_tdata, m_axis_tuser, m_axis_tlast));
                end else begin
                    exp_p = exp_q.pop_front();
                    if (m_axis_tdata !== exp_p.data || m_axis_tuser !== exp_p.user || m_axis_tlast !== exp_p.last)
                        err($sformatf("pixel %0d: got data=%h user=%b last=%b, expected data=%h user=%b last=%b",
                                      pix_out, m_axis_tdata, m_axis_tuser, m_axis_tlast,
                                      exp_p.data, exp_p.user, exp_p.last));
                    // Behavior 7: input acceptance -> first output pixel
                    if (check_lat && exp_p.t_in >= 0) begin
                        if (cyc - exp_p.t_in < lat_min) lat_min = cyc - exp_p.t_in;
                        if (cyc - exp_p.t_in > lat_max) lat_max = cyc - exp_p.t_in;
                    end
                end
                pix_out++;
            end

            // P2-5: with m_axis_tready high, s_axis_tready low <= 1 cycle in a row
            if (check_stall && s_axis_tvalid && !s_axis_tready && m_axis_tready) begin
                stall_cnt++;
                if (stall_cnt > 1) err("s_axis_tready low for more than 1 consecutive cycle");
            end else begin
                stall_cnt = 0;
            end
        end
    end

    // ---------------- frame monitor (Test 5) ----------------
    // Counts geometry at the output: pixels per line, lines per frame, tusers,
    // and idle cycles between a frame's last pixel and the next frame's first.
    bit  frame_check = 0;
    int  fm_px, fm_lines, fm_frames, fm_idle, fm_min_gap;

    always @(posedge aclk) begin
        if (frame_check && aresetn) begin
            if (m_axis_tvalid && m_axis_tready) begin
                if (m_axis_tuser) begin
                    if (fm_frames > 0) begin
                        if (fm_lines != FULL_LINES)
                            err($sformatf("frame %0d had %0d lines, expected %0d", fm_frames - 1, fm_lines, FULL_LINES));
                        if (fm_idle < fm_min_gap) fm_min_gap = fm_idle;
                    end
                    fm_frames++;
                    fm_lines = 0;
                    fm_px    = 0;
                end
                fm_px++;
                if (m_axis_tlast) begin
                    if (fm_px != 2 * FULL_BEATS)
                        err($sformatf("line %0d had %0d pixels, expected %0d", fm_lines, fm_px, 2 * FULL_BEATS));
                    fm_lines++;
                    fm_px = 0;
                end
                fm_idle = 0;
            end else begin
                fm_idle++;
            end
        end
    end

    // ---------------- helpers ----------------
    function automatic void err(string msg);
        errors++;
        $display("ERROR @%0t: %s", $time, msg);
    endfunction

    // Queue n_lines lines of random pixels. sof puts tuser on the first beat.
    // Optional timing: beat_idle cycles after every beat, h_idle extra after
    // each line, v_idle extra after the frame.
    function automatic void queue_frame(int n_lines, bit sof, int beats = LINE_BEATS,
                                        int beat_idle = 0, int h_idle = 0, int v_idle = 0);
        for (int l = 0; l < n_lines; l++)
            for (int b = 0; b < beats; b++) begin
                int idle = beat_idle;
                if (b == beats - 1)   idle += h_idle;
                if (b == beats - 1 && l == n_lines - 1) idle += v_idle;
                in_q.push_back('{p0:   1'($urandom),
                                 p1:   1'($urandom),
                                 user: sof && l == 0 && b == 0,
                                 last: b == beats - 1,
                                 idle_after: 32'(idle)});
            end
    endfunction

    // Wait until everything queued has gone in and come out.
    task automatic drain(int timeout = TIMEOUT);
        int t = 0;
        while ((in_q.size() != 0 || s_axis_tvalid || exp_q.size() != 0) && t < timeout) begin
            @(posedge aclk);
            t++;
        end
        if (t >= timeout) err($sformatf("drain timeout: %0d beats unsent, %0d pixels missing",
                                         in_q.size(), exp_q.size()));
        repeat (5) @(posedge aclk);
    endtask

    task automatic do_reset(int cycles);
        aresetn <= 0;
        repeat (cycles) @(posedge aclk);
        in_q.delete();
        exp_q.delete();
        idle_cnt = 0;
        aresetn <= 1;
        @(posedge aclk);
    endtask

    // ---------------- tests ----------------
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars();

        s_axis_tdata = 0; s_axis_tuser = 0; s_axis_tlast = 0;
        do_reset(5);

        // Test 1: back-to-back beats, m_axis_tready = 1 (P2-1, P2-5)
        $display("Test 1: back-to-back, no backpressure");
        gap_pct = 0; stall_pct = 0; check_stall = 1; check_lat = 1;
        queue_frame(3, 1);
        drain();
        check_stall = 0;

        // Test 2: random gaps between beats (P2-1, P2-6)
        $display("Test 2: random input gaps");
        gap_pct = 50; stall_pct = 0;
        queue_frame(3, 1);
        drain();
        check_lat = 0;

        // Test 3: random backpressure (P2-4)
        $display("Test 3: random m_axis_tready");
        gap_pct = 20; stall_pct = 50;
        queue_frame(10, 1);
        drain();

        // Test 4: reset mid-line, then a partial frame before the first tuser (P2-7, P2-9)
        $display("Test 4: reset mid-line + start-of-frame gate");
        gap_pct = 0; stall_pct = 30;
        queue_frame(2, 1);
        repeat (LINE_BEATS + 1) @(posedge aclk);    // part-way through line 1
        do_reset(3);
        queue_frame(2, 0);                          // no tuser: must all be dropped
        queue_frame(2, 1);                          // forwarded from its first beat
        drain();

        // Test 5: two full 1080p30 frames at real rate (P2-5, P2-6)
        $display("Test 5: 2 full 1920x1080 frames at 1 beat / 2 clocks");
        gap_pct = 0; stall_pct = 0; check_stall = 1; check_lat = 1;
        frame_check = 1; fm_frames = 0; fm_lines = 0; fm_px = 0; fm_idle = 0; fm_min_gap = '1 >> 1;
        repeat (2) queue_frame(FULL_LINES, 1, FULL_BEATS, 1, H_IDLE, V_IDLE);
        drain(2 * FULL_LINES * (2 * FULL_BEATS + H_IDLE) + 2 * V_IDLE + 1000);
        if (fm_frames != 2)          err($sformatf("saw %0d tusers, expected 2", fm_frames));
        if (fm_lines != FULL_LINES)  err($sformatf("last frame had %0d lines, expected %0d", fm_lines, FULL_LINES));
        if (fm_min_gap < MIN_GAP)    err($sformatf("inter-frame gap %0d cycles, need >= %0d", fm_min_gap, MIN_GAP));
        $display("  inter-frame gap at output: %0d cycles", fm_min_gap);
        frame_check = 0; check_stall = 0; check_lat = 0;

        // Latency, measured in Tests 1, 2 and 5 (m_axis_tready high): fixed and <= 3 clocks
        $display("Latency: min %0d, max %0d clocks", lat_min, lat_max);
        if (lat_max > 3)        err($sformatf("latency %0d clocks, spec allows <= 3", lat_max));
        if (lat_min != lat_max) err("latency is not fixed");

        if (errors == 0) $display("PASS: %0d pixels checked", pix_out);
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
