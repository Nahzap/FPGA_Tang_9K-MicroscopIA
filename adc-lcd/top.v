// Tang Nano 9K — AD7606 SPI + GY-91 MPU9250 I2C + ST7789 1.14" LCD.
// One 27 MHz domain. ADC burst then format_scan; IMU I2C then format_imu.
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
    inout  wire i2c_scl,
    inout  wire i2c_sda,
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
    wire        adc_idle;
    wire        regs_valid;
    wire        sample_done;
    wire        fmt_idle;
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

    wire        imu_idle;
    wire        imu_ready;
    wire        imu_sample;
    wire [1:0]  imu_status;
    wire [7:0]  whoami;
    wire [6:0]  dev_used;
    wire [15:0] ax, ay, az, gx, gy, gz;
    wire        scl_oe;
    wire        sda_oe;
    wire        fmt_imu_idle;
    wire [16:0] ap0, ap1, ap2, gp0, gp1, gp2;
    wire [15:0] ar0, ar1, ar2, gr0, gr1, gr2;

    reg  [15:0] s0, s1, s2, s3, s4, s5, s6, s7;
    reg  [16:0] d0, d1, d2, d3, d4, d5, d6, d7;
    reg  [2:0]  sstatus;
    reg  [15:0] sconv;
    reg         svalid;
    reg         sbusy;
    reg         sdout;
    reg         start;
    reg         fmt_go;
    reg         fmt_pend;
    reg         imu_go;
    reg         fmt_imu_go;
    reg         fmt_imu_pend;
    reg  [15:0] sax, say, saz, sgx, sgy, sgz;
    reg  [16:0] sap0, sap1, sap2, sgp0, sgp1, sgp2;
    reg  [1:0]  simu_st;
    reg  [7:0]  swho;
    reg         sready;

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
        start   = 1'b0;
        fmt_go  = 1'b0;
        fmt_pend = 1'b0;
        imu_go = 1'b0;
        fmt_imu_go = 1'b0;
        fmt_imu_pend = 1'b0;
        sax = 16'd0; say = 16'd0; saz = 16'd0;
        sgx = 16'd0; sgy = 16'd0; sgz = 16'd0;
        sap0 = 17'd0; sap1 = 17'd0; sap2 = 17'd0;
        sgp0 = 17'd0; sgp1 = 17'd0; sgp2 = 17'd0;
        simu_st = 2'd0;
        swho = 8'd0;
        sready = 1'b0;
    end

    assign i2c_scl = scl_oe ? 1'b0 : 1'bz;
    assign i2c_sda = sda_oe ? 1'b0 : 1'bz;

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

    adc_master u_adc (
        .clk         (clk),
        .start       (start),
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

    imu_mpu u_imu (
        .clk         (clk),
        .start       (imu_go),
        .paused      (paused),
        .idle        (imu_idle),
        .ready       (imu_ready),
        .sample_done (imu_sample),
        .status      (imu_status),
        .whoami      (whoami),
        .dev_used    (dev_used),
        .ax          (ax),
        .ay          (ay),
        .az          (az),
        .gx          (gx),
        .gy          (gy),
        .gz          (gz),
        .scl_oe      (scl_oe),
        .sda_oe      (sda_oe),
        .scl_i       (i2c_scl),
        .sda_i       (i2c_sda)
    );

    format_imu u_fmt_imu (
        .clk   (clk),
        .start (fmt_imu_go),
        .ax    (ax),
        .ay    (ay),
        .az    (az),
        .gx    (gx),
        .gy    (gy),
        .gz    (gz),
        .idle  (fmt_imu_idle),
        .p0    (ap0),
        .p1    (ap1),
        .p2    (ap2),
        .p3    (gp0),
        .p4    (gp1),
        .p5    (gp2),
        .r0    (ar0),
        .r1    (ar1),
        .r2    (ar2),
        .r3    (gr0),
        .r4    (gr1),
        .r5    (gr2)
    );

    always @(posedge clk) begin
        start       <= 1'b0;
        fmt_go      <= 1'b0;
        imu_go      <= 1'b0;
        fmt_imu_go  <= 1'b0;
        if (fmt_pend && fmt_idle) begin
            fmt_go   <= 1'b1;
            fmt_pend <= 1'b0;
        end
        if (fmt_imu_pend && fmt_imu_idle) begin
            fmt_imu_go   <= 1'b1;
            fmt_imu_pend <= 1'b0;
        end
        if (sample_done) begin
            fmt_pend <= 1'b1;
            s0 <= ch0; s1 <= ch1; s2 <= ch2; s3 <= ch3;
            s4 <= ch4; s5 <= ch5; s6 <= ch6; s7 <= ch7;
            sconv  <= conv_cnt;
            svalid <= 1'b1;
            sstatus <= adc_status;
            sbusy  <= probe_busy;
            sdout  <= probe_dout;
        end
        if (imu_sample) begin
            fmt_imu_pend <= 1'b1;
            sax <= ax; say <= ay; saz <= az;
            sgx <= gx; sgy <= gy; sgz <= gz;
            simu_st <= imu_status;
            swho    <= whoami;
            sready  <= 1'b1;
        end
        if (frame_done && init_done && adc_idle && fmt_idle && !paused) begin
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
            start   <= 1'b1;
        end
        if (frame_done && init_done && fmt_imu_idle && !paused) begin
            sax  <= ar0;
            say  <= ar1;
            saz  <= ar2;
            sgx  <= gr0;
            sgy  <= gr1;
            sgz  <= gr2;
            sap0 <= ap0;
            sap1 <= ap1;
            sap2 <= ap2;
            sgp0 <= gp0;
            sgp1 <= gp1;
            sgp2 <= gp2;
            simu_st <= imu_status;
            swho    <= whoami;
            sready  <= imu_ready;
            if (imu_idle && imu_ready)
                imu_go <= 1'b1;
        end
    end

    text_adc u_text (
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
        .imu_st     (simu_st),
        .whoami     (swho),
        .imu_ready  (sready),
        .iax        (sax),
        .iay        (say),
        .iaz        (saz),
        .igx        (sgx),
        .igy        (sgy),
        .igz        (sgz),
        .ap0        (sap0),
        .ap1        (sap1),
        .ap2        (sap2),
        .gp0        (sgp0),
        .gp1        (sgp1),
        .gp2        (sgp2),
        .pixel      (pixel)
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

    assign led = paused ? adc_convst : ~conv_cnt[0];
    assign adc_convstb = adc_convst;
endmodule
