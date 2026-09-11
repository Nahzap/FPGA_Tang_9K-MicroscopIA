// AD7606 + LCD + 2× DRV8871. top solo cablea. orch manda.
// enc_pos en sample_done. pwr_lim entre map_pot y pwm_drv.
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
    wire        x_fwd_l, x_rev_l, y_fwd_l, y_rev_l;
    wire [10:0] x_cmp_l, y_cmp_l;

    wire        ex_moved, ey_moved;
    wire        ex_lp, ex_ln, ey_lp, ey_ln;
    wire        ex_neg, ey_neg;
    wire [6:0]  ex_pct, ey_pct;
    wire [3:0]  ex_hun, ex_ten, ex_one, ey_hun, ey_ten, ey_one;

    wire [10:0] pwm_cnt;
    wire        pwm_en;
    wire        adc_go, map_go, fmt_go, snap_pwm, snap_lcd;
    wire        maps_idle;

    reg  [15:0] pix_q;
    reg  [16:0] d0, d1, d2, d3;
    reg  [2:0]  sstatus;
    reg  [15:0] sconv;
    reg         svalid;
    reg         sbusy;
    reg         sdout;
    reg         sx_neg, sy_neg;
    reg  [3:0]  sx_hun, sx_ten, sx_one, sy_hun, sy_ten, sy_one;
    reg         sx_moved, sy_moved, sx_lock, sy_lock;
    reg         lx_fwd, lx_rev, ly_fwd, ly_rev;
    reg  [10:0] lx_cmp, ly_cmp;

    initial begin
        pix_q   = 16'd0;
        d0 = 17'd0; d1 = 17'd0; d2 = 17'd0; d3 = 17'd0;
        sstatus = 3'd1;
        sconv   = 16'd0;
        svalid  = 1'b0;
        sbusy   = 1'b0;
        sdout   = 1'b1;
        sx_neg = 1'b0; sy_neg = 1'b0;
        sx_hun = 4'd0; sx_ten = 4'd0; sx_one = 4'd0;
        sy_hun = 4'd0; sy_ten = 4'd0; sy_one = 4'd0;
        sx_moved = 1'b0; sy_moved = 1'b0;
        sx_lock = 1'b0; sy_lock = 1'b0;
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

    enc_pos u_enc_x (
        .clk     (clk),
        .sample  (sample_done),
        .raw_a   (ch4),
        .raw_b   (ch5),
        .cmd_fwd (x_fwd),
        .cmd_rev (x_rev),
        .cmd_on  (x_cmp != 11'd0),
        .moved   (ex_moved),
        .lock_p  (ex_lp),
        .lock_n  (ex_ln),
        .pos_neg (ex_neg),
        .pct     (ex_pct),
        .hun     (ex_hun),
        .ten     (ex_ten),
        .one     (ex_one)
    );

    enc_pos u_enc_y (
        .clk     (clk),
        .sample  (sample_done),
        .raw_a   (ch6),
        .raw_b   (ch7),
        .cmd_fwd (y_fwd),
        .cmd_rev (y_rev),
        .cmd_on  (y_cmp != 11'd0),
        .moved   (ey_moved),
        .lock_p  (ey_lp),
        .lock_n  (ey_ln),
        .pos_neg (ey_neg),
        .pct     (ey_pct),
        .hun     (ey_hun),
        .ten     (ey_ten),
        .one     (ey_one)
    );

    pwr_lim u_lim_x (
        .fwd_i   (x_fwd),
        .rev_i   (x_rev),
        .cmp_i   (x_cmp),
        .pct     (ex_pct),
        .pos_neg (ex_neg),
        .lock_p  (ex_lp),
        .lock_n  (ex_ln),
        .fwd_o   (x_fwd_l),
        .rev_o   (x_rev_l),
        .cmp_o   (x_cmp_l)
    );

    pwr_lim u_lim_y (
        .fwd_i   (y_fwd),
        .rev_i   (y_rev),
        .cmp_i   (y_cmp),
        .pct     (ey_pct),
        .pos_neg (ey_neg),
        .lock_p  (ey_lp),
        .lock_n  (ey_ln),
        .fwd_o   (y_fwd_l),
        .rev_o   (y_rev_l),
        .cmp_o   (y_cmp_l)
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
            lx_fwd <= x_fwd_l;
            lx_rev <= x_rev_l;
            lx_cmp <= x_cmp_l;
            ly_fwd <= y_fwd_l;
            ly_rev <= y_rev_l;
            ly_cmp <= y_cmp_l;
        end
        if (snap_lcd) begin
            d0      <= p0;
            d1      <= p1;
            d2      <= p2;
            d3      <= p3;
            sstatus <= adc_status;
            sconv   <= conv_cnt;
            svalid  <= regs_valid;
            sbusy   <= probe_busy;
            sdout   <= probe_dout;
            sx_neg   <= ex_neg;
            sx_hun   <= ex_hun;
            sx_ten   <= ex_ten;
            sx_one   <= ex_one;
            sx_moved <= ex_moved;
            sx_lock  <= ex_lp | ex_ln;
            sy_neg   <= ey_neg;
            sy_hun   <= ey_hun;
            sy_ten   <= ey_ten;
            sy_one   <= ey_one;
            sy_moved <= ey_moved;
            sy_lock  <= ey_lp | ey_ln;
        end
    end

    text_pwm u_text (
        .pix_x      (pix_x),
        .pix_y      (pix_y),
        .p0         (d0),
        .p1         (d1),
        .p2         (d2),
        .p3         (d3),
        .status     (sstatus),
        .conv_cnt   (sconv),
        .paused     (paused),
        .regs_valid (svalid),
        .busy_pin   (sbusy),
        .dout_pin   (sdout),
        .x_neg      (sx_neg),
        .x_hun      (sx_hun),
        .x_ten      (sx_ten),
        .x_one      (sx_one),
        .x_moved    (sx_moved),
        .x_lock     (sx_lock),
        .y_neg      (sy_neg),
        .y_hun      (sy_hun),
        .y_ten      (sy_ten),
        .y_one      (sy_one),
        .y_moved    (sy_moved),
        .y_lock     (sy_lock),
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
