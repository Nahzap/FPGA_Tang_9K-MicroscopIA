// Tang Nano 9K — LCD teleprompter of board parameters.
// Single 27 MHz domain. Pause/resume from either user button.
module top (
    input  wire clk,
    input  wire btn0_n,
    input  wire btn1_n,
    output wire lcd_resetn,
    output wire lcd_clk,
    output wire lcd_cs,
    output wire lcd_rs,
    output wire lcd_data,
    output wire led
);
    wire        pause_toggle;
    wire        paused;
    wire        init_done;
    wire        frame_done;
    wire [7:0]  pix_x;
    wire [7:0]  pix_y;
    wire [7:0]  scroll_y;
    wire [15:0] pixel;

    btn_sync u_btn (
        .clk          (clk),
        .btn0_n       (btn0_n),
        .btn1_n       (btn1_n),
        .pause_toggle (pause_toggle)
    );

    pause_reg u_pause (
        .clk          (clk),
        .pause_toggle (pause_toggle),
        .paused       (paused)
    );

    teleprompter u_scroll (
        .clk        (clk),
        .init_done  (init_done),
        .frame_done (frame_done),
        .paused     (paused),
        .scroll_y   (scroll_y)
    );

    text_source u_text (
        .pix_x    (pix_x),
        .pix_y    (pix_y),
        .scroll_y (scroll_y),
        .paused   (paused),
        .pixel    (pixel)
    );

    lcd_master u_lcd (
        .clk        (clk),
        .pixel      (pixel),
        .pix_x      (pix_x),
        .pix_y      (pix_y),
        .init_done  (init_done),
        .frame_done (frame_done),
        .lcd_resetn (lcd_resetn),
        .lcd_clk    (lcd_clk),
        .lcd_cs     (lcd_cs),
        .lcd_rs     (lcd_rs),
        .lcd_data   (lcd_data)
    );

    // LED2 active-low: lit while RUN, off while PAUSA.
    assign led = paused;
endmodule
