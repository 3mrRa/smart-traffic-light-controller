`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// traffic_ctrl_ref - behavioral reference model (simulation only)
//
// Deliberately written differently from the DUT so the lock-step comparison
// in the testbench is meaningful:
//   * binary state encoding instead of one-hot
//   * a single sequential process (no separate next-state logic)
//   * a "time remaining" down-counter loaded on phase entry instead of an
//     up-counting timer compared against duration-1
// -----------------------------------------------------------------------------
module traffic_ctrl_ref #(
    parameter integer MAIN_GREEN_MIN   = 60,
    parameter integer MAIN_YELLOW_TIME = 4,
    parameter integer ALL_RED1_TIME    = 2,
    parameter integer SIDE_GREEN_TIME  = 40,
    parameter integer WALK_TIME        = 40,
    parameter integer SIDE_YELLOW_TIME = 5,
    parameter integer ALL_RED2_TIME    = 3,
    parameter integer FAIR_ARB         = 0
) (
    input  wire       clk, rst, VS, PB,
    output reg  [2:0] light_main,
    output reg  [2:0] light_side,
    output reg        walk
);
    localparam [2:0] RED = 3'b001, YEL = 3'b010, GRN = 3'b100;
    localparam [2:0] MG = 3'd0, MY = 3'd1, AR1 = 3'd2, SG = 3'd3,
                     PED = 3'd4, SY = 3'd5, AR2 = 3'd6;

    reg [2:0] st;
    integer   remaining;      // periods left in the current phase, after this one
    reg       p_req, v_req;
    reg       ped_last;       // which service ran most recently

    task enter;
        input [2:0]   s;
        input integer duration;
        begin
            st        <= s;
            remaining <= duration - 1;
        end
    endtask

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            st <= MG; remaining <= MAIN_GREEN_MIN - 1;
            p_req <= 1'b0; v_req <= 1'b0; ped_last <= 1'b0;
        end else begin
            // request latches (cleared while being served)
            p_req <= (st == PED) ? 1'b0 : (p_req | PB);
            v_req <= (st == SG)  ? 1'b0 : (v_req | VS);

            if (remaining > 0) begin
                remaining <= remaining - 1;
            end else begin
                case (st)
                    MG:  if (p_req || v_req) enter(MY, MAIN_YELLOW_TIME);
                    MY:  enter(AR1, ALL_RED1_TIME);
                    AR1: if (p_req && v_req && FAIR_ARB != 0) begin
                             if (ped_last) begin enter(SG,  SIDE_GREEN_TIME); ped_last <= 1'b0; end
                             else          begin enter(PED, WALK_TIME);       ped_last <= 1'b1; end
                         end
                         else if (p_req) begin enter(PED, WALK_TIME);       ped_last <= 1'b1; end
                         else if (v_req) begin enter(SG,  SIDE_GREEN_TIME); ped_last <= 1'b0; end
                         else            enter(MG, MAIN_GREEN_MIN);
                    SG:  enter(SY, SIDE_YELLOW_TIME);
                    PED: enter(SY, SIDE_YELLOW_TIME);
                    SY:  enter(AR2, ALL_RED2_TIME);
                    AR2: enter(MG, MAIN_GREEN_MIN);
                    default: enter(MG, MAIN_GREEN_MIN);
                endcase
            end
        end
    end

    always @(*) begin
        light_main = (st == MG) ? GRN : (st == MY) ? YEL : RED;
        light_side = (st == SG) ? GRN : (st == SY) ? YEL : RED;
        walk       = (st == PED);
    end
endmodule
