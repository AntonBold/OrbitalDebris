`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/27/2026 02:27:10 PM
// Design Name: 
// Module Name: sync_debouncer
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module sync_debouncer(
    input wire sys_clk,
    input wire button,
    output wire sync_deb_signal
    );
    
    reg button_sync_1, button_sync_2, button_deb_1, button_deb_2, button_deb_3, button_deb_4, button_deb_5, button_deb_6, button_deb_7,  button_deb_8, button_deb_9, button_deb_10;

    always @(posedge sys_clk) begin
        button_sync_1 <= button;
        button_sync_2 <= button_sync_1;
        button_deb_1 <= button_sync_2;
        button_deb_2 <= button_deb_1;
        button_deb_3 <= button_deb_2;
        button_deb_4 <= button_deb_3;
        button_deb_5 <= button_deb_4;
        button_deb_6 <= button_deb_5;
        button_deb_7 <= button_deb_6;
        button_deb_8 <= button_deb_7;
        button_deb_9 <= button_deb_8;
        button_deb_10 <= button_deb_9;
    end
    
    assign sync_deb_signal = button_deb_1 & button_deb_2 & button_deb_3 & button_deb_4 & button_deb_5 & button_deb_6 & button_deb_7 & button_deb_8 & button_deb_9 & button_deb_10;
    
endmodule
