module blinky(
    input logic sysclk,
    input logic sw0,
    output logic led0
);

    localparam FAST_COUNT = 12_500_000;
    localparam SLOW_COUNT = 25_000_000;

    logic [$clog2(SLOW_COUNT):0] counter;
    logic [$clog2(SLOW_COUNT):0] max_count;
    logic [1:0] sw0_pipe;
    logic sw0_dffd;
    
    
    assign sw0_dffd = sw0_pipe[1];


    initial begin
        led0 = 1'b0;
        sw0_pipe = 2'b0;
        counter = '0;
    end
    

    always_ff @(posedge sysclk) begin
        if (counter >= max_count - 1) begin
            led0 <= ~led0;
            counter <= 0;
        end
        else 
            counter <= counter + 1'b1;
        
        sw0_pipe <= {sw0_pipe[0], sw0};
    end
    
    
    always_comb begin
        case (sw0_dffd) 
            1'b0: max_count = FAST_COUNT;
            1'b1: max_count = SLOW_COUNT;
            default: max_count = SLOW_COUNT;
        endcase
    
    
    end

endmodule