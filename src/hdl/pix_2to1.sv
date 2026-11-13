`timescale 1ns/1ps

module pix_2to1 #()(
    input logic aclk,
    input logic aresetn,
    input logic [15:0] s_axis_tdata,
    input logic s_axis_tvalid,
    input logic s_axis_tuser,
    input logic s_axis_tlast,
    output logic s_axis_tready,
    output logic [7:0] m_axis_tdata,
    output logic m_axis_tvalid,
    output logic m_axis_tuser,
    output logic m_axis_tlast,
    input logic m_axis_tready
);

logic [7:0] first_pixel, second_pixel;
logic tlast_reg;
logic tuser_reg;

logic accepted_beat, accepted_output;
logic gate_start_of_frame;

typedef enum logic [1:0] {
    FIRST_PIX,
    SECOND_PIX,
    EMPTY
} state_t;
state_t state, next_state;

assign accepted_beat = s_axis_tvalid && s_axis_tready;
assign accepted_output = m_axis_tvalid && m_axis_tready;

// registering input data
always_ff @(posedge aclk)
begin
    if (!aresetn)
    begin
        first_pixel <= '0;
        second_pixel <= '0;
        tuser_reg <= 0;
        tlast_reg <= 0;
    end
    else if (accepted_beat)
    begin
        first_pixel <= {7'b0,s_axis_tdata[0]};
        second_pixel <= {7'b0, s_axis_tdata[8]};
        tuser_reg <= s_axis_tuser;
        tlast_reg <= s_axis_tlast;
    end
end

// valid and ready driving
always_comb begin
    if (!aresetn)
    begin
        m_axis_tvalid = 0;
        s_axis_tready = 0;
    end
    else if (gate_start_of_frame)
    begin
        m_axis_tvalid = 0;
        s_axis_tready = 1;
    end
    else
    begin
        m_axis_tvalid = (state != EMPTY);
        s_axis_tready = (state == EMPTY) || ((state == SECOND_PIX) && (m_axis_tready));
    end
end

// next state assignment
always_ff @(posedge aclk)
begin
    if (!aresetn)
        state <= EMPTY;
    else
        state <= next_state;
end

// state output logic
always_comb
begin
    case (state)
            FIRST_PIX:
            begin
                m_axis_tdata = first_pixel;
                m_axis_tuser = tuser_reg;
                m_axis_tlast = 0;
            end
            SECOND_PIX:
            begin
                m_axis_tdata = second_pixel;
                m_axis_tuser = 0;
                m_axis_tlast = tlast_reg;
            end
            EMPTY:
            begin
                m_axis_tdata = '1;
                m_axis_tuser = 0;
                m_axis_tlast = 0;
            end
            default:
            begin
                m_axis_tdata = '1;
                m_axis_tuser = 0;
                m_axis_tlast = 0;
            end
    endcase
end

// next state logic
always_comb
begin
    next_state = state;
    case (state)
        FIRST_PIX:
            begin
                if (accepted_output)
                    next_state = SECOND_PIX;
                else
                    next_state = FIRST_PIX;
            end
        SECOND_PIX:
            begin
                if (accepted_output && accepted_beat)
                    next_state = FIRST_PIX;
                else if (accepted_output)
                    next_state = EMPTY;
                else
                    next_state = SECOND_PIX;
            end
        EMPTY:
            begin
                if (accepted_beat)
                    next_state = FIRST_PIX;
                else
                    next_state = EMPTY;
            end
        default:
            next_state = EMPTY;
    endcase

end

// start of frame gatee
always_ff @(posedge aclk)
begin
    if (!aresetn) 
    begin
        gate_start_of_frame <= 1'b1;
    end
    else if (accepted_beat && s_axis_tuser)
    begin
        gate_start_of_frame <= 1'b0;
    end
end

endmodule
