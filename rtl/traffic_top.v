`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// traffic_top - board-level wrapper (FPGA)
//
//   * Generates a 1-cycle `tick` pulse at TICK_HZ from the board clock, so the
//     phase durations in traffic_ctrl_core are measured in seconds (default)
//     instead of clock periods. Single clock domain - no derived clocks.
//   * Reset: asynchronous assert, synchronous de-assert. RST_ACTIVE_LOW selects
//     the polarity of the board's reset button.
//   * VS / PB come from switches/buttons, so the 2-flop synchronizer is on.
//   * Fair arbitration is on so a busy crossing cannot starve the side road.
// -----------------------------------------------------------------------------
module traffic_top #(
    parameter integer CLK_HZ         = 50_000_000,
    parameter integer TICK_HZ        = 1,
    parameter integer RST_ACTIVE_LOW = 1
) (
    input  wire       clk,
    input  wire       rst_btn,
    input  wire       vs_in,      // side-road vehicle sensor / switch
    input  wire       pb_in,      // pedestrian push button
    output wire [2:0] led_main,   // {green, yellow, red}
    output wire [2:0] led_side,   // {green, yellow, red}
    output wire       led_walk
);
    localparam integer DIV = (CLK_HZ / TICK_HZ > 0) ? CLK_HZ / TICK_HZ : 1;
    localparam integer DW  = (DIV > 1) ? $clog2(DIV) : 1;

    // ---------------------------------------------------- reset synchronizer
    wire rst_async = RST_ACTIVE_LOW ? ~rst_btn : rst_btn;
    reg  [1:0] rst_sync;
    always @(posedge clk or posedge rst_async)
        if (rst_async) rst_sync <= 2'b11;
        else           rst_sync <= {rst_sync[0], 1'b0};
    wire rst = rst_sync[1];

    // -------------------------------------------------------- tick prescaler
    reg [DW-1:0] div_cnt;
    reg          tick;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            div_cnt <= {DW{1'b0}};
            tick    <= 1'b0;
        end else if (div_cnt == DIV - 1) begin
            div_cnt <= {DW{1'b0}};
            tick    <= 1'b1;
        end else begin
            div_cnt <= div_cnt + 1'b1;
            tick    <= 1'b0;
        end
    end

    traffic_ctrl_core #(
        .SYNC_INPUTS(1),
        .FAIR_ARB   (1)
    ) u_ctrl (
        .clk(clk), .rst(rst), .tick(tick),
        .VS(vs_in), .PB(pb_in),
        .light_main(led_main), .light_side(led_side), .walk(led_walk)
    );
endmodule
