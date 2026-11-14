`timescale 1ns/1ps

// Smoke test for the board wrapper: a tiny clock divider (CLK_HZ/TICK_HZ = 4)
// so the full sequence runs quickly, checked by the black-box protocol checker
// with tick-based timing and 2-clock input latency.
module traffic_top_tb;
    reg clk = 0, rst_n = 0, vs = 0, pb = 0;
    wire [2:0] m, s;
    wire w;
    integer i, seed = 3;

    always #5 clk = ~clk;

    traffic_top #(.CLK_HZ(4), .TICK_HZ(1), .RST_ACTIVE_LOW(1)) dut (
        .clk(clk), .rst_btn(rst_n), .vs_in(vs), .pb_in(pb),
        .led_main(m), .led_side(s), .led_walk(w));

    traffic_checker #(.NAME("top"), .FAIR_ARB(1), .LATENCY(2)) chk (
        .clk(clk), .rst(dut.rst), .tick(dut.tick), .VS(vs), .PB(pb),
        .light_main(m), .light_side(s), .walk(w));

    initial begin
        #23 rst_n = 1;
        for (i = 0; i < 20000; i = i + 1) begin
            @(negedge clk);
            vs = ($random(seed) % 97)  == 0;
            pb = ($random(seed) % 131) == 0;
        end
        vs = 0; pb = 0;
        repeat (2000) @(negedge clk);
        $display("top: %0d samples, %0d walk / %0d side phases, %0d error(s)",
                 chk.checks, chk.n_walk, chk.n_side, chk.errors);
        if (chk.errors == 0 && chk.n_walk > 0 && chk.n_side > 0) begin
            $display("PASS");
            $finish;
        end else
            $fatal(1, "traffic_top smoke test failed");
    end
endmodule
