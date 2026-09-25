// AD7606 + LCD + 2× DRV8871. One controller per motor.
// Serial protocol of Lab 206 on pins 17 (TX) and 18 (RX), 115200 8N1.
module top (
    input  wire clk,
    input  wire btn0_n,
    input  wire btn1_n,
    input  wire adc_busy,
    input  wire adc_dout,
    input  wire uart_rx,
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
    output wire led,
    output wire uart_tx
);
    wire        pause_toggle;
    wire        paused;
    wire        adc_idle;
    wire        regs_valid;
    wire        sample_done;
    wire        fmt_idle;
    wire [2:0]  adc_status;
    wire        probe_busy;
    wire        probe_dout;
    wire [15:0] conv_cnt;
    wire [7:0]  pix_x;
    wire [7:0]  pix_y;
    wire [15:0] pixel;

    wire [15:0] ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7;
    wire [16:0] p0, p1, p2, p3, p4, p5, p6, p7;

    wire        x_fwd, x_rev, x_brake, y_fwd, y_rev, y_brake;
    wire [10:0] x_cmp, y_cmp;
    wire signed [9:0] x_rep, y_rep;
    wire [11:0] x_sens, y_sens;
    wire        x_moved, y_moved, x_gate, y_gate;
    wire [3:0]  x_sth, x_shu, x_ste, x_son;
    wire [3:0]  y_sth, y_shu, y_ste, y_son;

    wire [1:0]        mode;
    wire signed [9:0] pwr_a, pwr_b;
    wire [11:0]       ref_x, ref_y;
    wire [5:0]        gate_e;
    wire              inv_x, inv_y;

    wire [10:0] pwm_cnt;
    wire        pwm_en;
    wire        adc_go, map_go, fmt_go, snap_pwm, snap_lcd;
    reg         map_idle = 1'b1;

    reg  [15:0] pix_q;
    reg  [16:0] d0, d1, d2, d3;
    reg  [2:0]  sstatus;
    reg  [15:0] sconv;
    reg         svalid;
    reg         sbusy;
    reg         sdout;
    reg         sx_neg, sy_neg;
    reg         sx_moved, sy_moved;
    reg  [3:0]  sx_sth, sx_shu, sx_ste, sx_son;
    reg  [3:0]  sy_sth, sy_shu, sy_ste, sy_son;
    reg         lx_fwd, lx_rev, lx_brake, ly_fwd, ly_rev, ly_brake;
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
        sx_moved = 1'b0; sy_moved = 1'b0;
        sx_sth = 4'd0; sx_shu = 4'd0; sx_ste = 4'd0; sx_son = 4'd0;
        sy_sth = 4'd0; sy_shu = 4'd0; sy_ste = 4'd0; sy_son = 4'd0;
        lx_fwd = 1'b0; lx_rev = 1'b0; lx_brake = 1'b0;
        ly_fwd = 1'b0; ly_rev = 1'b0; ly_brake = 1'b0;
        lx_cmp = 11'd0; ly_cmp = 11'd0;
    end

    assign adc_convstb = adc_convst;
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
        .map_idle (map_idle),
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
        .busy_s      (),
        .dout_s      (),
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
        .r0    (),
        .r1    (),
        .r2    (),
        .r3    (),
        .r4    (),
        .r5    (),
        .r6    (),
        .r7    ()
    );

    // X hears V7/V8 (ch6/ch7). Y hears V5/V6 (ch4/ch5).
    axis_ctl u_x (
        .clk      (clk),
        .sample   (sample_done),
        .mode     (mode),
        .auto_pwr (pwr_a),
        .ref_s    (ref_x),
        .gate_e   (gate_e),
        .inv      (inv_x),
        .pot      (ch2),
        .raw_a    (ch6),
        .raw_b    (ch7),
        .fwd      (x_fwd),
        .rev      (x_rev),
        .brake    (x_brake),
        .cmp      (x_cmp),
        .rep      (x_rep),
        .sensor   (x_sens),
        .moved    (x_moved),
        .in_gate  (x_gate),
        .spd_th   (x_sth),
        .spd_hu   (x_shu),
        .spd_te   (x_ste),
        .spd_on   (x_son)
    );

    axis_ctl u_y (
        .clk      (clk),
        .sample   (sample_done),
        .mode     (mode),
        .auto_pwr (pwr_b),
        .ref_s    (ref_y),
        .gate_e   (gate_e),
        .inv      (inv_y),
        .pot      (ch3),
        .raw_a    (ch4),
        .raw_b    (ch5),
        .fwd      (y_fwd),
        .rev      (y_rev),
        .brake    (y_brake),
        .cmp      (y_cmp),
        .rep      (y_rep),
        .sensor   (y_sens),
        .moved    (y_moved),
        .in_gate  (y_gate),
        .spd_th   (y_sth),
        .spd_hu   (y_shu),
        .spd_te   (y_ste),
        .spd_on   (y_son)
    );

    com_ctrl u_com (
        .clk       (clk),
        .rx        (uart_rx),
        .tx        (uart_tx),
        .rep_a     (x_rep),
        .rep_b     (y_rep),
        .sensor1   (y_sens),
        .sensor2   (x_sens),
        .in_gate_a (x_gate),
        .in_gate_b (y_gate),
        .mode      (mode),
        .pwr_a     (pwr_a),
        .pwr_b     (pwr_b),
        .ref_x     (ref_x),
        .ref_y     (ref_y),
        .gate_e    (gate_e),
        .inv_x     (inv_x),
        .inv_y     (inv_y)
    );

    pwm_timer u_pwm_tmr (
        .clk (clk),
        .cnt (pwm_cnt)
    );

    pwm_drv u_pwm_x (
        .clk    (clk),
        .enable (pwm_en),
        .brake  (lx_brake),
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
        .brake  (ly_brake),
        .fwd    (ly_fwd),
        .rev    (ly_rev),
        .cmp    (ly_cmp),
        .cnt    (pwm_cnt),
        .in1    (pwm_y_in1),
        .in2    (pwm_y_in2)
    );

    always @(posedge clk) begin
        if (map_go)
            map_idle <= 1'b0;
        else
            map_idle <= 1'b1;

        pix_q <= pixel;
        if (snap_pwm) begin
            lx_fwd   <= x_fwd;
            lx_rev   <= x_rev;
            lx_brake <= x_brake;
            lx_cmp   <= x_cmp;
            ly_fwd   <= y_fwd;
            ly_rev   <= y_rev;
            ly_brake <= y_brake;
            ly_cmp   <= y_cmp;
        end
        if (snap_lcd) begin
            d0       <= p0;
            d1       <= p1;
            d2       <= p2;
            d3       <= p3;
            sstatus  <= adc_status;
            sconv    <= conv_cnt;
            svalid   <= regs_valid;
            sbusy    <= probe_busy;
            sdout    <= probe_dout;
            sx_neg   <= x_rev;
            sx_moved <= x_moved;
            sy_neg   <= y_rev;
            sy_moved <= y_moved;
            sx_sth   <= x_sth;
            sx_shu   <= x_shu;
            sx_ste   <= x_ste;
            sx_son   <= x_son;
            sy_sth   <= y_sth;
            sy_shu   <= y_shu;
            sy_ste   <= y_ste;
            sy_son   <= y_son;
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
        .x_hun      (4'd0),
        .x_ten      (4'd0),
        .x_one      (4'd0),
        .x_moved    (sx_moved),
        .x_lock     (1'b0),
        .x_sth      (sx_sth),
        .x_shu      (sx_shu),
        .x_ste      (sx_ste),
        .x_son      (sx_son),
        .y_neg      (sy_neg),
        .y_hun      (4'd0),
        .y_ten      (4'd0),
        .y_one      (4'd0),
        .y_moved    (sy_moved),
        .y_lock     (1'b0),
        .y_sth      (sy_sth),
        .y_shu      (sy_shu),
        .y_ste      (sy_ste),
        .y_son      (sy_son),
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
