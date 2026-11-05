`timescale 1ns/1ps
module traffic_ctrl_tb;
    reg clk=0, rst=1, VS=0, PB=0;
    wire [2:0] light_main, light_side, ref_main, ref_side;
    wire walk, ref_walk;
    integer comparisons=0;
    integer i;

    traffic_ctrl dut(.clk(clk),.rst(rst),.VS(VS),.PB(PB),
        .light_main(light_main),.light_side(light_side),.walk(walk));
    traffic_ctrl_ref ref_model(.clk(clk),.rst(rst),.VS(VS),.PB(PB),
        .light_main(ref_main),.light_side(ref_side),.walk(ref_walk));

    always #5 clk=~clk;

    always @(negedge clk) begin
        if (!rst) begin
            comparisons = comparisons + 1;
            if ({light_main,light_side,walk} !== {ref_main,ref_side,ref_walk}) begin
                $display("FAIL at %0t: DUT=%b%b%b REF=%b%b%b",
                    $time,light_main,light_side,walk,ref_main,ref_side,ref_walk);
                $fatal(1,"DUT/reference mismatch");
            end
        end
    end

    initial begin
        $dumpfile("traffic_ctrl.vcd");
        $dumpvars(0,traffic_ctrl_tb);
        #12 rst=0;
        repeat(75) @(negedge clk);
        // Vehicle request.
        VS=1; @(negedge clk); VS=0;
        repeat(160) @(negedge clk);
        // Pedestrian request.
        PB=1; @(negedge clk); PB=0;
        repeat(160) @(negedge clk);
        // Simultaneous requests; pedestrian has priority.
        VS=1; PB=1; @(negedge clk); VS=0; PB=0;
        repeat(220) @(negedge clk);
        // Randomized requests.
        for (i=0;i<500;i=i+1) begin
            VS=($random%7==0);
            PB=($random%9==0);
            @(negedge clk);
        end
        VS=0; PB=0;
        repeat(20) @(negedge clk);
        $display("PASS: %0d output comparisons completed.",comparisons);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1,"Global simulation timeout");
    end
endmodule
