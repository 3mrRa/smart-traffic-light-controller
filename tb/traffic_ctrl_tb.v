`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Self-checking testbench
//
// Devices under test (all driven by the same VS / PB / rst):
//   u_dut   default traffic_ctrl              <-> reference model, lock-step
//   u_fair  traffic_ctrl FAIR_ARB=1           <-> reference model, lock-step
//   u_small traffic_ctrl with short timings   <-> reference model, lock-step
//   u_sync  traffic_ctrl SYNC_INPUTS=1        (protocol checker only)
//   u_tick  traffic_ctrl_core, random `tick`  (protocol checker only)
// Every DUT also has its own black-box protocol checker (traffic_checker.v).
//
// Plusargs:  +seed=<n>  +cycles=<n>  +novcd
// -----------------------------------------------------------------------------
module traffic_ctrl_tb;
    localparam [2:0] RED = 3'b001, YEL = 3'b010, GRN = 3'b100;
    // short timings used by u_small / u_tick
    localparam integer SM_MG = 7, SM_MY = 2, SM_AR1 = 1, SM_SG = 5,
                       SM_WK = 4, SM_SY = 3, SM_AR2 = 2;

    reg clk = 0, rst = 1, VS = 0, PB = 0, tick = 1;
    integer seed = 1, rand_cycles = 20000, cycle = 0;
    integer errors = 0, compares = 0, t0, i, n0, n1;

    always #5 clk = ~clk;
    always @(posedge clk) cycle = cycle + 1;

    // ------------------------------------------------------------- instances
    wire [2:0] m0, s0, rm0, rs0;  wire w0, rw0;
    wire [2:0] m1, s1, rm1, rs1;  wire w1, rw1;
    wire [2:0] m2, s2, rm2, rs2;  wire w2, rw2;
    wire [2:0] m3, s3;            wire w3;
    wire [2:0] m4, s4;            wire w4;

    traffic_ctrl     u_dut  (.clk(clk), .rst(rst), .VS(VS), .PB(PB),
                             .light_main(m0), .light_side(s0), .walk(w0));
    traffic_ctrl_ref u_ref0 (.clk(clk), .rst(rst), .VS(VS), .PB(PB),
                             .light_main(rm0), .light_side(rs0), .walk(rw0));

    traffic_ctrl     #(.FAIR_ARB(1)) u_fair (.clk(clk), .rst(rst), .VS(VS), .PB(PB),
                             .light_main(m1), .light_side(s1), .walk(w1));
    traffic_ctrl_ref #(.FAIR_ARB(1)) u_ref1 (.clk(clk), .rst(rst), .VS(VS), .PB(PB),
                             .light_main(rm1), .light_side(rs1), .walk(rw1));

    traffic_ctrl #(.MAIN_GREEN_MIN(SM_MG), .MAIN_YELLOW_TIME(SM_MY), .ALL_RED1_TIME(SM_AR1),
                   .SIDE_GREEN_TIME(SM_SG), .WALK_TIME(SM_WK), .SIDE_YELLOW_TIME(SM_SY),
                   .ALL_RED2_TIME(SM_AR2))
        u_small (.clk(clk), .rst(rst), .VS(VS), .PB(PB),
                 .light_main(m2), .light_side(s2), .walk(w2));
    traffic_ctrl_ref #(.MAIN_GREEN_MIN(SM_MG), .MAIN_YELLOW_TIME(SM_MY), .ALL_RED1_TIME(SM_AR1),
                   .SIDE_GREEN_TIME(SM_SG), .WALK_TIME(SM_WK), .SIDE_YELLOW_TIME(SM_SY),
                   .ALL_RED2_TIME(SM_AR2))
        u_ref2  (.clk(clk), .rst(rst), .VS(VS), .PB(PB),
                 .light_main(rm2), .light_side(rs2), .walk(rw2));

    traffic_ctrl #(.SYNC_INPUTS(1)) u_sync (.clk(clk), .rst(rst), .VS(VS), .PB(PB),
                             .light_main(m3), .light_side(s3), .walk(w3));

    traffic_ctrl_core #(.MAIN_GREEN_MIN(SM_MG), .MAIN_YELLOW_TIME(SM_MY), .ALL_RED1_TIME(SM_AR1),
                        .SIDE_GREEN_TIME(SM_SG), .WALK_TIME(SM_WK), .SIDE_YELLOW_TIME(SM_SY),
                        .ALL_RED2_TIME(SM_AR2), .FAIR_ARB(1))
        u_tick (.clk(clk), .rst(rst), .tick(tick), .VS(VS), .PB(PB),
                .light_main(m4), .light_side(s4), .walk(w4));

    // -------------------------------------------------------------- checkers
    traffic_checker #(.NAME("default")) c0 (.clk(clk), .rst(rst), .tick(1'b1), .VS(VS), .PB(PB),
        .light_main(m0), .light_side(s0), .walk(w0));
    traffic_checker #(.NAME("fair"), .FAIR_ARB(1)) c1 (.clk(clk), .rst(rst), .tick(1'b1), .VS(VS), .PB(PB),
        .light_main(m1), .light_side(s1), .walk(w1));
    traffic_checker #(.NAME("small"), .MAIN_GREEN_MIN(SM_MG), .MAIN_YELLOW_TIME(SM_MY),
        .ALL_RED1_TIME(SM_AR1), .SIDE_GREEN_TIME(SM_SG), .WALK_TIME(SM_WK),
        .SIDE_YELLOW_TIME(SM_SY), .ALL_RED2_TIME(SM_AR2))
        c2 (.clk(clk), .rst(rst), .tick(1'b1), .VS(VS), .PB(PB),
        .light_main(m2), .light_side(s2), .walk(w2));
    traffic_checker #(.NAME("sync"), .LATENCY(2)) c3 (.clk(clk), .rst(rst), .tick(1'b1), .VS(VS), .PB(PB),
        .light_main(m3), .light_side(s3), .walk(w3));
    traffic_checker #(.NAME("tick"), .MAIN_GREEN_MIN(SM_MG), .MAIN_YELLOW_TIME(SM_MY),
        .ALL_RED1_TIME(SM_AR1), .SIDE_GREEN_TIME(SM_SG), .WALK_TIME(SM_WK),
        .SIDE_YELLOW_TIME(SM_SY), .ALL_RED2_TIME(SM_AR2), .FAIR_ARB(1))
        c4 (.clk(clk), .rst(rst), .tick(tick), .VS(VS), .PB(PB),
        .light_main(m4), .light_side(s4), .walk(w4));

    // ------------------------------------------------- lock-step comparisons
    task cmp;
        input [8*8-1:0] name;
        input [6:0] dut, gold;
        begin
            compares = compares + 1;
            if (dut !== gold) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("MISMATCH [%0s] @%0t cycle %0d: DUT main=%b side=%b walk=%b | REF main=%b side=%b walk=%b",
                             name, $time, cycle, dut[6:4], dut[3:1], dut[0], gold[6:4], gold[3:1], gold[0]);
            end
        end
    endtask

    always @(negedge clk) if (!rst) begin
        cmp("default", {m0, s0, w0}, {rm0, rs0, rw0});
        cmp("fair",    {m1, s1, w1}, {rm1, rs1, rw1});
        cmp("small",   {m2, s2, w2}, {rm2, rs2, rw2});
    end

    // ------------------------------------------------------------- helpers
    task check;
        input       cond;
        input [8*80-1:0] msg;
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("DIRECTED FAIL @%0t cycle %0d: %0s", $time, cycle, msg);
            end
        end
    endtask

    task clocks;  input integer n;  begin repeat (n) @(negedge clk); end endtask

    task press_pb; begin PB = 1; @(negedge clk); PB = 0; end endtask
    task press_vs; begin VS = 1; @(negedge clk); VS = 0; end endtask

    task do_reset;
        begin
            @(negedge clk); rst = 1; VS = 0; PB = 0;
            clocks(2);
            rst = 0;
        end
    endtask

    // Wait (at negedges) until the default DUT shows a given lamp pattern.
    // Returns the number of clocks waited in t0; -1 on timeout.
    task wait_for;
        input [2:0] m, s;
        input       w;
        input integer limit;
        integer k;
        begin
            t0 = -1;
            for (k = 0; k < limit && t0 < 0; k = k + 1) begin
                if (m0 === m && s0 === s && w0 === w) t0 = k;
                else @(negedge clk);
            end
        end
    endtask

    // ---------------------------------------------------------------- tests
    initial begin
        if ($value$plusargs("seed=%d", seed)) ;
        if ($value$plusargs("cycles=%d", rand_cycles)) ;
        if (!$test$plusargs("novcd")) begin
            $dumpfile("traffic_ctrl.vcd");
            $dumpvars(0, traffic_ctrl_tb);
        end
        $display("Seed = %0d, random cycles = %0d", seed, rand_cycles);

        // T0: reset values (after the first clock edge while rst is held)
        #7;
        check(m0 === GRN && s0 === RED && w0 === 1'b0, "outputs during reset must be MAIN_GREEN");
        #5 rst = 0;

        // T1: no requests -> main road stays green
        $display("T1: idle");
        for (i = 0; i < 300; i = i + 1) begin
            @(negedge clk);
            check(m0 === GRN && s0 === RED && !w0, "main must stay green with no requests");
        end

        // T2: vehicle request -> side green after MY(4) + AR1(2); timer already past 60
        $display("T2: vehicle request");
        press_vs;
        wait_for(RED, GRN, 1'b0, 20);
        // VS latched at edge 1, MY from edge 2 (4 clocks), AR1 (2 clocks), SG from edge 8
        check(t0 == 7, "side green must appear 8 edges after VS (latch 1 + MY 4 + AR1 2 + 1)");
        clocks(40);
        check(s0 === YEL, "side green must last exactly 40 clocks");
        wait_for(GRN, RED, 1'b0, 20);
        clocks(100);

        // T3: pedestrian request -> walk, both roads red
        $display("T3: pedestrian request");
        press_pb;
        wait_for(RED, RED, 1'b1, 20);
        check(t0 == 7, "walk must appear 8 edges after PB (latch 1 + MY 4 + AR1 2 + 1)");
        clocks(39);
        check(w0 === 1'b1, "walk must still be on at clock 40");
        clocks(1);
        check(w0 === 1'b0 && s0 === YEL, "walk must end after 40 clocks, then side yellow");
        wait_for(GRN, RED, 1'b0, 20);
        clocks(70);

        // T4: simultaneous requests -> pedestrian first, vehicle served next
        $display("T4: simultaneous requests");
        VS = 1; PB = 1; @(negedge clk); VS = 0; PB = 0;
        wait_for(RED, RED, 1'b1, 20);
        check(t0 >= 0, "pedestrian must be served first");
        wait_for(RED, GRN, 1'b0, 200);
        check(t0 >= 60, "vehicle must be served in the next cycle after a full main green");
        wait_for(GRN, RED, 1'b0, 100);
        clocks(70);

        // T5: PB during side green is held for the next cycle
        $display("T5: PB during side green");
        press_vs;
        wait_for(RED, GRN, 1'b0, 20);
        clocks(10);
        press_pb;
        wait_for(RED, RED, 1'b1, 200);
        check(t0 > 0, "PB pressed during side green must be served later");
        wait_for(GRN, RED, 1'b0, 100);
        clocks(70);

        // T6: request pressed during its own service is dropped (by spec)
        $display("T6: PB during walk is absorbed");
        press_pb;
        wait_for(RED, RED, 1'b1, 20);
        clocks(5);
        press_pb;
        wait_for(GRN, RED, 1'b0, 100);
        for (i = 0; i < 150; i = i + 1) begin
            @(negedge clk);
            check(m0 === GRN, "PB during walk must not trigger another cycle");
        end

        // T7: asynchronous reset in the middle of a walk phase
        $display("T7: reset during walk");
        press_pb;
        wait_for(RED, RED, 1'b1, 20);
        clocks(10);
        #2 rst = 1; #1;
        check(m0 === GRN && s0 === RED && !w0, "async reset must force MAIN_GREEN immediately");
        @(negedge clk); rst = 0;
        clocks(60);

        // T8: starvation - a vehicle waits while pedestrians keep pressing
        $display("T8: pedestrian stream vs. waiting vehicle (fair arbitration)");
        do_reset;
        n0 = c0.n_side; n1 = c1.n_side;
        VS = 1; PB = 1; @(negedge clk); VS = 0; PB = 0;
        for (i = 0; i < 1000; i = i + 1) begin
            // press PB every main-green phase
            if (m0 === GRN && i % 20 == 0) PB = 1;
            @(negedge clk); PB = 0;
        end
        n0 = c0.n_side - n0; n1 = c1.n_side - n1;
        $display("    side-green phases in 1000 clocks: default=%0d (starved)  fair=%0d", n0, n1);
        check(n1 >= 1, "fair arbitration must serve the waiting vehicle");
        check(n0 == 0, "default (strict priority) behaviour changed unexpectedly");

        // T9: constrained-random stimulus with random tick for u_tick
        $display("T9: random stimulus");
        do_reset;
        for (i = 0; i < rand_cycles; i = i + 1) begin
            VS   = ($random(seed) % 23) == 0;
            PB   = ($random(seed) % 31) == 0;
            tick = ($random(seed) % 3)  != 0;
            if (($random(seed) % 9000) == 0) rst = 1; else rst = 0;
            @(negedge clk);
        end
        VS = 0; PB = 0; rst = 0; tick = 1;
        clocks(400);

        // ------------------------------------------------------------ report
        errors = errors + c0.errors + c1.errors + c2.errors + c3.errors + c4.errors;
        $display("--------------------------------------------------------------");
        $display("lock-step compares : %0d", compares);
        $display("checker samples    : %0d / %0d / %0d / %0d / %0d",
                 c0.checks, c1.checks, c2.checks, c3.checks, c4.checks);
        $display("walk / side phases : default %0d/%0d  fair %0d/%0d  small %0d/%0d  sync %0d/%0d  tick %0d/%0d",
                 c0.n_walk, c0.n_side, c1.n_walk, c1.n_side, c2.n_walk, c2.n_side,
                 c3.n_walk, c3.n_side, c4.n_walk, c4.n_side);
        if (errors == 0) begin
            $display("PASS");
            $finish;
        end else begin
            $display("FAIL: %0d error(s)", errors);
            $fatal(1, "testbench failed");
        end
    end

    initial begin
        #5_000_000;
        $fatal(1, "Global simulation timeout");
    end
endmodule
