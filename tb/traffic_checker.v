`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// traffic_checker - black-box protocol checker (simulation only)
//
// Watches ONLY the controller's inputs and lamp outputs; it knows nothing about
// the internal state. It checks, every clock:
//   * safety: only legal lamp combinations (no conflicting greens, walk only
//     while every vehicle lamp is red, valid one-hot lamp encodings)
//   * phase order:  MG -> MY -> AR1 -> {WALK | SG | MG},
//                   SG/WALK -> SY -> AR2 -> MG
//   * exact phase durations (in ticks) and the minimum main-green time
//   * main green never ends without a pending request
//   * arbitration at ALL_RED1 (strict pedestrian priority, or alternating
//     when FAIR_ARB=1)
//   * liveness: a pending request is served within MAX_WAIT ticks
// Requests are modelled with LATENCY clocks of input delay (2 when the DUT
// has SYNC_INPUTS=1).
// -----------------------------------------------------------------------------
module traffic_checker #(
    parameter         NAME             = "dut",
    parameter integer MAIN_GREEN_MIN   = 60,
    parameter integer MAIN_YELLOW_TIME = 4,
    parameter integer ALL_RED1_TIME    = 2,
    parameter integer SIDE_GREEN_TIME  = 40,
    parameter integer WALK_TIME        = 40,
    parameter integer SIDE_YELLOW_TIME = 5,
    parameter integer ALL_RED2_TIME    = 3,
    parameter integer FAIR_ARB         = 0,
    parameter integer LATENCY          = 0,
    parameter integer MAX_WAIT_P       = 0,   // 0 = derive automatically
    parameter integer MAX_WAIT_V       = 0    // 0 = derive / don't check
) (
    input wire       clk, rst, tick, VS, PB,
    input wire [2:0] light_main, light_side,
    input wire       walk
);
    localparam [2:0] RED = 3'b001, YEL = 3'b010, GRN = 3'b100;
    localparam integer MG = 0, MY = 1, AR1 = 2, SG = 3, WK = 4, SY = 5, AR2 = 6,
                       BAD = 7;

    // One full service cycle, worst case, plus a small margin.
    localparam integer CYCLE = MAIN_GREEN_MIN + MAIN_YELLOW_TIME + ALL_RED1_TIME +
                               ((SIDE_GREEN_TIME > WALK_TIME) ? SIDE_GREEN_TIME : WALK_TIME) +
                               SIDE_YELLOW_TIME + ALL_RED2_TIME + 2;
    localparam integer WAIT_P = (MAX_WAIT_P != 0) ? MAX_WAIT_P :
                                (FAIR_ARB != 0)   ? 2 * CYCLE : CYCLE;
    // Without fair arbitration vehicles can starve, so only check when asked.
    localparam integer WAIT_V = (MAX_WAIT_V != 0) ? MAX_WAIT_V :
                                (FAIR_ARB != 0)   ? 2 * CYCLE : 0;

    integer errors   = 0;
    integer checks   = 0;
    integer n_walk   = 0, n_side = 0;
    integer phase, count, wait_p, wait_v;
    reg     pend_p, pend_v, last_pend_p, last_pend_v, last_ped;
    reg [LATENCY:0] vs_d, pb_d;   // vs_d[LATENCY] = what the FSM sees
    integer cur;

    function integer decode;
        input [2:0] m, s;
        input       w;
        begin
            if      (m == GRN && s == RED && !w) decode = MG;
            else if (m == YEL && s == RED && !w) decode = MY;
            else if (m == RED && s == RED && !w) decode = AR1;   // AR1/AR2 resolved later
            else if (m == RED && s == GRN && !w) decode = SG;
            else if (m == RED && s == RED &&  w) decode = WK;
            else if (m == RED && s == YEL && !w) decode = SY;
            else                                 decode = BAD;
        end
    endfunction

    function [8*5-1:0] pname;
        input integer p;
        case (p)
            MG: pname = "MG";  MY: pname = "MY";  AR1: pname = "AR1";
            SG: pname = "SG";  WK: pname = "WALK"; SY: pname = "SY";
            AR2: pname = "AR2"; default: pname = "BAD";
        endcase
    endfunction

    function integer expected;
        input integer p;
        case (p)
            MY: expected = MAIN_YELLOW_TIME;  AR1: expected = ALL_RED1_TIME;
            SG: expected = SIDE_GREEN_TIME;   WK:  expected = WALK_TIME;
            SY: expected = SIDE_YELLOW_TIME;  AR2: expected = ALL_RED2_TIME;
            default: expected = -1;
        endcase
    endfunction

    task fail;
        input [8*96-1:0] msg;
        begin
            errors = errors + 1;
            if (errors <= 20)
                $display("[%0s] CHECK FAIL @%0t: %0s", NAME, $time, msg);
        end
    endtask

    always @(posedge clk or posedge rst) begin
        if (rst !== 1'b0) begin   // X or 1 = in reset
            phase = MG; count = 0; wait_p = 0; wait_v = 0;
            pend_p = 0; pend_v = 0; last_pend_p = 0; last_pend_v = 0; last_ped = 0;
            vs_d = 0; pb_d = 0;
        end else begin
            checks = checks + 1;
            cur = decode(light_main, light_side, walk);
            if (cur == AR1 && (phase == SY || phase == AR2)) cur = AR2;

            if (cur == BAD) begin
                fail("illegal lamp combination");
                $display("        main=%b side=%b walk=%b", light_main, light_side, walk);
            end else if (cur != phase) begin
                // ---------------- a phase just finished: check it
                case (phase)
                    MG: begin
                        if (cur != MY) fail("MG must be followed by MY");
                        if (count < MAIN_GREEN_MIN) fail("main green shorter than minimum");
                        if (!last_pend_p && !last_pend_v) fail("main green ended with no request");
                    end
                    MY:  if (cur != AR1) fail("MY must be followed by ALL_RED1");
                    AR1: begin
                        if (cur == WK) begin
                            if (!last_pend_p) fail("WALK without a pedestrian request");
                            if (FAIR_ARB != 0 && last_pend_v && last_ped)
                                fail("fair arbitration: vehicles should have won");
                        end else if (cur == SG) begin
                            if (!last_pend_v) fail("SIDE_GREEN without a vehicle request");
                            if (last_pend_p && (FAIR_ARB == 0 || !last_ped))
                                fail("pedestrian request should have had priority");
                        end else if (cur == MG) begin
                            if (last_pend_p || last_pend_v) fail("ALL_RED1 -> MG with request pending");
                        end else fail("bad phase after ALL_RED1");
                    end
                    SG, WK: if (cur != SY)  fail("SG/WALK must be followed by SY");
                    SY:     if (cur != AR2) fail("SY must be followed by ALL_RED2");
                    AR2:    if (cur != MG)  fail("ALL_RED2 must be followed by MG");
                endcase
                if (phase != MG && count != expected(phase)) begin
                    fail("wrong phase duration");
                    $display("        phase %0s lasted %0d ticks, expected %0d",
                             pname(phase), count, expected(phase));
                end
                if (cur == WK) begin last_ped = 1; n_walk = n_walk + 1; end
                if (cur == SG) begin last_ped = 0; n_side = n_side + 1; end
                phase = cur;
                count = 0;
            end
            if (tick) count = count + 1;

            // ---------------- request model (same semantics as the spec)
            vs_d = {vs_d, VS};
            pb_d = {pb_d, PB};
            last_pend_p = pend_p;
            last_pend_v = pend_v;
            pend_p = (pend_p | pb_d[LATENCY]) & (cur != WK);
            pend_v = (pend_v | vs_d[LATENCY]) & (cur != SG);

            // ---------------- liveness
            if (pend_p && cur != WK) begin
                if (tick) wait_p = wait_p + 1;
                if (wait_p == WAIT_P + 1) fail("pedestrian request not served in time");
            end else wait_p = 0;
            if (pend_v && cur != SG) begin
                if (tick) wait_v = wait_v + 1;
                if (WAIT_V != 0 && wait_v == WAIT_V + 1) fail("vehicle request not served in time");
            end else wait_v = 0;
        end
    end
endmodule
