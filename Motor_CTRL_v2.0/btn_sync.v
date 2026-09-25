// 2FF synchronizer per button + arm-on-release.
// Either button (active-low) produces a 1-cycle pause_toggle pulse.
// No millisecond debounce counter; no async set/reset.
module btn_sync (
    input  wire clk,
    input  wire btn0_n,
    input  wire btn1_n,
    output reg  pause_toggle
);
    initial pause_toggle = 1'b0;

    reg [1:0] btn0_ff = 2'b11;
    reg [1:0] btn1_ff = 2'b11;
    reg       armed   = 1'b1;

    always @(posedge clk) begin
        btn0_ff <= {btn0_ff[0], btn0_n};
        btn1_ff <= {btn1_ff[0], btn1_n};
    end

    wire btn0_sync   = btn0_ff[1];
    wire btn1_sync   = btn1_ff[1];
    wire any_pressed = ~btn0_sync | ~btn1_sync;

    always @(posedge clk) begin
        pause_toggle <= 1'b0;
        if (any_pressed && armed) begin
            pause_toggle <= 1'b1;
            armed        <= 1'b0;
        end else if (!any_pressed) begin
            armed <= 1'b1;
        end
    end
endmodule
