module top (
    input  wire       clk,
    output wire [5:0] led
);
    // 27 MHz. One-hot chase, 5 steps/s. LEDs active-low (0 = on).
    // led[5:0] → pins 10, 11, 13, 14, 15, 16 (LED1..LED6 / DONE on [0]).
    localparam [22:0] STEP = 23'd5_400_000; // 200 ms @ 27 MHz

    reg [22:0] cnt   = 23'd0;
    reg [5:0]  chase = 6'b000001;

    always @(posedge clk) begin
        if (cnt == STEP - 23'd1) begin
            cnt   <= 23'd0;
            chase <= {chase[4:0], chase[5]};
        end else begin
            cnt <= cnt + 23'd1;
        end
    end

    assign led = ~chase;
endmodule
