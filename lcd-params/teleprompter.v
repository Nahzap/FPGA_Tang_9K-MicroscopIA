// Pixel-smooth vertical crawl. Advances only when the LCD raster
// reports frame_done AND the skip counter says line_advance_ok.
// No free-running timer racing the SPI FSM.
module teleprompter #(
    parameter [7:0] SCROLL_MAX     = 8'd207, // N_LINES*FONT_H - 1 (26*8-1)
    parameter [3:0] FRAMES_PER_PX  = 4'd6
) (
    input  wire       clk,
    input  wire       init_done,
    input  wire       frame_done,
    input  wire       paused,
    output reg  [7:0] scroll_y
);
    reg [3:0] frame_div = 4'd0;

    wire line_advance_ok = (frame_div == (FRAMES_PER_PX - 4'd1));

    initial scroll_y = 8'd0;

    always @(posedge clk) begin
        if (!init_done) begin
            scroll_y  <= 8'd0;
            frame_div <= 4'd0;
        end else if (frame_done && !paused) begin
            if (line_advance_ok) begin
                frame_div <= 4'd0;
                if (scroll_y == SCROLL_MAX)
                    scroll_y <= 8'd0;
                else
                    scroll_y <= scroll_y + 8'd1;
            end else begin
                frame_div <= frame_div + 4'd1;
            end
        end
    end
endmodule
