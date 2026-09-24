`timescale 1ns / 1ps

module translator_lut_tb();

    parameter DEPTH = 1024;
    localparam ADDR_SIZE = $clog2(DEPTH);
    localparam DATA_WIDTH = ADDR_SIZE;

    // Clock and Reset
    logic clk;
    logic rst;

    // Write Port
    logic [DATA_WIDTH-1:0] dind;
    logic i_we;
    logic [ADDR_SIZE-1:0] addrd;

    // Read Ports
    logic [ADDR_SIZE-1:0] addra, addrb, addre, addrf, addrg;
    logic [DATA_WIDTH-1:0] doa, dob, doe, dof, dog;

    // DUT
    translator_lut #(
        .DEPTH(DEPTH)
    ) dut (
        .i_clk(clk),
        .i_rst(rst),
        .dind(dind),
        .i_we(i_we),
        .addrd(addrd),
        .addra(addra),
        .addrb(addrb),
        .addre(addre),
        .addrf(addrf),
        .addrg(addrg),
        .doa(doa),
        .dob(dob),
        .doe(doe),
        .dof(dof),
        .dog(dog)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ==========================================
    // TB-Level SystemVerilog Assertions (SVAs)
    // ==========================================

    // 1. Data written should be readable combinationally on the NEXT clock cycle
    // (Since it's a distributed RAM with ff write and comb read)
    property p_write_read_latency;
        @(posedge clk) disable iff (rst || dut.state == 1 /* RESETTING */)
        (i_we) |=> (doa == $past(dind) || addra != $past(addrd)); 
        // If we wrote data, and we read the same address next cycle, data must match
    endproperty
    assert property (p_write_read_latency) else $error("SVA: RAM Write-to-Read mismatch");

    // ==========================================
    // Stimulus (To be filled later)
    // ==========================================
    initial begin
        rst = 1;
        i_we = 0;
        dind = 0;
        addrd = 0;
        addra = 0; addrb = 0; addre = 0; addrf = 0; addrg = 0;

        repeat(5) @(posedge clk);
        rst = 0;
        
        // Wait for internal LUT reset state machine to finish (1024 cycles)
        repeat(1030) @(posedge clk);

        // ==========================================
        // Manual Directed Stimulus
        // ==========================================

        // Write a merged label (e.g., Label 5 merged into 2)
        i_we = 1; addrd = 5; dind = 2;
        @(posedge clk);
        i_we = 0;

        // Wait a cycle to ensure write completes
        @(posedge clk);

        // Combinationally read from Port A and Port B
        addra = 5; addrb = 2;
        #1; // Delta delay to let combinational logic settle
        
        $display("Read Port A (addr 5): %0d (Expected 2)", doa);
        $display("Read Port B (addr 2): %0d (Expected 2)", dob);
        
        @(posedge clk);

        #100;
        $finish;
    end

endmodule
