`timescale 1ns / 1ps

// Core of the pattern_gen moving-object tests (wrappers: pattern_gen_move_tb,
// pattern_gen_move_full_tb).
//
// pattern_gen (MOVE_ENABLE=1, one frame per enable pulse, as behind the
// button) -> cca_top -> BRAM model. After each frame's interrupt, read the
// frame's slot like the PS does and check:
//   - the header: frame number and 4 objects (3 static shapes + the mover)
//   - one entry is the mover, with area and sums at the position this
//     testbench expects (its own copy of the step / jump-back rule)
//   - the other 3 entries are the same every frame (the static shapes)

module pattern_gen_move_env #(
    parameter int W = 64, H = 48,
    parameter int O1X = 5,  O1Y = 5,            // static square 1
    parameter int O2X = 30, O2Y = 20,           // static square 2
    parameter int CX = 40,  CY = 30,            // static U shape
    parameter int MX = 2,   MY = 40,            // mover start
    parameter int MS = 3,                       // mover size
    parameter int DX = 20,  DY = 0,             // mover step per frame
    parameter int FRAMES = 6,
    parameter int NUM_LABELS = 256
);

    localparam int SLOT_WORDS = 513;

    logic clk = 0;
    always #5 clk = ~clk;

    logic rst = 1, en = 0;
    logic [7:0] tdata;
    logic tvalid, tuser, tlast, trdy, irq;
    logic [31:0] addr, wdata;
    logic [3:0] we;
    logic bram_en;

    pattern_gen #(
        .WIDTH(W), .HEIGHT(H),
        .OBJ1_X_START(O1X), .OBJ1_Y_START(O1Y),
        .OBJ2_X_START(O2X), .OBJ2_Y_START(O2Y),
        .COLL_X_START(CX), .COLL_Y_START(CY),
        .MOVE_ENABLE(1), .MOVE_X_START(MX), .MOVE_Y_START(MY),
        .MOVE_SIZE(MS), .MOVE_DX(DX), .MOVE_DY(DY),
        .NUM_FRAMES(1)
    ) pg (
        .i_clk(clk), .i_rst(rst), .i_enable(en),
        .m_axis_tdata(tdata), .m_axis_tvalid(tvalid), .m_axis_tuser(tuser), .m_axis_tlast(tlast));

    cca_top #(.NUM_LABELS(NUM_LABELS), .ROW_SIZE(W), .COL_SIZE(H)) cca (
        .clk(clk), .rst(rst), .i_tdata(tdata), .i_tvalid(tvalid), .i_tuser(tuser), .i_tlast(tlast),
        .o_trdy(trdy), .o_interrupt(irq), .o_bram_addr(addr), .o_bram_wdata(wdata), .o_bram_we(we),
        .o_bram_en(bram_en), .o_bram_clk());

    logic [31:0] bram [0:3*SLOT_WORDS-1];
    always @(posedge clk)
        if (bram_en && we == 4'hF) bram[addr >> 2] <= wdata;

    int errors = 0;

    // Mover sums for a MS x MS square with top-left (x, y)
    function automatic int sq_sum(int p);
        return MS * (MS * p + MS * (MS - 1) / 2);
    endfunction

    initial begin
        int mx = MX, my = MY;
        int static_w1[3], static_w2[3];
        int nstatic;

        repeat (5) @(negedge clk);
        rst = 0;
        repeat (4 * NUM_LABELS + 100) @(negedge clk);      // TL / feature table clear after reset

        for (int f = 1; f <= FRAMES; f++) begin
            int base, hdr, count, found;
            int ns;

            wait (!pg.active_frame);                        // pattern_gen ignores i_enable while blanking
            @(negedge clk) en = 1;                          // one debounced button press
            @(negedge clk) en = 0;
            @(posedge irq);
            repeat (2) @(negedge clk);

            base = ((f - 1) % 3) * SLOT_WORDS;
            hdr = bram[base];
            count = hdr & 'h1FF;
            if ((hdr >>> 9) != f || count != 4) begin
                errors++;
                $display("FAIL frame %0d: header 0x%08x (frame %0d, count %0d), expected frame %0d, count 4",
                         f, hdr, hdr >>> 9, count, f);
            end

            found = 0;
            ns = 0;
            for (int i = 0; i < count; i++) begin
                int w1, w2, area, ysum;
                w1 = bram[base + 1 + 2 * i];
                w2 = bram[base + 2 + 2 * i];
                area = (w2 >> 1) & 'h1FF;
                ysum = w2 >>> 10;
                if (area == MS * MS && w1 == sq_sum(mx) && ysum == sq_sum(my)) begin
                    found++;
                end else if (ns < 3) begin
                    if (f == 1) begin
                        static_w1[ns] = w1;
                        static_w2[ns] = w2;
                    end else if (w1 != static_w1[ns] || w2 != static_w2[ns]) begin
                        errors++;
                        $display("FAIL frame %0d: static entry %0d changed (0x%08x 0x%08x, frame 1 had 0x%08x 0x%08x)",
                                 f, ns, w1, w2, static_w1[ns], static_w2[ns]);
                    end
                    ns++;
                end
            end
            if (found != 1) begin
                errors++;
                $display("FAIL frame %0d: mover at (%0d,%0d) expected x_sum %0d y_sum %0d area %0d, found %0d matching entries",
                         f, mx, my, sq_sum(mx), sq_sum(my), MS * MS, found);
            end else
                $display("frame %0d: mover at (%0d,%0d) ok, %0d static entries unchanged", f, mx, my, ns);

            // the step pattern_gen takes after this frame
            if (mx + DX < 0 || mx + DX > W - MS) mx = MX; else mx = mx + DX;
            if (my + DY < 0 || my + DY > H - MS) my = MY; else my = my + DY;

            repeat (200) @(negedge clk);
        end

        if (errors == 0) $display("PATTERN_GEN_MOVE PASSED (%0d frames)", FRAMES);
        else $fatal(1, "PATTERN_GEN_MOVE FAILED (%0d errors)", errors);
        $finish;
    end

    // a frame that never interrupts would hang the loop above
    initial begin
        #(64'd20 * (W * H + 45 * (W + 280)) * (FRAMES + 2) * 10 + 64'd1_000_000);
        $fatal(1, "PATTERN_GEN_MOVE TIMEOUT");
    end

endmodule
