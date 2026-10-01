module blinky(
    input logic sysclk,
    output logic led0
);

    localparam COUNT = 12_500_000;
    logic [$clog2(COUNT):0] counter;


    initial begin
        led = 1'b0;
    end

    always_ff @(posedge sysclk) begin
        if (counter >= COUNT - 1'b1) begin
            led <= ~led;
            counter <= 0;
        end
        else 
            counter <= counter + 1'b1;
    end

endmodule