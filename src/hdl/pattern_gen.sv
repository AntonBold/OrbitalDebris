`timescale 1ns / 1ps

module pattern_gen #(
    parameter WIDTH = 1920,
    parameter HEIGHT = 1080,
    
    // Object 1 Parameters (Square)
    parameter OBJ1_ENABLE = 1,
    parameter OBJ1_X_START = 100,
    parameter OBJ1_Y_START = 100,
    parameter OBJ1_SIZE = 5,
    
    // Object 2 Parameters (Square)
    parameter OBJ2_ENABLE = 1,
    parameter OBJ2_X_START = 500,
    parameter OBJ2_Y_START = 500,
    parameter OBJ2_SIZE = 5,
    
    // Collision Object Parameters (U-shape or reverse L)
    parameter COLL_ENABLE = 1,
    parameter COLL_X_START = 800,
    parameter COLL_Y_START = 800,
    parameter COLL_WIDTH = 15,
    parameter COLL_HEIGHT = 10,
    parameter COLL_THICKNESS = 3,
    
    // Multi-frame testing
    parameter NUM_FRAMES = 1
)(
    input  logic i_clk,
    input  logic i_rst,
    input  logic i_enable, // Start streaming
    
    // AXI4-Stream Video Out (inferred by vivado)
     output logic [7:0] m_axis_tdata,
     output logic       m_axis_tvalid,
     output logic       m_axis_tuser,
     output logic       m_axis_tlast
);

    logic [$clog2(WIDTH)-1:0] x_cnt;
    logic [$clog2(HEIGHT)-1:0] y_cnt;
    logic [7:0] frame_count;
    logic active_frame;
    
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            x_cnt <= '0;
            y_cnt <= '0;
            frame_count <= '0;
            m_axis_tvalid <= 1'b0;
            active_frame <= 1'b0;
        end else if (i_enable || active_frame) begin
            active_frame <= 1'b1;
            m_axis_tvalid <= 1'b1; // We can add random stalls later if desired
            
            // Increment logic
            if (x_cnt == WIDTH - 1) begin
                x_cnt <= '0;
                if (y_cnt == HEIGHT - 1) begin
                    y_cnt <= '0;
                    if (frame_count == NUM_FRAMES - 1) begin
                        active_frame <= 1'b0; // Stop after N frames
                        m_axis_tvalid <= 1'b0;
                    end else begin
                        frame_count <= frame_count + 1'b1;
                    end
                end else begin
                    y_cnt <= y_cnt + 1'b1;
                end
            end else begin
                x_cnt <= x_cnt + 1'b1;
            end
        end else begin
            m_axis_tvalid <= 1'b0;
        end
    end
    
    // AXI-Stream Control Signals
    assign m_axis_tuser = (x_cnt == 0 && y_cnt == 0 && m_axis_tvalid);
    assign m_axis_tlast = (x_cnt == WIDTH - 1 && m_axis_tvalid);
    
    // Object Generation Logic
    logic is_obj1, is_obj2, is_coll;
    
    // Simple Square 1
    assign is_obj1 = OBJ1_ENABLE && 
                     (x_cnt >= OBJ1_X_START) && (x_cnt < OBJ1_X_START + OBJ1_SIZE) &&
                     (y_cnt >= OBJ1_Y_START) && (y_cnt < OBJ1_Y_START + OBJ1_SIZE);
                     
    // Simple Square 2                 
    assign is_obj2 = OBJ2_ENABLE && 
                     (x_cnt >= OBJ2_X_START) && (x_cnt < OBJ2_X_START + OBJ2_SIZE) &&
                     (y_cnt >= OBJ2_Y_START) && (y_cnt < OBJ2_Y_START + OBJ2_SIZE);
                     
    // Collision Object (U-Shape)
    // Left leg, Right leg, and a bottom bridge connecting them
    logic coll_left_leg, coll_right_leg, coll_bridge;
    assign coll_left_leg = (x_cnt >= COLL_X_START) && (x_cnt < COLL_X_START + COLL_THICKNESS) &&
                           (y_cnt >= COLL_Y_START) && (y_cnt < COLL_Y_START + COLL_HEIGHT);
                           
    assign coll_right_leg = (x_cnt >= COLL_X_START + COLL_WIDTH - COLL_THICKNESS) && (x_cnt < COLL_X_START + COLL_WIDTH) &&
                            (y_cnt >= COLL_Y_START) && (y_cnt < COLL_Y_START + COLL_HEIGHT);
                            
    assign coll_bridge = (x_cnt >= COLL_X_START) && (x_cnt < COLL_X_START + COLL_WIDTH) &&
                         (y_cnt >= COLL_Y_START + COLL_HEIGHT - COLL_THICKNESS) && (y_cnt < COLL_Y_START + COLL_HEIGHT);
                         
    assign is_coll = COLL_ENABLE && (coll_left_leg || coll_right_leg || coll_bridge);
    
    // Output pixel data (1-bit binarized stream on bit 0)
    assign m_axis_tdata = {7'b0, (is_obj1 | is_obj2 | is_coll)};

endmodule