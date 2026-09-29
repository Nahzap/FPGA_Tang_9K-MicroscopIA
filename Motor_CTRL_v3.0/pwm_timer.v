`include "config.vh"
// Timebase for both DRV8871 bridges. Counts 0 .. PERIOD-1 at the board clock.
// PERIOD = CFG_CLK_HZ / CFG_PWM_HZ (540 => 50 kHz at 27 MHz).
module pwm_timer #(
    parameter integer PERIOD = `CFG_PWM_PERIOD
) (
    input  wire        clk,
    output reg  [15:0] cnt
);
    localparam [15:0] LAST = PERIOD - 1;

    initial cnt = 16'd0;

    always @(posedge clk) begin
        if (cnt == LAST)
            cnt <= 16'd0;
        else
            cnt <= cnt + 16'd1;
    end
endmodule
