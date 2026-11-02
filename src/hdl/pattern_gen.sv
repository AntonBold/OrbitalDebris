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
    
    // Moving object (Square): steps by (MOVE_DX, MOVE_DY) pixels after every
    // frame, so the classifier sees one spot moving against static ones.
    // Jumps back to its start when the next step would leave the frame.
    parameter MOVE_ENABLE = 0,
    parameter MOVE_X_START = 300,
    parameter MOVE_Y_START = 60,
    parameter MOVE_SIZE = 3,
    parameter MOVE_DX = 4,
    parameter MOVE_DY = 0,

    // Multi-frame testing
    parameter NUM_FRAMES = 1,

    // Vertical blanking after every frame (tvalid low), as the HDMI receiver
    // delivers it: VBLANK_LINES lines of WIDTH + H_BLANK clocks. 1080p60
    // (CEA-861) has 45 blanking lines of 2200 clocks (1920 active + 280
    // horizontal blanking) = 99,000 idle cycles. H_BLANK only sets the length
    // of a blanking line; lines are still sent back-to-back. Centroiding needs
    // an idle gap between frames to dump features and clear the TL -- see
    // docs/hdmi-cca_interface.md, "Frame Timing".
    parameter VBLANK_LINES = 45,
    parameter H_BLANK = 280
)(
    input  logic i_clk,
    input  logic i_rst,
    // Start streaming: a pulse sends NUM_FRAMES frames. While held high, the
    // stream keeps going (frame, blanking, frame, ...) like live video. Only
    // seen while idle and at the end of a blanking period.
    input  logic i_enable,
    
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

    localparam VBLANK_CYCLES = VBLANK_LINES * (WIDTH + H_BLANK);
    logic [31:0] blank_cnt;
    logic in_blank;

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            x_cnt <= '0;
            y_cnt <= '0;
            frame_count <= '0;
            m_axis_tvalid <= 1'b0;
            active_frame <= 1'b0;
            blank_cnt <= '0;
            in_blank <= 1'b0;
        end else if (i_enable || active_frame) begin
            active_frame <= 1'b1;

            if (in_blank) begin
                // Vertical blanking: hold tvalid low for VBLANK_CYCLES cycles,
                // then start the next frame, or stop after the last one
                // unless i_enable is still high
                m_axis_tvalid <= 1'b0;
                blank_cnt <= blank_cnt - 1'b1;
                if (blank_cnt <= 1) begin
                    in_blank <= 1'b0;
                    if (frame_count == NUM_FRAMES - 1) begin
                        frame_count <= '0;
                        if (i_enable)
                            m_axis_tvalid <= 1'b1;
                        else
                            active_frame <= 1'b0;
                    end else begin
                        frame_count <= frame_count + 1'b1;
                        m_axis_tvalid <= 1'b1;
                    end
                end
            end else begin
                m_axis_tvalid <= 1'b1; // We can add random stalls later if desired

                // Increment logic -- only advance once the current pixel has
                // actually been presented (tvalid high), so each frame
                // starts at (0,0) with tuser asserted
                if (m_axis_tvalid) begin
                    if (x_cnt == WIDTH - 1) begin
                        x_cnt <= '0;
                        if (y_cnt == HEIGHT - 1) begin
                            // end of frame: blanking always follows, so
                            // frames are never back-to-back
                            y_cnt <= '0;
                            in_blank <= 1'b1;
                            blank_cnt <= VBLANK_CYCLES;
                            m_axis_tvalid <= 1'b0;
                        end else begin
                            y_cnt <= y_cnt + 1'b1;
                        end
                    end else begin
                        x_cnt <= x_cnt + 1'b1;
                    end
                end
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

    // Moving Object -- position only changes between frames
    logic [$clog2(WIDTH)-1:0] mov_x;
    logic [$clog2(HEIGHT)-1:0] mov_y;
    int mov_x_next, mov_y_next;
    logic frame_end, is_mov;

    // last pixel of a frame is being presented
    assign frame_end = m_axis_tvalid && (x_cnt == WIDTH - 1) && (y_cnt == HEIGHT - 1);

    always_comb begin
        mov_x_next = int'(mov_x) + MOVE_DX;
        mov_y_next = int'(mov_y) + MOVE_DY;
    end

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            mov_x <= MOVE_X_START;
            mov_y <= MOVE_Y_START;
        end else if (frame_end) begin
            if (mov_x_next < 0 || mov_x_next > WIDTH - MOVE_SIZE)
                mov_x <= MOVE_X_START;
            else
                mov_x <= mov_x_next[$clog2(WIDTH)-1:0];
            if (mov_y_next < 0 || mov_y_next > HEIGHT - MOVE_SIZE)
                mov_y <= MOVE_Y_START;
            else
                mov_y <= mov_y_next[$clog2(HEIGHT)-1:0];
        end
    end

    assign is_mov = MOVE_ENABLE &&
                    (x_cnt >= mov_x) && (x_cnt < mov_x + MOVE_SIZE) &&
                    (y_cnt >= mov_y) && (y_cnt < mov_y + MOVE_SIZE);

    // Output pixel data (1-bit binarized stream on bit 0)
    assign m_axis_tdata = {7'b0, (is_obj1 | is_obj2 | is_coll | is_mov)};

endmodule