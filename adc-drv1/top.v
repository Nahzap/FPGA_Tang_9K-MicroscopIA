// One DRV8871. top only wires. orch commands. V3 = pot. Pins 40/35 = IN1/IN2.
// Pins 41/42 stay 00 so a second isolator/driver stays asleep.
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
    output wire pwm_in1,
    output wire pwm_in2,
    output wire hold_in1,
    output wire hold_in2,
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
    wire        map_idle;
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

    wire        m_fwd, m_rev;
    wire [10:0] m_cmp;
    wire [6:0]  m_pct;
    wire [3:0]  m_hun, m_ten, m_one;
    wire [10:0] pwm_cnt;
    wire        pwm_en;
    wire        adc_go, map_go, fmt_go, snap_pwm, snap_lcd;

    reg  [15:0] s0, s1, s2, s3, s4, s5, s6, s7;
    reg  [16:0] d0, d1, d2, d3, d4, d5, d6, d7;
    reg  [2:0]  sstatus;
    reg  [15:0] sconv;
    reg         svalid;
    reg         sbusy;
    reg         sdout;
    reg         sfwd, srev;
    reg  [3:0]  shun, sten, sone;
    reg         lfwd, lrev;
    reg  [10:0] lcmp;

    initial begin
        s0 = 16'd0; s1 = 16'd0; s2 = 16'd0; s3 = 16'd0;
        s4 = 16'd0; s5 = 16'd0; s6 = 16'd0; s7 = 16'd0;
        d0 = 17'd0; d1 = 17'd0; d2 = 17'd0; d3 = 17'd0;
        d4 = 17'd0; d5 = 17'd0; d6 = 17'd0; d7 = 17'd0;
        sstatus = 3'd1;
        sconv   = 16'd0;
        svalid  = 1'b0;
        sbusy   = 1'b0;
        sdout   = 1'b1;
        sfwd = 1'b0; srev = 1'b0;
        shun = 4'd0; sten = 4'd0; sone = 4'd0;
        lfwd = 1'b0; lrev = 1'b0;
        lcmp = 11'd0;
    end

    assign adc_convstb = adc_convst;
    assign hold_in1    = 1'b0;
    assign hold_in2    = 1'b0;
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

    map_pot u_map (
        .clk   (clk),
        .start (map_go),
        .raw   (ch2),
        .idle  (map_idle),
        .fwd   (m_fwd),
        .rev   (m_rev),
        .cmp   (m_cmp),
        .pct   (m_pct),
        .hun   (m_hun),
        .ten   (m_ten),
        .one   (m_one)
    );

    pwm_timer u_tmr (
        .clk (clk),
        .cnt (pwm_cnt)
    );

    pwm_drv u_drv (
        .clk    (clk),
        .enable (pwm_en),
        .fwd    (lfwd),
        .rev    (lrev),
        .cmp    (lcmp),
        .cnt    (pwm_cnt),
        .in1    (pwm_in1),
        .in2    (pwm_in2)
    );

    always @(posedge clk) begin
        if (snap_pwm) begin
            lfwd <= m_fwd;
            lrev <= m_rev;
            lcmp <= m_cmp;
            sfwd <= m_fwd;
            srev <= m_rev;
            shun <= m_hun;
            sten <= m_ten;
            sone <= m_one;
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

    text_drv u_text (
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
        .fwd        (sfwd),
        .rev        (srev),
        .hun        (shun),
        .ten        (sten),
        .one        (sone),
        .pixel      (pixel)
    );

    lcd_master u_lcd (
        .clk        (clk),
        .pixel      (pixel),
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
