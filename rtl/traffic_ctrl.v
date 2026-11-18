`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// traffic_ctrl_core
//   Synthesizable one-hot FSM for a main road, a side road and a pedestrian
//   crossing.
//
//   * All phase durations are parameters, counted in "ticks".
//   * `tick` is a clock enable for the phase timer. Tie it to 1'b1 to count
//     clock periods, or drive it from a prescaler (see traffic_top.v) to count
//     seconds on real hardware. Requests are still sampled on every clock.
//   * Outputs are registered (decoded from next_state), so the lamp drivers
//     never see combinational glitches, with no added latency.
//   * Illegal (non one-hot) states recover to MAIN_GREEN.
//   * SYNC_INPUTS=1 adds a two-flop synchronizer on VS/PB for asynchronous
//     sensors / push buttons (adds 2 clocks of request latency).
//   * FAIR_ARB=1: when both requests are pending at ALL_RED1, the one that was
//     NOT served last time wins. This prevents a stream of pedestrian presses
//     from starving side-road vehicles forever. FAIR_ARB=0 (default) keeps the
//     original strict pedestrian priority.
// -----------------------------------------------------------------------------
module traffic_ctrl_core #(
    parameter integer MAIN_GREEN_MIN   = 60,
    parameter integer MAIN_YELLOW_TIME = 4,
    parameter integer ALL_RED1_TIME    = 2,
    parameter integer SIDE_GREEN_TIME  = 40,
    parameter integer WALK_TIME        = 40,
    parameter integer SIDE_YELLOW_TIME = 5,
    parameter integer ALL_RED2_TIME    = 3,
    parameter integer SYNC_INPUTS      = 0,
    parameter integer FAIR_ARB         = 0
) (
    input  wire       clk,
    input  wire       rst,        // active-high, asynchronous
    input  wire       tick,       // timer enable
    input  wire       VS,         // vehicle on side road
    input  wire       PB,         // pedestrian push button
    output reg  [2:0] light_main,
    output reg  [2:0] light_side,
    output reg        walk
);
    localparam [2:0] RED = 3'b001, YEL = 3'b010, GRN = 3'b100;

    // One-hot state bit positions
    localparam integer S_MG = 0, S_MY = 1, S_AR1 = 2, S_SG = 3,
                       S_PED = 4, S_SY = 5, S_AR2 = 6;
    localparam [6:0] MAIN_GREEN  = 7'b1 << S_MG,
                     MAIN_YELLOW = 7'b1 << S_MY,
                     ALL_RED1    = 7'b1 << S_AR1,
                     SIDE_GREEN  = 7'b1 << S_SG,
                     PEDESTRIAN  = 7'b1 << S_PED,
                     SIDE_YELLOW = 7'b1 << S_SY,
                     ALL_RED2    = 7'b1 << S_AR2;

    // Timer only has to reach the longest phase - 1 (it saturates there).
    localparam integer T_MAX_A = (MAIN_GREEN_MIN  > SIDE_GREEN_TIME) ? MAIN_GREEN_MIN  : SIDE_GREEN_TIME;
    localparam integer T_MAX_B = (WALK_TIME       > T_MAX_A)         ? WALK_TIME       : T_MAX_A;
    localparam integer T_MAX_C = (MAIN_YELLOW_TIME> SIDE_YELLOW_TIME)? MAIN_YELLOW_TIME: SIDE_YELLOW_TIME;
    localparam integer T_MAX_D = (ALL_RED1_TIME   > ALL_RED2_TIME)   ? ALL_RED1_TIME   : ALL_RED2_TIME;
    localparam integer T_MAX_E = (T_MAX_C         > T_MAX_D)         ? T_MAX_C         : T_MAX_D;
    localparam integer T_MAX   = (T_MAX_B         > T_MAX_E)         ? T_MAX_B         : T_MAX_E;
    localparam integer TW      = (T_MAX > 2) ? $clog2(T_MAX) : 1;
    localparam [TW-1:0] T_SAT  = T_MAX - 1;

    reg [6:0]    state, next_state;
    reg [TW-1:0] timer;
    reg          P_queued, V_queued;
    reg          last_was_ped;     // last service phase was PEDESTRIAN
    wire         ped_wins = P_queued && (FAIR_ARB == 0 || !V_queued || !last_was_ped);

    // ------------------------------------------------------------------ inputs
    wire vs_in, pb_in;
    generate
        if (SYNC_INPUTS != 0) begin : g_sync
            reg [1:0] vs_sync, pb_sync;
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    vs_sync <= 2'b00;
                    pb_sync <= 2'b00;
                end else begin
                    vs_sync <= {vs_sync[0], VS};
                    pb_sync <= {pb_sync[0], PB};
                end
            end
            assign vs_in = vs_sync[1];
            assign pb_in = pb_sync[1];
        end else begin : g_nosync
            assign vs_in = VS;
            assign pb_in = PB;
        end
    endgenerate

    // ------------------------------------------------- timer done comparisons
    // (tick is an argument, not read from module scope, so that @(*) sees it)
    function done;
        input          en;
        input [TW-1:0] t;
        input integer  n;
        begin
            done = en && (t >= n - 1);
        end
    endfunction

    // --------------------------------------------------------- state register
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= MAIN_GREEN;
            timer    <= {TW{1'b0}};
            P_queued <= 1'b0;
            V_queued <= 1'b0;
            last_was_ped <= 1'b0;
        end else begin
            state <= next_state;
            if (next_state[S_PED]) last_was_ped <= 1'b1;
            if (next_state[S_SG])  last_was_ped <= 1'b0;

            if (next_state != state)
                timer <= {TW{1'b0}};
            else if (tick && timer != T_SAT)
                timer <= timer + 1'b1;

            // Requests are latched; a request is dropped while it is being
            // served (the clear wins over a simultaneous new request).
            P_queued <= (P_queued | pb_in) & ~state[S_PED];
            V_queued <= (V_queued | vs_in) & ~state[S_SG];
        end
    end

    // ------------------------------------------------------- next-state logic
    always @(*) begin
        next_state = state;
        case (state)
            MAIN_GREEN:
                if (done(tick, timer, MAIN_GREEN_MIN) && (P_queued || V_queued))
                    next_state = MAIN_YELLOW;
            MAIN_YELLOW:
                if (done(tick, timer, MAIN_YELLOW_TIME)) next_state = ALL_RED1;
            ALL_RED1:
                if (done(tick, timer, ALL_RED1_TIME)) begin
                    if      (ped_wins) next_state = PEDESTRIAN;
                    else if (V_queued) next_state = SIDE_GREEN;
                    else               next_state = MAIN_GREEN;
                end
            SIDE_GREEN:
                if (done(tick, timer, SIDE_GREEN_TIME)) next_state = SIDE_YELLOW;
            PEDESTRIAN:
                if (done(tick, timer, WALK_TIME)) next_state = SIDE_YELLOW;
            SIDE_YELLOW:
                if (done(tick, timer, SIDE_YELLOW_TIME)) next_state = ALL_RED2;
            ALL_RED2:
                if (done(tick, timer, ALL_RED2_TIME)) next_state = MAIN_GREEN;
            default:
                next_state = MAIN_GREEN;                     // illegal-state recovery
        endcase
    end

    // ------------------------------------------- registered, glitch-free outputs
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            light_main <= GRN;
            light_side <= RED;
            walk       <= 1'b0;
        end else begin
            light_main <= next_state[S_MG] ? GRN : next_state[S_MY] ? YEL : RED;
            light_side <= next_state[S_SG] ? GRN : next_state[S_SY] ? YEL : RED;
            walk       <= next_state[S_PED];
        end
    end
endmodule


// -----------------------------------------------------------------------------
// traffic_ctrl
//   Original interface (no tick port): timer counts clock periods.
//   Cycle-for-cycle compatible with the original project / reference model.
// -----------------------------------------------------------------------------
module traffic_ctrl #(
    parameter integer MAIN_GREEN_MIN   = 60,
    parameter integer MAIN_YELLOW_TIME = 4,
    parameter integer ALL_RED1_TIME    = 2,
    parameter integer SIDE_GREEN_TIME  = 40,
    parameter integer WALK_TIME        = 40,
    parameter integer SIDE_YELLOW_TIME = 5,
    parameter integer ALL_RED2_TIME    = 3,
    parameter integer SYNC_INPUTS      = 0,
    parameter integer FAIR_ARB         = 0
) (
    input  wire       clk, rst, VS, PB,
    output wire [2:0] light_main,
    output wire [2:0] light_side,
    output wire       walk
);
    traffic_ctrl_core #(
        .MAIN_GREEN_MIN  (MAIN_GREEN_MIN),
        .MAIN_YELLOW_TIME(MAIN_YELLOW_TIME),
        .ALL_RED1_TIME   (ALL_RED1_TIME),
        .SIDE_GREEN_TIME (SIDE_GREEN_TIME),
        .WALK_TIME       (WALK_TIME),
        .SIDE_YELLOW_TIME(SIDE_YELLOW_TIME),
        .ALL_RED2_TIME   (ALL_RED2_TIME),
        .SYNC_INPUTS     (SYNC_INPUTS),
        .FAIR_ARB        (FAIR_ARB)
    ) u_core (
        .clk(clk), .rst(rst), .tick(1'b1), .VS(VS), .PB(PB),
        .light_main(light_main), .light_side(light_side), .walk(walk)
    );
endmodule
