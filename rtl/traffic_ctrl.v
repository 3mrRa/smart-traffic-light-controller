`timescale 1ns/1ps

module traffic_ctrl (
    input wire clk, rst, VS, PB,
    output reg [2:0] light_main,
    output reg [2:0] light_side,
    output reg walk
);
    localparam [2:0] RED=3'b001, YEL=3'b010, GRN=3'b100;
    localparam [6:0] MAIN_GREEN=7'b0000001, MAIN_YELLOW=7'b0000010,
        ALL_RED1=7'b0000100, SIDE_GREEN=7'b0001000,
        PEDESTRIAN=7'b0010000, SIDE_YELLOW=7'b0100000,
        ALL_RED2=7'b1000000;

    localparam [6:0] MAIN_GREEN_MIN=60, SIDE_GREEN_TIME=40,
        WALK_TIME=40, MAIN_YELLOW_TIME=4, SIDE_YELLOW_TIME=5,
        ALL_RED1_TIME=2, ALL_RED2_TIME=3;

    reg [6:0] state, next_state;
    reg [6:0] timer;
    reg P_queued, V_queued;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= MAIN_GREEN;
            timer <= 0;
            P_queued <= 0;
            V_queued <= 0;
        end else begin
            state <= next_state;
            if (state != next_state) timer <= 0;
            else if (timer < MAIN_GREEN_MIN) timer <= timer + 1'b1;

            if (PB) P_queued <= 1'b1;
            if (VS) V_queued <= 1'b1;
            if (state == PEDESTRIAN) P_queued <= 1'b0;
            if (state == SIDE_GREEN) V_queued <= 1'b0;
        end
    end

    always @(*) begin
        next_state = state;
        case (state)
            MAIN_GREEN:
                if ((timer >= MAIN_GREEN_MIN-1'b1) && (P_queued || V_queued))
                    next_state = MAIN_YELLOW;
            MAIN_YELLOW:
                if (timer >= MAIN_YELLOW_TIME-1'b1) next_state = ALL_RED1;
            ALL_RED1:
                if (timer >= ALL_RED1_TIME-1'b1) begin
                    if (P_queued) next_state = PEDESTRIAN;
                    else if (V_queued) next_state = SIDE_GREEN;
                    else next_state = MAIN_GREEN;
                end
            SIDE_GREEN:
                if (timer >= SIDE_GREEN_TIME-1'b1) next_state = SIDE_YELLOW;
            PEDESTRIAN:
                if (timer >= WALK_TIME-1'b1) next_state = SIDE_YELLOW;
            SIDE_YELLOW:
                if (timer >= SIDE_YELLOW_TIME-1'b1) next_state = ALL_RED2;
            ALL_RED2:
                if (timer >= ALL_RED2_TIME-1'b1) next_state = MAIN_GREEN;
            default: next_state = MAIN_GREEN;
        endcase
    end

    always @(*) begin
        light_main = RED;
        light_side = RED;
        walk = 1'b0;
        case (state)
            MAIN_GREEN:  light_main = GRN;
            MAIN_YELLOW: light_main = YEL;
            SIDE_GREEN:  light_side = GRN;
            SIDE_YELLOW: light_side = YEL;
            PEDESTRIAN:  walk = 1'b1;
            default: begin light_main = RED; light_side = RED; walk = 1'b0; end
        endcase
    end
endmodule
