// Pause latch: toggles only on the 1-cycle pause_toggle pulse.
module pause_reg (
    input  wire clk,
    input  wire pause_toggle,
    output reg  paused
);
    initial paused = 1'b0;

    always @(posedge clk) begin
        if (pause_toggle)
            paused <= ~paused;
    end
endmodule
