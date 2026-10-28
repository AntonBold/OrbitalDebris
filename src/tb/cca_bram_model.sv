`timescale 1ns / 1ps

// Testbench-only model of the shared centroid BRAM (docs/pl-ps_interface_spec.md).
//
// Captures full-word writes (en && we == 4'b1111) from cca_top and checks:
//   - every write lands inside the slot the PL should be filling right now
//     (slot 0 after reset, then 0 -> 1 -> 2 -> 0 on each interrupt);
//   - the header (slot base) is the last word written before the interrupt.
// Reset clears the memory: a system reset restarts the PS too, so nothing
// from before the reset is meant to be visible afterwards.

module cca_bram_model (
    input  logic        clk,
    input  logic        rst,
    input  logic        irq,
    input  logic        en,
    input  logic [3:0]  we,
    input  logic [31:0] addr,
    input  logic [31:0] wdata
);

    localparam int SLOT_BYTES = 32'h804;
    localparam int WORDS      = 3 * SLOT_BYTES / 4;   // 0x180C bytes

    logic [31:0] mem [0:WORDS-1];

    int exp_slot;
    int oob_errors    = 0;   // writes outside the active slot / BRAM
    int order_errors  = 0;   // header not last, or interrupt without header
    int partial_we    = 0;   // en with a we other than 0000/1111
    int writes        = 0;
    bit hdr_written;

    function automatic void clear();
        for (int i = 0; i < WORDS; i++) mem[i] = '0;
        exp_slot    = 0;
        hdr_written = 1'b0;
    endfunction

    initial clear();

    always @(posedge clk) begin
        if (rst) begin
            clear();
        end else begin
            if (en && we != 4'b0000 && we != 4'b1111) partial_we++;
            if (en && we == 4'b1111) begin
                writes++;
                if (addr[1:0] != 2'b00 || addr >= 3 * SLOT_BYTES) begin
                    oob_errors++;
                    $display("[%0t] BRAM: write to illegal address 0x%0h", $time, addr);
                end else begin
                    if (addr < exp_slot * SLOT_BYTES || addr >= (exp_slot + 1) * SLOT_BYTES) begin
                        oob_errors++;
                        $display("[%0t] BRAM: write to 0x%0h outside active slot %0d [0x%0h,0x%0h)",
                                 $time, addr, exp_slot, exp_slot * SLOT_BYTES, (exp_slot + 1) * SLOT_BYTES);
                    end
                    if (hdr_written) begin
                        order_errors++;
                        $display("[%0t] BRAM: write to 0x%0h after the header was written", $time, addr);
                    end
                    if (addr == exp_slot * SLOT_BYTES) hdr_written = 1'b1;
                    mem[addr >> 2] = wdata;
                end
            end
            if (irq) begin
                if (!hdr_written) begin
                    order_errors++;
                    $display("[%0t] BRAM: interrupt before header write for slot %0d", $time, exp_slot);
                end
                hdr_written = 1'b0;
                exp_slot    = (exp_slot + 1) % 3;
            end
        end
    end

endmodule
