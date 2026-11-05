`timescale 1ns/1ps

// Binary-encoded behavioral reference model.
module traffic_ctrl_ref (
    input wire clk, rst, VS, PB,
    output reg [2:0] light_main,
    output reg [2:0] light_side,
    output reg walk
);
    localparam [2:0] RED=3'b001, YEL=3'b010, GRN=3'b100;
    localparam [2:0] MAIN_GREEN=0, MAIN_YELLOW=1, ALL_RED1=2,
        SIDE_GREEN=3, PEDESTRIAN=4, SIDE_YELLOW=5, ALL_RED2=6;
    integer timer;
    reg [2:0] state, next_state;
    reg P_queued, V_queued;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= MAIN_GREEN; timer <= 0;
            P_queued <= 0; V_queued <= 0;
        end else begin
            state <= next_state;
            if (state != next_state) timer <= 0;
            else if (timer < 60) timer <= timer + 1;
            if (PB) P_queued <= 1;
            if (VS) V_queued <= 1;
            if (state == PEDESTRIAN) P_queued <= 0;
            if (state == SIDE_GREEN) V_queued <= 0;
        end
    end

    always @(*) begin
        next_state = state;
        case (state)
            MAIN_GREEN: if ((timer >= 59) && (P_queued || V_queued)) next_state=MAIN_YELLOW;
            MAIN_YELLOW: if (timer >= 3) next_state=ALL_RED1;
            ALL_RED1: if (timer >= 1) begin
                if (P_queued) next_state=PEDESTRIAN;
                else if (V_queued) next_state=SIDE_GREEN;
                else next_state=MAIN_GREEN;
            end
            SIDE_GREEN: if (timer >= 39) next_state=SIDE_YELLOW;
            PEDESTRIAN: if (timer >= 39) next_state=SIDE_YELLOW;
            SIDE_YELLOW: if (timer >= 4) next_state=ALL_RED2;
            ALL_RED2: if (timer >= 2) next_state=MAIN_GREEN;
            default: next_state=MAIN_GREEN;
        endcase
    end

    always @(*) begin
        light_main=RED; light_side=RED; walk=0;
        case (state)
            MAIN_GREEN: light_main=GRN;
            MAIN_YELLOW: light_main=YEL;
            SIDE_GREEN: light_side=GRN;
            SIDE_YELLOW: light_side=YEL;
            PEDESTRIAN: walk=1;
            default: begin light_main=RED; light_side=RED; walk=0; end
        endcase
    end
endmodule
