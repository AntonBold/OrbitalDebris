// Translator Lut - Spagnolo et al.
// indexed by a provisional label, stores the label as it
// currently translates

module translator_lut #(
        parameter DEPTH = 1024,
        localparam ADDR_SIZE = $clog2(DEPTH),
        localparam DATA_WIDTH = ADDR_SIZE
    )(
        input logic i_clk,
        input logic i_rst,

        // write port
        input logic [DATA_WIDTH-1:0] dind,
        input logic i_we,
        input logic [ADDR_SIZE-1:0] addrd,

        // read ports
        // a/b - decision time lookup of west and north neighbors
        input logic [ADDR_SIZE-1:0] addra,
        input logic [ADDR_SIZE-1:0] addrb,
        // e - resolve r2 before it is stored in the buffer
        input logic [ADDR_SIZE-1:0] addre,
        // f/g - second translation hop on a collision, for extract feature block
        input logic [ADDR_SIZE-1:0] addrf,
        input logic [ADDR_SIZE-1:0] addrg,

        output logic [DATA_WIDTH-1:0] doa,
        output logic [DATA_WIDTH-1:0] dob,
        output logic [DATA_WIDTH-1:0] doe,
        output logic [DATA_WIDTH-1:0] dof,
        output logic [DATA_WIDTH-1:0] dog
    );

    (* ram_style = "distributed" *)
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // reads - combinational, one array, five readers
    assign doa = mem[addra];
    assign dob = mem[addrb];
    assign doe = mem[addre];
    assign dof = mem[addrf];
    assign dog = mem[addrg];

    // State machine for internal reset
    typedef enum logic {
        IDLE,
        RESETTING
    } state_t;
    
    state_t state, next_state;
    logic [ADDR_SIZE-1:0] reset_counter;
    
    // Internal write signals to mux between external inputs and reset logic
    logic internal_we;
    logic [ADDR_SIZE-1:0] internal_addrd;
    logic [DATA_WIDTH-1:0] internal_dind;
    
    assign internal_we    = (state == RESETTING) ? 1'b1          : i_we;
    assign internal_addrd = (state == RESETTING) ? reset_counter : addrd;
    assign internal_dind  = (state == RESETTING) ? reset_counter : dind;

    // State machine and counter sequential logic
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            state <= RESETTING;
            reset_counter <= '0;
        end else begin
            state <= next_state;
            if (state == RESETTING) begin
                reset_counter <= reset_counter + 1'b1;
            end
        end
    end
    
    // Next state combinational logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                // Stay in IDLE until external i_rst kicks us back to RESETTING via the ff block
            end
            RESETTING: begin
                if (reset_counter == DEPTH - 1) begin
                    next_state = IDLE;
                end
            end
        endcase
    end

    // Memory write block using the internal muxed signals
    always_ff @(posedge i_clk) begin
        if (internal_we) begin
            mem[internal_addrd] <= internal_dind;
        end
    end

endmodule