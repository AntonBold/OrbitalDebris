`timescale 1ns / 1ps

// Self-checking verification environment for cca_top (parameterized core).
// Wrapper tops pick the frame size and vector file: cca_directed_tb,
// cca_random_tb, cca_wide_tb, cca_full_tb.
//
// Frames and expected results come from scripts/golden/cca_golden.py, an
// independent flood-fill model (see that file for the vector format). For
// each frame the environment drives it, waits for o_interrupt, and reads the
// BRAM the way the PS will: scan the three headers, take the newest by frame
// number, read count x 2 words. Results are compared with the golden model
// field by field.
//
// Always-on checkers (counted, never $error, which stops the simulation):
//   timing      no pixel while the TL is clearing or feature_extract is dumping
//   irq_width   o_interrupt is a single-cycle pulse
//   bram_*      writes stay in the active slot; header written last
//               (cca_bram_model)
//   fifo_*      line buffer: no write when full (without a read), no read
//               when empty
//   label_wrap  label 0 (background) is never handed out as a new label
//   label_count labels used per frame == golden count of provisional labels
//   trdy        o_trdy is high whenever rst is low
//   xz          no X/Z on outputs after reset (4-state simulators only)
//   ps_empty    after reset, the PS reader sees no frame
//   slot_kept   a slot is not modified after its interrupt (slow reader)
//
// Plusargs:
//   +vectors=<file>   vector file (default from the wrapper)
//   +seed=<n>         seed for gap patterns (printed)
//   +selftest=<name>  inject a fault so one checker must fire (see below)
//   +dump             VCD of the whole environment
//   +dump_scope=dut|decision|fe   VCD of one scope only
//   +dump_test=<idx>  VCD only while test <idx> runs
//   +verbose          print every test's header line
//
// Self-tests (each must make the run FAIL, proving the checker can fail):
//   data stim bram_oob hdr_order irq_width fifo timing label_count ps_empty

module cca_env_tb #(
    parameter int    W           = 64,
    parameter int    H           = 48,
    parameter int    NUM_LABELS  = 1024,
    parameter string VEC_DEFAULT = "vectors/cca_directed.txt"
);

    localparam int SLOT_WORDS  = 32'h804 / 4;
    localparam int MAX_CENT    = 256;
    localparam int IRQ_TIMEOUT = 2 * NUM_LABELS + 2 * 512 + 2000;
    localparam int INFO_WINDOW = 3 * IRQ_TIMEOUT;

    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;

    logic [7:0]  tdata;
    logic        tvalid, tuser, tlast, trdy;
    logic        interrupt;
    logic [31:0] bram_addr, bram_wdata;
    logic [3:0]  bram_we;
    logic        bram_en;

    axis_frame_driver #(.W(W), .H(H)) drv (
        .clk(clk), .tdata(tdata), .tvalid(tvalid), .tuser(tuser), .tlast(tlast)
    );

    cca_top #(.NUM_LABELS(NUM_LABELS), .ROW_SIZE(W), .COL_SIZE(H)) dut (
        .clk(clk), .rst(rst),
        .i_tdata(tdata), .i_tvalid(tvalid), .i_tuser(tuser), .i_tlast(tlast),
        .o_trdy(trdy), .o_interrupt(interrupt),
        .o_bram_addr(bram_addr), .o_bram_wdata(bram_wdata),
        .o_bram_we(bram_we), .o_bram_en(bram_en), .o_bram_clk()
    );

    // ------------------------------------------------------------------
    // Self-test fault injection on the path into the BRAM model / checkers
    // ------------------------------------------------------------------
    string selftest = "";
    bit    inj_oob_armed = 0, inj_hdr_armed = 0, inj_irq_armed = 0;
    bit    inj_extra_write = 0, inj_extra_irq = 0;
    logic        m_en, m_irq;
    logic [3:0]  m_we;
    logic [31:0] m_addr, m_wdata;

    always_comb begin
        m_en    = bram_en;
        m_we    = bram_we;
        m_addr  = bram_addr;
        m_wdata = bram_wdata;
        m_irq   = interrupt | inj_extra_irq;
        if (inj_oob_armed && bram_en && bram_we == 4'hF && bram_addr % 32'h804 == 4)
            m_addr = bram_addr + 32'h804;          // first centroid word, wrong slot
        if (inj_extra_write) begin
            m_en  = 1'b1;
            m_we  = 4'hF;
            m_addr = bram.exp_slot * 32'h804 + 4;  // a write after the header
            m_wdata = '0;
        end
    end

    always @(posedge clk) begin
        if (inj_extra_write) begin inj_extra_write <= 0; inj_hdr_armed <= 0; end
        else if (inj_hdr_armed && bram_en && bram_we == 4'hF && bram_addr % 32'h804 == 0)
            inj_extra_write <= 1;
        if (inj_extra_irq) begin inj_extra_irq <= 0; inj_irq_armed <= 0; end
        else if (inj_irq_armed && interrupt) inj_extra_irq <= 1;
        if (inj_oob_armed && bram_en && bram_we == 4'hF && bram_addr % 32'h804 == 4)
            inj_oob_armed <= 0;
    end

    cca_bram_model bram (
        .clk(clk), .rst(rst), .irq(m_irq),
        .en(m_en), .we(m_we), .addr(m_addr), .wdata(m_wdata)
    );

    // ------------------------------------------------------------------
    // Always-on checkers
    // ------------------------------------------------------------------
    int err_timing = 0, err_irq_width = 0, err_fifo_full = 0, err_fifo_empty = 0;
    int err_label_wrap = 0, err_label_count = 0, err_trdy = 0, err_xz = 0;
    int err_ps_empty = 0, err_slot_kept = 0;

    // Errors raised by the always-on checkers, attributed to whichever test
    // is being driven when they fire. (slot_kept and label_count are raised
    // inside a frame's own check and counted against that frame directly.)
    function automatic int total_errors();
        return err_timing + err_irq_width + err_fifo_full + err_fifo_empty + err_label_wrap
             + err_trdy + err_xz + err_ps_empty
             + bram.oob_errors + bram.order_errors + bram.partial_we;
    endfunction

    always @(posedge clk) begin
        if (!rst && tvalid && (dut.decision_top.tl.state != 0 || dut.fe.state != 0)) begin
            err_timing++;
            $display("[%0t] CHECK timing: pixel while busy (tl.state=%0d fe.state=%0d)",
                     $time, dut.decision_top.tl.state, dut.fe.state);
        end
    end

    int irq_len = 0;
    always @(posedge clk) begin
        if (rst) irq_len = 0;
        else if (m_irq) begin
            irq_len++;
            if (irq_len == 2) begin
                err_irq_width++;
                $display("[%0t] CHECK irq_width: interrupt high for more than 1 cycle", $time);
            end
        end else irq_len = 0;
    end

    always @(posedge clk) begin
        if (!rst && !dut.control_fe_frame_done) begin
            if (dut.decision_top.north_label_buffer.i_data_valid && dut.decision_top.north_label_buffer.o_full &&
                !(dut.decision_top.north_label_buffer.i_rd_data && !dut.decision_top.north_label_buffer.o_empty)) begin
                err_fifo_full++;
                $display("[%0t] CHECK fifo_full: line buffer written while full (write dropped)", $time);
            end
            if (dut.decision_top.north_label_buffer.i_rd_data && dut.decision_top.north_label_buffer.o_empty) begin
                err_fifo_empty++;
                $display("[%0t] CHECK fifo_empty: line buffer read while empty", $time);
            end
        end
    end

    // Label 0 is background; handing it out means the 10-bit counter wrapped.
    // (new_label > NUM_LABELS-1 can't happen in a $clog2(NUM_LABELS)-bit
    // counter, so the meaningful check is the wrap.)
    always @(posedge clk) begin
        if (!rst && dut.decision_top.decision_block.inc_new_label &&
            dut.decision_top.decision_block.new_label == 0) begin
            err_label_wrap++;
            if (err_label_wrap <= 3)
                $display("[%0t] CHECK label_wrap: label 0 handed out as a new label (more than %0d labels in a frame)",
                         $time, NUM_LABELS - 1);
        end
    end

    // Labels used by the frame, sampled on the frame_done edge (the last
    // pixel's increment happens on that same edge)
    int labels_used = 0;
    always @(posedge clk) begin
        if (!rst && dut.control_fe_frame_done)
            labels_used = (int'(dut.decision_top.decision_block.new_label) - 1
                        + int'(dut.decision_top.decision_block.inc_new_label) + NUM_LABELS) % NUM_LABELS;
    end

    always @(posedge clk) begin
        if (!rst && trdy !== 1'b1) begin
            err_trdy++;
            $display("[%0t] CHECK trdy: o_trdy low while not in reset", $time);
        end
        if (!rst && $isunknown({trdy, interrupt, bram_addr, bram_wdata, bram_we, bram_en})) begin
            err_xz++;
            $display("[%0t] CHECK xz: X/Z on a cca_top output", $time);
        end
    end

    // Interrupt events, counted on the falling edge so the reader runs while
    // the pulse is high (the header must already be readable then)
    int  irq_count = 0;
    logic irq_q = 0;
    always @(negedge clk) begin
        if (m_irq && !irq_q) begin irq_count++; cov_ev["irq"]++; end
        irq_q = m_irq;
    end

    // ------------------------------------------------------------------
    // Coverage
    // ------------------------------------------------------------------
    int cov_class[string];
    int cov_ev[string];
    string ev_names[$] = '{"tl_collision", "fe_merge", "merge_same_root_2nd_hop", "doe_forward",
                           "fifo_full_read_write", "gap_cycle", "slot_wrap", "reset", "irq",
                           "frames_driven", "frames_aborted"};
    always @(posedge clk) begin
        if (!rst) begin
            if (dut.decision_top.lut_we) cov_ev["tl_collision"]++;
            if (dut.decision_top.lut_we && dut.fe.state == 0) begin
                if (dut.dec_fe_valid_coll) cov_ev["fe_merge"]++;
                else cov_ev["merge_same_root_2nd_hop"]++;
            end
            if (dut.decision_top.lut_we && dut.decision_top.lut_addrd == dut.decision_top.reg_label &&
                dut.decision_top.reg_valid)
                cov_ev["doe_forward"]++;
            if (dut.decision_top.north_label_buffer.i_data_valid && dut.decision_top.north_label_buffer.o_full &&
                dut.decision_top.north_label_buffer.i_rd_data)
                cov_ev["fifo_full_read_write"]++;
            if (drv.in_frame && !tvalid) cov_ev["gap_cycle"]++;
        end
    end

    // ------------------------------------------------------------------
    // Expected-frame bookkeeping
    // ------------------------------------------------------------------
    logic [22:0] fnum_force_val;
    int gen = 0;              // bumped on every reset
    int irq_base = 0;         // irq_count at the last reset
    int irq_expected = 0;     // interrupts expected since the last reset
    int fn_next = 1;          // next expected frame number
    int slot_next = 0;        // next expected slot
    int frames_since_reset = 0;

    logic [31:0] slot_snap [0:2][0:SLOT_WORDS-1];
    bit          slot_snap_valid [0:2];

    // per-test results
    string t_name[$], t_tag[$], t_note[$];
    int    t_mism[$], t_errs[$], t_timing[$], t_err0[$], t_timing0[$];
    bit    t_done[$];
    int    n_tests = 0;
    int    bg_pending = 0;

    function automatic void note(int idx, string s);
        if (t_note[idx] == "") t_note[idx] = s;
        else t_note[idx] = {t_note[idx], "; ", s};
    endfunction

    // Read the three headers like the PS: newest by frame number (first one
    // wins on a tie)
    function automatic int ps_newest_slot();
        int slot = 0;
        logic [22:0] best = 0;
        for (int s = 0; s < 3; s++) begin
            logic [31:0] hdr = bram.mem[s * SLOT_WORDS];
            if (s == 0 || hdr[31:9] > best) begin best = hdr[31:9]; slot = s; end
        end
        return slot;
    endfunction

    function automatic int compare_frame(int idx, int exp_fn, int exp_slot, int exp_count,
                                         int ex[$], int ey[$], int ea[$], bit quiet);
        int mism = 0, slot, count;
        logic [31:0] hdr;
        string nm = t_name[idx];
        slot  = ps_newest_slot();
        hdr   = bram.mem[slot * SLOT_WORDS];
        count = hdr[8:0];
        if (slot != exp_slot) begin
            mism++;
            if (!quiet && mism <= 8) $display("  MISMATCH %s: PS reader picked slot %0d, PL should have written slot %0d",
                                 nm, slot, exp_slot);
        end
        if (hdr[31:9] != exp_fn[22:0]) begin
            mism++;
            if (!quiet && mism <= 8) $display("  MISMATCH %s slot %0d header.frame_number: exp 0x%0h act 0x%0h",
                                 nm, slot, exp_fn, hdr[31:9]);
        end
        if (count != exp_count) begin
            mism++;
            if (!quiet && mism <= 8) $display("  MISMATCH %s slot %0d header.count: exp %0d act %0d", nm, slot, exp_count, count);
        end
        for (int i = 0; i < ex.size() || (i < count && i < MAX_CENT); i++) begin
            logic [31:0] a1, a2;
            if (i >= MAX_CENT) break;
            a1 = bram.mem[slot * SLOT_WORDS + 1 + 2 * i];
            a2 = bram.mem[slot * SLOT_WORDS + 2 + 2 * i];
            if (i >= ex.size()) begin
                mism++;
                if (!quiet && mism <= 8) $display("  EXTRA    %s slot %0d obj %0d: x_sum=%0d y_sum=%0d area=%0d valid=%0d",
                                     nm, slot, i, a1, a2[31:10], a2[9:1], a2[0]);
            end else if (i >= count) begin
                mism++;
                if (!quiet && mism <= 8) $display("  MISSING  %s slot %0d obj %0d: exp x_sum=%0d y_sum=%0d area=%0d",
                                     nm, slot, i, ex[i], ey[i], ea[i]);
            end else begin
                if (longint'(a1) != longint'(ex[i])) begin
                    mism++;
                    if (!quiet && mism <= 8) $display("  MISMATCH %s slot %0d obj %0d x_sum: exp %0d act %0d", nm, slot, i, ex[i], a1);
                end
                if (int'(a2[31:10]) != ey[i]) begin
                    mism++;
                    if (!quiet && mism <= 8) $display("  MISMATCH %s slot %0d obj %0d y_sum: exp %0d act %0d (22-bit field)",
                                         nm, slot, i, ey[i], a2[31:10]);
                end
                if (int'(a2[9:1]) != ea[i]) begin
                    mism++;
                    if (!quiet && mism <= 8) $display("  MISMATCH %s slot %0d obj %0d area: exp %0d act %0d (9-bit field)",
                                         nm, slot, i, ea[i], a2[9:1]);
                end
                if (a2[0] !== 1'b1) begin
                    mism++;
                    if (!quiet && mism <= 8) $display("  MISMATCH %s slot %0d obj %0d valid: exp 1 act 0", nm, slot, i);
                end
            end
        end
        if (!quiet && mism > 8) $display("  ... %0d more mismatch(es) in %s not shown", mism - 8, nm);
        return mism;
    endfunction

    // Slots written by earlier frames must not change after their interrupt
    // (a PS that reads late still gets that frame intact)
    function automatic int check_and_snapshot(int idx, int exp_slot);
        int errs = 0;
        for (int s = 0; s < 3; s++) begin
            if (s == exp_slot || !slot_snap_valid[s]) continue;
            for (int i = 0; i < SLOT_WORDS; i++) begin
                if (bram.mem[s * SLOT_WORDS + i] !== slot_snap[s][i]) begin
                    err_slot_kept++;
                    errs++;
                    $display("  CHECK slot_kept (%s): slot %0d word %0d changed after its interrupt",
                             t_name[idx], s, i);
                    slot_snap_valid[s] = 0;     // report each corruption once
                    break;
                end
            end
        end
        for (int i = 0; i < SLOT_WORDS; i++) slot_snap[exp_slot][i] = bram.mem[exp_slot * SLOT_WORDS + i];
        slot_snap_valid[exp_slot] = 1;
        return errs;
    endfunction

    // Wait for interrupt number <seq> (since reset <gen0>) and compare
    task automatic check_frame(int idx, int seq, int gen0, int exp_fn, int exp_slot, int exp_count,
                               int ex[$], int ey[$], int ea[$], int exp_labels, bit check_labels);
        int waited = 0, mism = 0;
        while ((irq_count - irq_base) < seq && waited < IRQ_TIMEOUT && gen == gen0) begin
            @(negedge clk);
            waited++;
        end
        if (gen != gen0) begin
            mism++;
            note(idx, "cancelled by a reset before its interrupt");
        end else if ((irq_count - irq_base) < seq) begin
            mism++;
            $display("  TIMEOUT  %s: no interrupt within %0d cycles of the frame's last pixel",
                     t_name[idx], IRQ_TIMEOUT);
        end else begin
            mism += compare_frame(idx, exp_fn, exp_slot, exp_count, ex, ey, ea, 0);
            mism += check_and_snapshot(idx, exp_slot);
            if (check_labels && labels_used != exp_labels) begin
                err_label_count++;
                mism++;
                $display("  CHECK label_count (%s): RTL used %0d labels, golden raster count %0d",
                         t_name[idx], labels_used, exp_labels);
            end
        end
        t_mism[idx] += mism;
        t_done[idx] = 1;
    endtask

    task automatic bg_check(int idx, int seq, int gen0, int exp_fn, int exp_slot, int exp_count,
                            int ex[$], int ey[$], int ea[$], int exp_labels, bit check_labels);
        bg_pending++;
        check_frame(idx, seq, gen0, exp_fn, exp_slot, exp_count, ex, ey, ea, exp_labels, check_labels);
        bg_pending--;
    endtask

    // ------------------------------------------------------------------
    // Reset and frame-gap helpers
    // ------------------------------------------------------------------
    // mode: "min" = first legal cycle after TL init, "min-1" = one cycle early,
    // otherwise a number of idle cycles after reset release
    task automatic do_reset(string mode);
        int waited = 0;
        while (bg_pending > 0 && waited < IRQ_TIMEOUT) begin drv.idle(1); waited++; end
        rst = 1'b1;
        drv.idle(4);
        gen++;
        irq_base = irq_count;
        irq_expected = 0;
        fn_next = 1;
        slot_next = 0;
        frames_since_reset = 0;
        for (int s = 0; s < 3; s++) slot_snap_valid[s] = 0;
        cov_ev["reset"]++;
        rst = 1'b0;
        if (mode == "min") begin
            while (dut.decision_top.tl.state != 0 || dut.fe.state != 0) drv.idle(1);
        end else if (mode == "min-1") begin
            while (dut.decision_top.tl.reset_counter != NUM_LABELS - 1) drv.idle(1);
        end else begin
            drv.idle(mode.atoi());
        end
        // A reader that runs before any frame exists must see none
        if (selftest == "ps_empty" && gen == 1) bram.mem[0] = 32'hDEAD_BEEF;
        for (int s = 0; s < 3; s++) begin
            if (bram.mem[s * SLOT_WORDS] != 0) begin
                err_ps_empty++;
                $display("  CHECK ps_empty: header of slot %0d is 0x%08h after reset (expected no frame)",
                         s, bram.mem[s * SLOT_WORDS]);
            end
        end
    endtask

    // Wait until feature_extract starts its dump, then until the design is
    // idle again (min) or one cycle before (min-1)
    task automatic wait_ifg(string mode);
        int waited = 0;
        while (dut.fe.state == 0 && waited < 16) begin drv.idle(1); waited++; end
        if (mode == "min-1") begin
            while (dut.fe.state != 6) drv.idle(1);            // S_done: last busy cycle
        end else begin
            while (dut.fe.state != 0 || dut.decision_top.tl.state != 0) drv.idle(1);
        end
    endtask

    // ------------------------------------------------------------------
    // Vector parsing helpers
    // ------------------------------------------------------------------
    function automatic void split(string s, ref string toks[$]);
        string cur = "";
        toks.delete();
        for (int i = 0; i < s.len(); i++) begin
            if (s[i] == " " || s[i] == "\n" || s[i] == "\r" || s[i] == "\t") begin
                if (cur != "") toks.push_back(cur);
                cur = "";
            end else cur = {cur, s[i]};
        end
        if (cur != "") toks.push_back(cur);
    endfunction

    function automatic void split_char(string s, byte c, ref string toks[$]);
        string cur = "";
        toks.delete();
        for (int i = 0; i < s.len(); i++) begin
            if (s[i] == c) begin toks.push_back(cur); cur = ""; end
            else cur = {cur, s[i]};
        end
        toks.push_back(cur);
    endfunction

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    initial begin
        string path, line, tag, flags, cls, name, toks[$], kv[$], parts[$];
        string opt[string];
        int fd, exp_count, nlabels, seed, dump_test, idx;
        int ex[$], ey[$], ea[$];
        bit aborted, info, check_labels;
        int stim_done = 0, data_done = 0;

        if (!$value$plusargs("vectors=%s", path)) path = VEC_DEFAULT;
        if (!$value$plusargs("seed=%d", seed)) seed = 1;
        void'($value$plusargs("selftest=%s", selftest));
        if (!$value$plusargs("dump_test=%d", dump_test)) dump_test = -1;
        drv.set_seed(seed);
        $display("cca_env_tb: %0dx%0d, vectors %s, seed %0d%s", W, H, path, seed,
                 selftest != "" ? {", SELFTEST ", selftest} : "");

        if ($test$plusargs("dump") || dump_test >= 0) begin
            string scope;
            $dumpfile("dump.vcd");
            if (!$value$plusargs("dump_scope=%s", scope)) scope = "all";
            if (scope == "dut") $dumpvars(0, dut);
            else if (scope == "decision") $dumpvars(0, dut.decision_top);
            else if (scope == "fe") $dumpvars(0, dut.fe);
            else $dumpvars;
            if (dump_test >= 0) $dumpoff;
        end

        foreach (ev_names[i]) cov_ev[ev_names[i]] = 0;
        if (selftest == "bram_oob")  inj_oob_armed = 1;
        if (selftest == "hdr_order") inj_hdr_armed = 1;
        if (selftest == "irq_width") inj_irq_armed = 1;

        fd = $fopen(path, "r");
        if (fd == 0) $fatal(1, "cannot open vector file %s", path);

        do_reset(selftest == "timing" ? "min-1" : "min");

        while ($fgets(line, fd)) begin
            if (line.len() == 0) continue;
            if (line[0] == "K") begin
                split(line, toks);
                for (int i = 1; i < toks.size(); i++) cov_class[toks[i]] = 0;
                continue;
            end
            if (line[0] != "T") continue;

            // T name tag count flags nlabels classes
            split(line, toks);
            if (toks.size() != 7) $fatal(1, "bad test header: %s", line);
            name = toks[1]; tag = toks[2]; exp_count = toks[3].atoi(); flags = toks[4];
            nlabels = toks[5].atoi(); cls = toks[6];
            // O options
            void'($fgets(line, fd));
            split(line, toks);
            opt.delete();
            for (int i = 1; i < toks.size(); i++) begin
                if (toks[i] == "-") continue;
                split_char(toks[i], "=", kv);
                opt[kv[0]] = kv[1];
            end
            for (int row = 0; row < H; row++) begin
                void'($fgets(line, fd));
                if (line[0] != "R" || line.len() < W + 2) $fatal(1, "bad row %0d in %s", row, name);
                for (int x = 0; x < W; x++) drv.pix[row][x] = (line[2 + x] == "1");
            end
            ex.delete(); ey.delete(); ea.delete();
            for (int i = 0; i < exp_count; i++) begin
                void'($fgets(line, fd));
                split(line, toks);
                if (toks.size() != 4 || toks[0] != "C") $fatal(1, "bad centroid line in %s", name);
                ex.push_back(toks[1].atoi()); ey.push_back(toks[2].atoi()); ea.push_back(toks[3].atoi());
            end

            idx = n_tests++;
            t_name.push_back(name); t_tag.push_back(tag); t_note.push_back("");
            t_mism.push_back(0); t_errs.push_back(0); t_timing.push_back(0); t_done.push_back(0);
            if ($test$plusargs("verbose")) $display("TEST  %0d %s [%s] count=%0d labels=%0d", idx, name, tag, exp_count, nlabels);
            split_char(cls, ",", parts);
            foreach (parts[i]) if (parts[i] != "-") cov_class[parts[i]]++;
            info = (tag == "INFO");

            // ---- before the frame -------------------------------------------
            if (opt.exists("rst_before")) do_reset(opt["rst_before"]);
            if (opt.exists("fnum")) begin
                automatic int v = opt["fnum"].atoi();
                // force's right-hand side must be static (Questa enforces this)
                fnum_force_val = 23'(v - 1);
                force dut.controller.frame_count = fnum_force_val;
                drv.idle(1);
                release dut.controller.frame_count;
                fn_next = v;
            end

            t_err0.push_back(total_errors());
            t_timing0.push_back(err_timing);
            if (idx == dump_test) $dumpon;

            // ---- self-test stimulus faults ------------------------------------
            if (selftest == "data" && !data_done && ex.size() > 0 && tag == "-") begin
                $display("NOTE  selftest data: wrong expected x_sum for %s", name);
                ex[0] = ex[0] + 1;
                data_done = 1;
            end
            if (selftest == "stim" && !stim_done && tag == "-" && !drv.pix[H/2][W/2] &&
                !drv.pix[H/2-1][W/2] && !drv.pix[H/2+1][W/2] && !drv.pix[H/2][W/2-1] && !drv.pix[H/2][W/2+1]) begin
                $display("NOTE  selftest stim: extra foreground pixel driven in %s", name);
                drv.pix[H/2][W/2] = 1;
                stim_done = 1;
            end
            if (selftest == "label_count" && idx == 0) nlabels++;
            if (selftest == "fifo" && idx == 0)
                fork begin
                    @(negedge clk);
                    force dut.decision_top.north_label_buffer.i_rd_data = 1'b1;
                    @(negedge clk);
                    release dut.decision_top.north_label_buffer.i_rd_data;
                end join_none

            // ---- drive ----------------------------------------------------------
            drv.clear_knobs();
            if (opt.exists("gap")) drv.gap_pct = opt["gap"].atoi();
            if (opt.exists("rst_at_pixel")) drv.abort_at = opt["rst_at_pixel"].atoi();
            if (opt.exists("malform")) begin
                split_char(opt["malform"], ":", parts);
                case (parts[0])
                    "missing_tlast": drv.drop_tlast_row = parts[1].atoi();
                    "extra_tlast":   begin drv.extra_tlast_row = parts[1].atoi(); drv.extra_tlast_x = parts[2].atoi(); end
                    "missing_tuser": drv.no_tuser = 1;
                    "rows":          drv.rows = parts[1].atoi();
                    "line_len":      begin drv.len_row = parts[1].atoi(); drv.len_val = parts[2].atoi(); end
                    default:         $fatal(1, "unknown malform %s", opt["malform"]);
                endcase
            end
            check_labels = !info && !opt.exists("malform") && selftest != "timing";
            cov_ev["frames_driven"]++;
            drv.send_frame(aborted);
            frames_since_reset++;

            // ---- after the frame ------------------------------------------------
            if (aborted) begin
                // Reset mid-frame: this frame must never interrupt
                automatic int irq0 = irq_count;
                cov_ev["frames_aborted"]++;
                do_reset("min");
                if (irq_count != irq0) begin t_mism[idx]++; note(idx, "interrupt from an aborted frame"); end
                t_done[idx] = 1;
            end else if (info) begin
                // Out of contract: watch for a while and report what happened
                automatic int irq0 = irq_count;
                automatic int got;
                drv.idle(INFO_WINDOW);
                got = irq_count - irq0;
                if (got == 0) note(idx, "no interrupt");
                else begin
                    automatic int slot = ps_newest_slot();
                    automatic logic [31:0] hdr = bram.mem[slot * SLOT_WORDS];
                    automatic int m = compare_frame(idx, hdr[31:9], slot, exp_count, ex, ey, ea, 1);
                    note(idx, $sformatf("%0d interrupt(s); newest header frame %0d count %0d (golden %0d); %s",
                                        got, hdr[31:9], hdr[8:0], exp_count,
                                        m == 0 ? "data matches golden" : $sformatf("%0d field(s) differ from golden", m)));
                end
                t_done[idx] = 1;
            end else if (opt.exists("rst_after")) begin
                // Reset during the dump: no interrupt for this frame
                automatic int irq0 = irq_count;
                drv.idle(opt["rst_after"].atoi());
                if (irq_count != irq0) begin t_mism[idx]++; note(idx, "interrupt arrived before the injected reset"); end
                do_reset("min");
                t_done[idx] = 1;
            end else begin
                // automatic copies: a forked check must keep this frame's values
                automatic int seq, efn, eslot, cidx = idx, cnl = nlabels, ccount = exp_count;
                automatic int cx[$] = ex, cy[$] = ey, ca[$] = ea;
                automatic bit cchk = check_labels;
                seq = ++irq_expected;
                efn = fn_next;
                fn_next = (fn_next + 1) & 32'h7F_FFFF;
                eslot = slot_next;
                if (slot_next == 2) cov_ev["slot_wrap"]++;
                slot_next = (slot_next + 1) % 3;
                if (opt.exists("ifg")) begin
                    fork
                        bg_check(cidx, seq, gen, efn, eslot, ccount, cx, cy, ca, cnl, cchk);
                    join_none
                    wait_ifg(opt["ifg"]);
                end else begin
                    check_frame(idx, seq, gen, efn, eslot, exp_count, ex, ey, ea, nlabels, check_labels);
                    if (opt.exists("rst_after_irq")) begin
                        drv.idle(opt["rst_after_irq"].atoi());
                        do_reset("min");
                    end else begin
                        drv.idle(16);
                    end
                end
            end
            if (idx == dump_test) $dumpoff;
        end
        $fclose(fd);

        // let background checks finish
        begin
            int waited = 0;
            while (bg_pending > 0 && waited < IRQ_TIMEOUT) begin drv.idle(1); waited++; end
        end
        drv.idle(16);
        report();
    end

    // ------------------------------------------------------------------
    // Results
    // ------------------------------------------------------------------
    task automatic report();
        int n_pass = 0, n_fail = 0, n_xfail = 0, n_xpass = 0, n_info = 0, fd;
        int errs, tim;
        string res;
        $display("");
        $display("==================== RESULTS ====================");
        // Checker errors before the first test (initial reset, empty-BRAM
        // read) belong to no test window, so count them here
        begin
            int pre = (n_tests > 0) ? t_err0[0] : total_errors();
            if (pre > 0) begin
                n_fail++;
                $display("FAIL  -  startup (%0d checker error(s) during the initial reset)", pre);
            end
        end
        for (int i = 0; i < n_tests; i++) begin
            int e1 = (i + 1 < n_tests) ? t_err0[i + 1] : total_errors();
            int t1 = (i + 1 < n_tests) ? t_timing0[i + 1] : err_timing;
            errs = e1 - t_err0[i];
            tim  = t1 - t_timing0[i];
            if (t_tag[i] == "INFO") begin
                n_info++;
                $display("INFO  %0d %s: %s", i, t_name[i], t_note[i]);
            end else if (t_tag[i] == "EXPECT_TIMING") begin
                if (tim > 0) begin
                    n_pass++;
                    $display("PASS  %0d %s (timing checker fired %0d time(s); data %s)", i, t_name[i], tim,
                             t_mism[i] == 0 ? "still correct" : "corrupted");
                end else begin
                    n_fail++;
                    $display("FAIL  %0d %s (pixel arrived early but the timing checker did not fire)", i, t_name[i]);
                end
            end else begin
                bit ok = (t_mism[i] == 0 && errs == 0 && t_done[i]);
                res = $sformatf("%0d mismatch(es), %0d checker error(s)%s", t_mism[i], errs,
                                t_note[i] != "" ? {"; ", t_note[i]} : "");
                if (t_tag[i] == "-") begin
                    if (ok) begin n_pass++; $display("PASS  %0d %s", i, t_name[i]); end
                    else begin n_fail++; $display("FAIL  %0d %s (%s)", i, t_name[i], res); end
                end else begin
                    if (ok) begin n_xpass++; $display("XPASS %0d %s [%s] expected to fail but passed", i, t_name[i], t_tag[i]); end
                    else begin n_xfail++; $display("XFAIL %0d %s [%s] (%s)", i, t_name[i], t_tag[i], res); end
                end
            end
        end

        $display("");
        $display("==================== CHECKERS ====================");
        $display("  timing=%0d irq_width=%0d bram_oob=%0d bram_order=%0d bram_partial_we=%0d",
                 err_timing, err_irq_width, bram.oob_errors, bram.order_errors, bram.partial_we);
        $display("  fifo_full=%0d fifo_empty=%0d label_wrap=%0d label_count=%0d trdy=%0d xz=%0d ps_empty=%0d slot_kept=%0d",
                 err_fifo_full, err_fifo_empty, err_label_wrap, err_label_count, err_trdy, err_xz,
                 err_ps_empty, err_slot_kept);
`ifdef VERILATOR
        $display("  (xz checker is inert here: this simulator is 2-state)");
`endif
        $display("");
        $display("==================== COVERAGE ====================");
        foreach (cov_class[k])
            $display("  %-28s %6d%s", k, cov_class[k], cov_class[k] == 0 ? "   <-- NOT COVERED" : "");
        $display("  -- events --");
        foreach (cov_ev[k])
            $display("  %-28s %6d%s", k, cov_ev[k], cov_ev[k] == 0 ? "   <-- never seen" : "");
        $display("");
        $display("==================== SUMMARY ====================");
        $display("  PASS  %0d", n_pass);
        $display("  FAIL  %0d", n_fail);
        $display("  XFAIL %0d (known issues / accepted limitations)", n_xfail);
        $display("  XPASS %0d (expected-fail tests that passed: update the tag)", n_xpass);
        $display("  INFO  %0d (out-of-contract stimulus, reported only)", n_info);
        $display("=================================================");
        fd = $fopen("tb_status.txt", "w");
        $fdisplay(fd, (n_fail + n_xpass > 0) ? "FAIL" : "PASS");
        $fclose(fd);
        if (n_fail + n_xpass > 0) $fatal(1, "unexpected results: %0d FAIL, %0d XPASS", n_fail, n_xpass);
        $finish;
    endtask

endmodule
