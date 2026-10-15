`include "config.vh"
// One PWM timebase for both bridges: CFG_PWM_PERIOD clocks, 0..PERIOD-1.
// cnt_y runs half a period behind cnt_x, so X and Y never switch on the
// same clock and their current steps do not add on the 12 V rail.
module pwm_timer #(
    parameter integer PERIOD = `CFG_PWM_PERIOD
) (
    input  wire       clk,
    output reg  [9:0] cnt_x,
    output reg  [9:0] cnt_y
);
    localparam [9:0] LAST = PERIOD - 1;
    localparam [9:0] HALF = PERIOD / 2;

    initial begin
        cnt_x = 10'd0;
        cnt_y = HALF;
    end

    always @(posedge clk) begin
        cnt_x <= (cnt_x == LAST) ? 10'd0 : cnt_x + 10'd1;
        cnt_y <= (cnt_y == LAST) ? 10'd0 : cnt_y + 10'd1;
    end
endmodule
