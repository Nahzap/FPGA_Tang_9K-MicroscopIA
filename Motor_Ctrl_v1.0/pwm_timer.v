// Timebase for both DRV8871 bridges. One job: count 0 .. PERIOD-1 at 27 MHz.
// PERIOD=1350 => 20.000 kHz. No ADC, no pins.
module pwm_timer #(
    parameter integer PERIOD = 1350
) (
    input  wire        clk,
    output reg  [10:0] cnt
);
    localparam [10:0] LAST = PERIOD[10:0] - 11'd1;

    initial cnt = 11'd0;

    always @(posedge clk) begin
        if (cnt == LAST)
            cnt <= 11'd0;
        else
            cnt <= cnt + 11'd1;
    end
endmodule
