// First image on the Tang Nano 9K 1.14" ST7789 SPI LCD:
// 24x15 grid of squares, turbo palette washing every ~150 ms.
module top (
    input  wire clk,
    output wire lcd_resetn,
    output wire lcd_clk,
    output wire lcd_cs,
    output wire lcd_rs,
    output wire lcd_data,
    output wire led
);
    // 150 ms @ 27 MHz
    localparam [22:0] PHASE_TICK = 23'd4_050_000;

    reg [22:0] phase_cnt = 23'd0;
    reg [3:0]  phase     = 4'd0;
    wire       running;

    always @(posedge clk) begin
        if (phase_cnt == PHASE_TICK - 23'd1) begin
            phase_cnt <= 23'd0;
            phase     <= phase + 4'd1;
        end else begin
            phase_cnt <= phase_cnt + 23'd1;
        end
    end

    lcd_st7789 u_lcd (
        .clk        (clk),
        .phase      (phase),
        .lcd_resetn (lcd_resetn),
        .lcd_clk    (lcd_clk),
        .lcd_cs     (lcd_cs),
        .lcd_rs     (lcd_rs),
        .lcd_data   (lcd_data),
        .running    (running)
    );

    // LED2 active-low: off during init, then follows palette phase.
    assign led = running ? ~phase[0] : 1'b1;
endmodule
