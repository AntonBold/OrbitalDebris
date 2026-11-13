`timescale 1ns/1ps

// Self-checking testbench for threshold (docs/hdmi-cca_interface.md v0.2).
//
// Structure (same style as pix_2to1_tb):
//   - in_q:    beats waiting to be driven on s_axis (filled by the tests)
//   - driver:  drives in_q onto s_axis, with optional random gaps (gap_pct)
//   - m_axis_tready: random backpressure (stall_pct)
//   - ref_q:   every accepted input beat is pushed here; every accepted output
//              beat pops one and is compared against the reference model
//
// The method follows MATLAB: grey = rgb2gray(pixel), foreground = grey > THR
// (imbinarize: values above the threshold become 1). rgb2gray weights are
// 0.2989 R + 0.5870 G + 0.1140 B, rounded to the nearest integer (round-to-nearest
// for uint8 is an assumption, the MATLAB page does not state it). THR is
// the grey level, 0..255 (MATLAB level x 255, rounded down).
// THR is still to be decided, so six DUTs with different THR are instantiated
// side by side and fed the same stream. Each is checked against its own reference
// model, so the checks hold whatever value is finally chosen. Byte lanes, from
// the low byte up: G, B, R (the Vivado metadata of the RXSS output says so).
//
// The DUT is combinational (latency 0). EXP_LAT is the latency the testbench
// requires; change it if the DUT is ever registered.
//
// Short lines (LINE_BEATS) keep the waveforms readable. Test 7 runs one full
// 1920x1080 frame at the real 1080p30 rate.

module threshold_tb;

    localparam int LINE_BEATS = 4;
    localparam int TIMEOUT    = 10000;   // cycles before drain() gives up
    localparam int EXP_LAT    = 0;       // required input-accept -> output-accept latency
    localparam int MAX_PRINT  = 20;      // stop printing errors after this many

    // Test 7: real 1080p30 timing at 75 MHz. A 2200-px line at 74.25 MHz lasts
    // ~2222 clocks: 960 beats at 1 beat / 2 clocks = 1920, + ~300 h-blank.
    // 45 blank lines = ~100,000 clocks of v-blank.
    localparam int FULL_BEATS = 960;
    localparam int FULL_LINES = 1080;
    localparam int H_IDLE     = 300;
    localparam int V_IDLE     = 45 * 2222;

    // ---------------- DUT configurations ----------------
    // foreground = grey > THR. 0 = everything but black, 255 = nothing.
    localparam int NCFG = 6;
    localparam int CFG_THR [NCFG] = '{32, 0, 100, 128, 254, 255};

    // ---------------- DUT signals ----------------
    logic        aclk = 0;
    logic        aresetn = 0;
    logic [47:0] s_axis_tdata = 0;
    logic        s_axis_tvalid = 0, s_axis_tuser = 0, s_axis_tlast = 0;
    logic        m_axis_tready = 1;

    logic        s_tready [NCFG];
    logic [15:0] m_tdata  [NCFG];
    logic        m_tvalid [NCFG];
    logic        m_tuser  [NCFG];
    logic        m_tlast  [NCFG];

    for (genvar i = 0; i < NCFG; i++) begin : g_dut
        threshold #(.THR(CFG_THR[i])) dut (
            .aclk         (aclk),
            .aresetn      (aresetn),
            .s_axis_tdata (s_axis_tdata),
            .s_axis_tvalid(s_axis_tvalid),
            .s_axis_tready(s_tready[i]),
            .s_axis_tuser (s_axis_tuser),
            .s_axis_tlast (s_axis_tlast),
            .m_axis_tdata (m_tdata[i]),
            .m_axis_tvalid(m_tvalid[i]),
            .m_axis_tready(m_axis_tready),
            .m_axis_tuser (m_tuser[i]),
            .m_axis_tlast (m_tlast[i])
        );
    end

    always #5 aclk = ~aclk;

    // ---------------- reference model ----------------
    // MATLAB rgb2gray on a uint8 pixel: 0.2989 R + 0.5870 G + 0.1140 B, rounded.
    // Done in integers (weights x 10000): round-to-nearest = (sum + 5000) / 10000.
    function automatic int gray_of(logic [23:0] pix);
        int grn, blu, red;
        grn = int'(pix[7:0]);
        blu = int'(pix[15:8]);
        red = int'(pix[23:16]);
        return (2989 * red + 5870 * grn + 1140 * blu + 5000) / 10000;
    endfunction

    // imbinarize: above the threshold -> 1
    function automatic logic model_bit(int thr, logic [23:0] pix);
        return gray_of(pix) > thr;
    endfunction

    // expected 16-bit output word for DUT i: pixel 0 -> bit 0, pixel 1 -> bit 8
    function automatic logic [15:0] exp_word(int i, logic [47:0] d);
        return {7'b0, model_bit(CFG_THR[i], d[47:24]),
                7'b0, model_bit(CFG_THR[i], d[23:0])};
    endfunction

    // ---------------- TB state ----------------
    typedef struct packed {
        logic [47:0] data;
        logic        user, last;
        logic [31:0] idle_after;    // cycles to hold tvalid low after this beat
    } beat_t;

    typedef struct packed {
        logic [47:0] data;
        logic        user, last;
        int          t_in;          // cycle the beat was accepted
    } ref_t;

    beat_t       in_q[$];
    ref_t        ref_q[$];
    logic [15:0] lit_q[$];          // literal expected words for DUT 0 (tests 1, 2)

    int  errors      = 0;
    int  beats_out   = 0;
    int  gap_pct     = 0;           // % chance the driver idles instead of sending
    int  stall_pct   = 0;           // % chance m_axis_tready is low
    bit  lit_en      = 0;           // also compare DUT 0 against lit_q
    bit  mon_en      = 0;           // record sideband positions (test 3)
    int  out_idx     = 0;
    int  u_idx[$];
    int  l_idx[$];
    int  idle_cnt    = 0;           // driver: idle cycles left before the next beat
    int  cyc         = 0;
    int  lat_min     = '1 >> 1;
    int  lat_max     = 0;
    bit  rst_d       = 0;           // aresetn was low last cycle
    beat_t drv_b;
    ref_t  ref_p;
    ref_t  ref_n;
    logic [15:0] lit_w;
    int  lat;

    // previous-cycle snapshot, for the "stable while stalled" check
    bit          prev_stall [NCFG];
    logic [15:0] prev_data  [NCFG];
    bit          prev_user  [NCFG];
    bit          prev_last  [NCFG];

    // ---------------- helpers ----------------
    function automatic void err(string msg);
        errors++;
        if (errors <= MAX_PRINT) $display("ERROR @%0t: %s", $time, msg);
        if (errors == MAX_PRINT + 1) $display("  (further errors counted, not printed)");
    endfunction

    function automatic logic [7:0] clamp8(int v);
        if (v < 0)   return 8'd0;
        if (v > 255) return 8'd255;
        return 8'(v);
    endfunction

    // random byte, biased towards the thresholds of the configurations under test
    function automatic logic [7:0] rand_byte();
        int r, t;
        r = $urandom_range(99);
        t = CFG_THR[$urandom_range(NCFG - 1)];
        if (r < 20) return clamp8(t - 1 + int'($urandom_range(2)));
        if (r < 28) return 8'd0;
        if (r < 36) return 8'd255;
        return 8'($urandom);
    endfunction

    function automatic logic [23:0] rand_pix();
        return {rand_byte(), rand_byte(), rand_byte()};
    endfunction

    function automatic void push_beat(logic [47:0] d, bit user, bit last, int idle = 0);
        beat_t b;
        b.data       = d;
        b.user       = user;
        b.last       = last;
        b.idle_after = 32'(idle);
        in_q.push_back(b);
    endfunction

    // beat with a literal expected output word for DUT 0
    function automatic void push_lit(logic [47:0] d, logic [15:0] e);
        push_beat(d, 1'b0, 1'b0);
        lit_q.push_back(e);
    endfunction

    // Queue n_lines lines of random pixels. sof puts tuser on the first beat.
    // beat_idle cycles after every beat, h_idle extra after each line, v_idle
    // extra after the frame.
    function automatic void queue_frame(int n_lines, bit sof, int beats = LINE_BEATS,
                                        int beat_idle = 0, int h_idle = 0, int v_idle = 0);
        for (int l = 0; l < n_lines; l++)
            for (int b = 0; b < beats; b++) begin
                int idle;
                idle = beat_idle;
                if (b == beats - 1)                     idle += h_idle;
                if (b == beats - 1 && l == n_lines - 1) idle += v_idle;
                push_beat({rand_pix(), rand_pix()}, sof && l == 0 && b == 0, b == beats - 1, idle);
            end
    endfunction

    // Wait until everything queued has gone in and come out.
    task automatic drain(int timeout = TIMEOUT);
        int t;
        t = 0;
        while ((in_q.size() != 0 || s_axis_tvalid || ref_q.size() != 0) && t < timeout) begin
            @(posedge aclk);
            t++;
        end
        if (t >= timeout) err($sformatf("drain timeout: %0d beats unsent, %0d beats missing",
                                         in_q.size(), ref_q.size()));
        repeat (5) @(posedge aclk);
    endtask

    task automatic do_reset(int cycles);
        aresetn <= 0;
        repeat (cycles) @(posedge aclk);
        in_q.delete();
        ref_q.delete();
        lit_q.delete();
        idle_cnt = 0;
        aresetn <= 1;
        @(posedge aclk);
    endtask

    int test_errs0;
    task automatic begin_test(string name);
        $display("%s", name);
        test_errs0 = errors;
    endtask
    task automatic end_test();
        if (errors == test_errs0) $display("  PASS");
        else                      $display("  FAIL (%0d errors)", errors - test_errs0);
    endtask

    // ---------------- driver ----------------
    // AXI rule: once tvalid is high, hold the beat until tready accepts it.
    // tdata is junk while tvalid is low.
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            s_axis_tvalid <= 0;
        end else if (!s_axis_tvalid || s_tready[0]) begin
            if (idle_cnt > 0) begin
                s_axis_tvalid <= 0;
                s_axis_tdata  <= 48'({$urandom, $urandom});
                idle_cnt <= idle_cnt - 1;
            end else if (in_q.size() > 0 && $urandom_range(99) >= gap_pct) begin
                drv_b = in_q.pop_front();
                idle_cnt <= drv_b.idle_after;
                s_axis_tvalid <= 1;
                s_axis_tdata  <= drv_b.data;
                s_axis_tuser  <= drv_b.user;
                s_axis_tlast  <= drv_b.last;
            end else begin
                s_axis_tvalid <= 0;
                s_axis_tdata  <= 48'({$urandom, $urandom});
            end
        end
    end

    // ---------------- backpressure ----------------
    always_ff @(posedge aclk)
        m_axis_tready <= ($urandom_range(99) >= stall_pct);

    // ---------------- scoreboard ----------------
    always @(posedge aclk) begin
        cyc   <= cyc + 1;
        rst_d <= !aresetn;
    end

    always @(posedge aclk) begin
        // every cycle, every DUT: tready passes straight through and blanking
        // (tvalid low) reaches the output unchanged: no buffering
        for (int i = 0; i < NCFG; i++) begin
            if (s_tready[i] !== m_axis_tready)
                err($sformatf("DUT %0d: s_axis_tready (%b) is not m_axis_tready (%b)", i, s_tready[i], m_axis_tready));
            if (m_tvalid[i] !== s_axis_tvalid)
                err($sformatf("DUT %0d: m_axis_tvalid (%b) does not follow s_axis_tvalid (%b)", i, m_tvalid[i], s_axis_tvalid));
            // nothing may come out while in reset (the driver holds tvalid low in reset)
            if (!aresetn && rst_d && m_tvalid[i] !== 1'b0)
                err($sformatf("DUT %0d: m_axis_tvalid high during reset", i));
        end

        // output must not change while it is stalled (tvalid high, tready low)
        for (int i = 0; i < NCFG; i++) begin
            if (prev_stall[i] && aresetn) begin
                if (m_tvalid[i] !== 1'b1 || m_tdata[i] !== prev_data[i] ||
                    m_tuser[i] !== prev_user[i] || m_tlast[i] !== prev_last[i])
                    err($sformatf("DUT %0d: output changed or dropped while stalled", i));
            end
            prev_stall[i] = aresetn && (m_tvalid[i] === 1'b1) && (m_axis_tready === 1'b0);
            prev_data[i]  = m_tdata[i];
            prev_user[i]  = m_tuser[i];
            prev_last[i]  = m_tlast[i];
        end

        // input side: record the accepted beat
        if (s_axis_tvalid && s_tready[0]) begin
            ref_n.data = s_axis_tdata;
            ref_n.user = s_axis_tuser;
            ref_n.last = s_axis_tlast;
            ref_n.t_in = cyc;
            ref_q.push_back(ref_n);
        end

        // output side: compare every DUT against the model
        if (m_tvalid[0] && m_axis_tready) begin
            if (ref_q.size() == 0) begin
                err("unexpected output beat");
            end else begin
                ref_p = ref_q.pop_front();
                for (int i = 0; i < NCFG; i++) begin
                    if (m_tdata[i] !== exp_word(i, ref_p.data))
                        err($sformatf("beat %0d DUT %0d: in=%h got=%h expected=%h", beats_out, i,
                                      ref_p.data, m_tdata[i], exp_word(i, ref_p.data)));
                    if (m_tuser[i] !== ref_p.user || m_tlast[i] !== ref_p.last)
                        err($sformatf("beat %0d DUT %0d: sideband user/last got=%b/%b expected=%b/%b", beats_out, i,
                                      m_tuser[i], m_tlast[i], ref_p.user, ref_p.last));
                end
                if (lit_en && lit_q.size() > 0) begin
                    lit_w = lit_q.pop_front();
                    if (m_tdata[0] !== lit_w)
                        err($sformatf("beat %0d literal check: in=%h got=%h expected=%h", beats_out,
                                      ref_p.data, m_tdata[0], lit_w));
                end
                lat = cyc - ref_p.t_in;
                if (lat < lat_min) lat_min = lat;
                if (lat > lat_max) lat_max = lat;
                if (mon_en) begin
                    if (m_tuser[0]) u_idx.push_back(out_idx);
                    if (m_tlast[0]) l_idx.push_back(out_idx);
                    out_idx++;
                end
            end
            beats_out++;
        end
    end

    // ---------------- frame monitor (Test 7) ----------------
    // Counts geometry at the output of DUT 0: beats per line, lines, tusers,
    // tlasts, and the shortest idle stretch between lines.
    bit  frame_check = 0;
    bit  fm_after_last;     // the previous accepted beat was a tlast
    int  fm_beats, fm_lines, fm_users, fm_total, fm_idle, fm_min_hgap;

    always @(posedge aclk) begin
        if (frame_check && aresetn) begin
            if (m_tvalid[0] && m_axis_tready) begin
                // first beat of a line: idle stretch since the previous tlast
                if (fm_after_last && fm_idle < fm_min_hgap) fm_min_hgap = fm_idle;
                fm_after_last = 0;
                fm_idle       = 0;
                if (m_tuser[0]) fm_users++;
                fm_beats++;
                fm_total++;
                if (m_tlast[0]) begin
                    if (fm_beats != FULL_BEATS)
                        err($sformatf("line %0d had %0d beats, expected %0d", fm_lines, fm_beats, FULL_BEATS));
                    fm_lines++;
                    fm_beats      = 0;
                    fm_after_last = 1;
                end
            end else begin
                fm_idle++;
            end
        end
    end

    // ---------------- tests ----------------
    // Test 1 table: pixel = {R, B, G} (bits 23:16, 15:8, 7:0). DUT 0 has THR = 32.
    // grey values worked out by hand from 0.2989 R + 0.5870 G + 0.1140 B, rounded:
    //   1F1F1F -> 31, 202020 -> 32, 212121 -> 33     (equal channels, around THR)
    //   R=108 -> 32, R=109 -> 33; G=55 -> 32, G=56 -> 33
    //   B=255 alone -> 29 (blue alone can never reach 33)
    //   000000 -> 0, FFFFFF -> 255, G+B=255 -> 179, R=255 -> 76
    localparam logic [23:0] T1_PIX [12] = '{24'h1F1F1F, 24'h202020, 24'h212121,
                                           24'h6C0000, 24'h6D0000,
                                           24'h000037, 24'h000038,
                                           24'h00FF00, 24'h000000, 24'hFFFFFF,
                                           24'h00FFFF, 24'hFF0000};
    localparam bit          T1_EXP [12] = '{0, 0, 1,
                                           0, 1,
                                           0, 1,
                                           0, 0, 1,
                                           1, 1};

    bit          t2_b0, t2_b1;
    logic [23:0] sw_pix;
    logic [7:0]  sw_v;

    initial begin
        for (int i = 0; i < NCFG; i++) prev_stall[i] = 0;
        do_reset(5);

        // Test 1: known pixels with hand-computed grey values, in both pixels of
        // the beat. Literal expected values, DUT 0 (THR 32): only grey > 32 is 1.
        begin_test("Test 1: known pixels (grey just below / at / just above THR), literal expected bits");
        gap_pct = 0; stall_pct = 0; lit_en = 1;
        for (int k = 0; k < 12; k++) begin
            push_lit({24'h0, T1_PIX[k]}, {15'b0, T1_EXP[k]});          // pixel 0 -> bit 0
            push_lit({T1_PIX[k], 24'h0}, {7'b0, T1_EXP[k], 8'b0});     // pixel 1 -> bit 8
        end
        drain();
        end_test();

        // Test 2: per-pixel independence, all four combinations, DUT 0 literal.
        // Then a boundary sweep for every configuration against the model.
        begin_test("Test 2: per-pixel independence (4 combinations) + exhaustive byte sweep, all configs");
        for (int c = 0; c < 4; c++) begin
            t2_b0 = c[0];
            t2_b1 = c[1];
            push_lit({t2_b1 ? 24'h212121 : 24'h202020, t2_b0 ? 24'h212121 : 24'h202020},
                     {7'b0, t2_b1, 7'b0, t2_b0});
        end
        drain();
        lit_en = 0;
        // every value 0..255 of G, of B, of R, and of all three equal, in pixel 0,
        // in pixel 1, and in pixel 1 next to a random pixel 0: crosses every
        // configuration's grey boundary
        for (int pos = 0; pos < 4; pos++)
            for (int v = 0; v < 256; v++) begin
                sw_v   = 8'(v);
                sw_pix = 24'h0;
                if (pos == 3) sw_pix = {sw_v, sw_v, sw_v};
                else          sw_pix[pos * 8 +: 8] = sw_v;
                push_beat({24'h0, sw_pix}, 1'b0, 1'b0);
                push_beat({sw_pix, 24'h0}, 1'b0, 1'b0);
                push_beat({sw_pix, rand_pix()}, 1'b0, 1'b0);
            end
        drain();
        end_test();

        // Test 3: tuser on the first beat, tlast on the last beat of each line
        begin_test("Test 3: tuser / tlast stay on their beats");
        mon_en = 1; out_idx = 0; u_idx.delete(); l_idx.delete();
        queue_frame(3, 1);
        drain();
        mon_en = 0;
        if (u_idx.size() != 1 || u_idx[0] != 0)
            err($sformatf("tuser positions wrong: %0d seen, first at %0d", u_idx.size(), u_idx.size() > 0 ? u_idx[0] : -1));
        if (l_idx.size() != 3 || l_idx[0] != LINE_BEATS - 1 || l_idx[1] != 2 * LINE_BEATS - 1 || l_idx[2] != 3 * LINE_BEATS - 1)
            err($sformatf("tlast positions wrong: %0d seen", l_idx.size()));
        end_test();

        // Test 4: random gaps between input beats
        begin_test("Test 4: random input gaps (tvalid low between beats)");
        gap_pct = 50; stall_pct = 0;
        queue_frame(6, 1);
        drain();
        end_test();

        // Test 5: random output backpressure
        begin_test("Test 5: random m_axis_tready (no loss, duplication or change while stalled)");
        gap_pct = 20; stall_pct = 50;
        queue_frame(20, 1);
        drain();
        gap_pct = 0; stall_pct = 80;
        queue_frame(10, 0);
        drain();
        end_test();

        // Test 6: reset mid-line, then everything after it must be new
        begin_test("Test 6: reset mid-stream, nothing stale afterwards");
        gap_pct = 0; stall_pct = 30;
        queue_frame(2, 1);
        repeat (LINE_BEATS + 1) @(posedge aclk);    // part-way through line 1
        do_reset(3);
        queue_frame(2, 1);
        drain();
        end_test();

        // Test 7: one full 1920x1080 frame (960 beats/line, 1080 lines) at the
        // real 1 beat / 2 clocks rate with real blanking
        begin_test("Test 7: one full 1920x1080 frame, 960 beats/line, with blanking");
        gap_pct = 0; stall_pct = 0;
        frame_check = 1; fm_beats = 0; fm_lines = 0; fm_users = 0; fm_total = 0; fm_idle = 0; fm_after_last = 0;
        fm_min_hgap = '1 >> 1;
        queue_frame(FULL_LINES, 1, FULL_BEATS, 1, H_IDLE, V_IDLE);
        drain(FULL_LINES * (2 * FULL_BEATS + H_IDLE) + V_IDLE + 1000);
        frame_check = 0;
        if (fm_total != FULL_BEATS * FULL_LINES)
            err($sformatf("saw %0d beats, expected %0d", fm_total, FULL_BEATS * FULL_LINES));
        if (fm_users != 1)           err($sformatf("saw %0d tusers, expected 1", fm_users));
        if (fm_lines != FULL_LINES)  err($sformatf("saw %0d tlasts, expected %0d", fm_lines, FULL_LINES));
        if (fm_min_hgap < H_IDLE)    err($sformatf("line-to-line idle %0d cycles at the output, input gave >= %0d", fm_min_hgap, H_IDLE));
        $display("  beats %0d, tusers %0d, tlasts %0d, min line gap %0d clocks", fm_total, fm_users, fm_lines, fm_min_hgap);
        end_test();

        // Latency, measured over every accepted beat
        $display("Latency: min %0d, max %0d clocks", lat_min, lat_max);
        if (lat_min != lat_max)  err("latency is not fixed");
        if (lat_max != EXP_LAT)  err($sformatf("latency %0d clocks, testbench requires %0d", lat_max, EXP_LAT));

        if (errors == 0) $display("PASS: %0d beats checked on %0d configurations", beats_out, NCFG);
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
