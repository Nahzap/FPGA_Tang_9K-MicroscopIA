module top (
    input  wire clk,
    output wire led
);
    // 27 MHz. LED activo en bajo: 0 = encendido
    reg [24:0] cnt = 25'd0;
    always @(posedge clk)
        cnt <= cnt + 25'd1;
    assign led = ~cnt[24];
endmodule
