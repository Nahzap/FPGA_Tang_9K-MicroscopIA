// Capítulo 6: AD7606 + 4 PWM. top solo cablea. orch manda.
// map X, map Y y format_scan arrancan juntos. El PWM no espera a la LCD.
module top (
    input  wire clk,
    input  wire btn0_n,
    input  wire btn1_n,
    input  wire adc_busy,
    input  wire adc_dout,
    output wire adc_convst,
    output wire adc_convstb,
    output wire adc_reset,
    output wire adc_cs,
    output wire adc_sclk,
    output wire pwm_x_in1,
    output wire pwm_x_in2,
    output wire pwm_y_in1,
    output wire pwm_y_in2,
    output wire lcd_resetn,
    output wire lcd_clk,
    output wire lcd_cs,
    output wire lcd_rs,
    output wire lcd_data,
    output wire led
);
    wire        pause_toggle;
    wire        paused;
    wire        adc_idle;
    wire        regs_valid;
    wire        sample_done;
    wire        fmt_idle;
    wire        map_x_idle;
    wire        map_y_idle;
    wire [2:0]  adc_status;
    wire        busy_live;
    wire        dout_live;
    wire        probe_busy;
    wire        probe_dout;
    wire [15:0] conv_cnt;
    wire [7:0]  pix_x;
    wire [7:0]  pix_y;
    wire [15:0] pixel;

    wire [15:0] ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7;
    wire [16:0] p0, p1, p2, p3, p4, p5, p6, p7;
    wire [15:0] r0, r1, r2, r3, r4, r5, r6, r7;

    wire        x_fwd, x_rev, y_fwd, y_rev;
    wire [10:0] x_cmp, y_cmp;
    wire [6:0]  x_pct, y_pct;
    wire [3:0]  x_hun, x_ten, x_one, y_hun, y_ten, y_one;
    wire [10:0] pwm_cnt;
    wire        pwm_en;
    wire        adc_go, map_go, fmt_go, snap_pwm, snap_lcd;
    wire        maps_idle;

    reg  [15:0] pix_q;
    reg  [15:0] s0, s1, s2, s3, s4, s5, s6, s7;
    reg  [16:0] d0, d1, d2, d3, d4, d5, d6, d7;
    reg  [2:0]  sstatus;
    reg  [15:0] sconv;
    reg         svalid;
    reg         sbusy;
    reg         sdout;
    reg         sx_fwd, sx_rev, sy_fwd, sy_rev;
    reg  [3:0]  sx_hun, sx_ten, sx_one, sy_hun, sy_ten, sy_one;
    reg         lx_fwd, lx_rev, ly_fwd, ly_rev;
    reg  [10:0] lx_cmp, ly_cmp;

    initial begin
        pix_q   = 16'd0;
        s0 = 16'd0; s1 = 16'd0; s2 = 16'd0; s3 = 16'd0;
        s4 = 16'd0; s5 = 16'd0; s6 = 16'd0; s7 = 16'd0;
        d0 = 17'd0; d1 = 17'd0; d2 = 17'd0; d3 = 17'd0;
        d4 = 17'd0; d5 = 17'd0; d6 = 17'd0; d7 = 17'd0;
        sstatus = 3'd1;
        sconv   = 16'd0;
        svalid  = 1'b0;
        sbusy   = 1'b0;
        sdout   = 1'b1;
        sx_fwd = 1'b0; sx_rev = 1'b0;
        sy_fwd = 1'b0; sy_rev = 1'b0;
        sx_hun = 4'd0; sx_ten = 4'd0; sx_one = 4'd0;
        sy_hun = 4'd0; sy_ten = 4'd0; sy_one = 4'd0;
        lx_fwd = 1'b0; lx_rev = 1'b0;
        ly_fwd = 1'b0; ly_rev = 1'b0;
        lx_cmp = 11'd0; ly_cmp = 11'd0;
    end

    assign adc_convstb = adc_convst;
    assign maps_idle   = map_x_idle && map_y_idle;
    assign led         = paused ? 1'b0 : ~conv_cnt[0];

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

    orch u_orch (
        .clk      (clk),
        .paused   (paused),
        .adc_idle (adc_idle),
        .adc_done (sample_done),
        .map_idle (maps_idle),
        .fmt_idle (fmt_idle),
        .adc_go   (adc_go),
        .map_go   (map_go),
        .fmt_go   (fmt_go),
        .snap_pwm (snap_pwm),
        .snap_lcd (snap_lcd),
        .pwm_en   (pwm_en)
    );

    adc_master u_adc (
        .clk         (clk),
        .start       (adc_go),
        .paused      (paused),
        .adc_busy    (adc_busy),
        .adc_dout    (adc_dout),
        .adc_convst  (adc_convst),
        .adc_reset   (adc_reset),
        .adc_cs      (adc_cs),
        .adc_sclk    (adc_sclk),
        .idle        (adc_idle),
        .regs_valid  (regs_valid),
        .sample_done (sample_done),
        .status      (adc_status),
        .busy_s      (busy_live),
        .dout_s      (dout_live),
        .probe_busy  (probe_busy),
        .probe_dout  (probe_dout),
        .conv_cnt    (conv_cnt),
        .ch0         (ch0),
        .ch1         (ch1),
        .ch2         (ch2),
        .ch3         (ch3),
        .ch4         (ch4),
        .ch5         (ch5),
        .ch6         (ch6),
        .ch7         (ch7)
    );

    format_scan u_fmt (
        .clk   (clk),
        .start (fmt_go),
        .ch0   (ch0),
        .ch1   (ch1),
        .ch2   (ch2),
        .ch3   (ch3),
        .ch4   (ch4),
        .ch5   (ch5),
        .ch6   (ch6),
        .ch7   (ch7),
        .idle  (fmt_idle),
        .p0    (p0),
        .p1    (p1),
        .p2    (p2),
        .p3    (p3),
        .p4    (p4),
        .p5    (p5),
        .p6    (p6),
        .p7    (p7),
        .r0    (r0),
        .r1    (r1),
        .r2    (r2),
        .r3    (r3),
        .r4    (r4),
        .r5    (r5),
        .r6    (r6),
        .r7    (r7)
    );

    map_pot u_map_x (
        .clk   (clk),
        .start (map_go),
        .raw   (ch2),
        .idle  (map_x_idle),
        .fwd   (x_fwd),
        .rev   (x_rev),
        .cmp   (x_cmp),
        .pct   (x_pct),
        .hun   (x_hun),
        .ten   (x_ten),
        .one   (x_one)
    );

    map_pot u_map_y (
        .clk   (clk),
        .start (map_go),
        .raw   (ch3),
        .idle  (map_y_idle),
        .fwd   (y_fwd),
        .rev   (y_rev),
        .cmp   (y_cmp),
        .pct   (y_pct),
        .hun   (y_hun),
        .ten   (y_ten),
        .one   (y_one)
    );

    pwm_timer u_pwm_tmr (
        .clk (clk),
        .cnt (pwm_cnt)
    );

    pwm_drv u_pwm_x (
        .clk    (clk),
        .enable (pwm_en),
        .fwd    (lx_fwd),
        .rev    (lx_rev),
        .cmp    (lx_cmp),
        .cnt    (pwm_cnt),
        .in1    (pwm_x_in1),
        .in2    (pwm_x_in2)
    );

    pwm_drv u_pwm_y (
        .clk    (clk),
        .enable (pwm_en),
        .fwd    (ly_fwd),
        .rev    (ly_rev),
        .cmp    (ly_cmp),
        .cnt    (pwm_cnt),
        .in1    (pwm_y_in1),
        .in2    (pwm_y_in2)
    );

    always @(posedge clk) begin
        pix_q <= pixel;
        if (snap_pwm) begin
            lx_fwd <= x_fwd;
            lx_rev <= x_rev;
            lx_cmp <= x_cmp;
            ly_fwd <= y_fwd;
            ly_rev <= y_rev;
            ly_cmp <= y_cmp;
            sx_fwd <= x_fwd;
            sx_rev <= x_rev;
            sx_hun <= x_hun;
            sx_ten <= x_ten;
            sx_one <= x_one;
            sy_fwd <= y_fwd;
            sy_rev <= y_rev;
            sy_hun <= y_hun;
            sy_ten <= y_ten;
            sy_one <= y_one;
        end
        if (snap_lcd) begin
            s0      <= r0;
            s1      <= r1;
            s2      <= r2;
            s3      <= r3;
            s4      <= r4;
            s5      <= r5;
            s6      <= r6;
            s7      <= r7;
            d0      <= p0;
            d1      <= p1;
            d2      <= p2;
            d3      <= p3;
            d4      <= p4;
            d5      <= p5;
            d6      <= p6;
            d7      <= p7;
            sstatus <= adc_status;
            sconv   <= conv_cnt;
            svalid  <= regs_valid;
            sbusy   <= probe_busy;
            sdout   <= probe_dout;
        end
    end

    text_pwm u_text (
        .pix_x      (pix_x),
        .pix_y      (pix_y),
        .ch0        (s0),
        .ch1        (s1),
        .ch2        (s2),
        .ch3        (s3),
        .ch4        (s4),
        .ch5        (s5),
        .ch6        (s6),
        .ch7        (s7),
        .p0         (d0),
        .p1         (d1),
        .p2         (d2),
        .p3         (d3),
        .p4         (d4),
        .p5         (d5),
        .p6         (d6),
        .p7         (d7),
        .status     (sstatus),
        .conv_cnt   (sconv),
        .paused     (paused),
        .regs_valid (svalid),
        .busy_pin   (sbusy),
        .dout_pin   (sdout),
        .x_fwd      (sx_fwd),
        .x_rev      (sx_rev),
        .x_hun      (sx_hun),
        .x_ten      (sx_ten),
        .x_one      (sx_one),
        .y_fwd      (sy_fwd),
        .y_rev      (sy_rev),
        .y_hun      (sy_hun),
        .y_ten      (sy_ten),
        .y_one      (sy_one),
        .pixel      (pixel)
    );

    lcd_master u_lcd (
        .clk        (clk),
        .pixel      (pix_q),
        .pix_x      (pix_x),
        .pix_y      (pix_y),
        .init_done  (),
        .frame_done (),
        .lcd_resetn (lcd_resetn),
        .lcd_clk    (lcd_clk),
        .lcd_cs     (lcd_cs),
        .lcd_rs     (lcd_rs),
        .lcd_data   (lcd_data)
    );
endmodule
