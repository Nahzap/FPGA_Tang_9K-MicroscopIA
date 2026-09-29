`include "config.vh"
// AD7606 + LCD + 2× DRV8871. One position datapath shared by both motors.
// Pots command a place on the guide: X CFG_X_UM, Y CFG_Y_UM.
// In AUTO the PC commands it instead (order T, counts and power).
// Serial protocol of Lab 206 on pins 17 (TX) and 18 (RX), CFG_BAUD 8N1.
// All tunable constants live in config.vh.
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
    wire [15:0] x_cmp, y_cmp;
    wire signed [9:0] x_rep, y_rep;
    wire [19:0] x_sens, y_sens, x_tgt, y_tgt;
    wire        x_moved, y_moved, x_gate, y_gate;
    wire        x_hlo, x_hhi, y_hlo, y_hhi;
    wire [23:0] x_dig, y_dig;

    wire [1:0]        mode;
    wire signed [9:0] pwr_a, pwr_b;
    wire [19:0]       pc_x, pc_y;
    wire              inv_x, inv_y;
    wire              x_arm, y_arm;
    wire              x_zero_p, y_zero_p, x_final_p, y_final_p, rst_p, lock_p;

    wire [15:0] pwm_cnt;
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
    reg         sx_moved, sy_moved;
    reg         sx_lock, sy_lock;
    reg  [23:0] sx_dig, sy_dig;
    reg         lx_fwd, lx_rev, lx_brake, ly_fwd, ly_rev, ly_brake;
    reg  [15:0] lx_cmp, ly_cmp;

    initial begin
        pix_q   = 16'd0;
        d0 = 17'd0; d1 = 17'd0; d2 = 17'd0; d3 = 17'd0;
        sstatus = 3'd1;
        sconv   = 16'd0;
        svalid  = 1'b0;
        sbusy   = 1'b0;
        sdout   = 1'b1;
        sx_moved = 1'b0; sy_moved = 1'b0;
        sx_lock = 1'b0; sy_lock = 1'b0;
        sx_dig = 24'd0; sy_dig = 24'd0;
        lx_fwd = 1'b0; lx_rev = 1'b0; lx_brake = 1'b0;
        ly_fwd = 1'b0; ly_rev = 1'b0; ly_brake = 1'b0;
        lx_cmp = 16'd0; ly_cmp = 16'd0;
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
    // One datapath for both axes; X and Y take turns on it.
    // 1 ms tick only times the stall check. Hall uses every conversion.
    localparam [15:0] MS_LAST = `CFG_CLK_HZ / 1000 - 1;
    reg [15:0] ms_div = 16'd0;
    reg        mot_tick = 1'b0;
    always @(posedge clk) begin
        mot_tick <= 1'b0;
        if (ms_div == MS_LAST) begin
            ms_div   <= 16'd0;
            mot_tick <= 1'b1;
        end else
            ms_div <= ms_div + 16'd1;
    end

    motion u_mot (
        .clk    (clk),
        .conv   (sample_done),
        .tick   (mot_tick),
        .mode   (mode),
        .pwr_a  (pwr_a),
        .pwr_b  (pwr_b),
        .tgt_x  (pc_x),
        .tgt_y  (pc_y),
        .inv_x  (inv_x),
        .inv_y  (inv_y),
        .x_zero (x_zero_p),
        .x_final(x_final_p),
        .y_zero (y_zero_p),
        .y_final(y_final_p),
        .clr    (rst_p),
        .lock   (lock_p),
        .pot_x  (ch2),
        .pot_y  (ch3),
        .xa     (ch6),
        .xb     (ch7),
        .ya     (ch4),
        .yb     (ch5),
        .x_fwd  (x_fwd),
        .x_rev  (x_rev),
        .x_brake(x_brake),
        .x_cmp  (x_cmp),
        .x_rep  (x_rep),
        .x_sens (x_sens),
        .x_tgt  (x_tgt),
        .x_moved(x_moved),
        .x_gate (x_gate),
        .x_arm  (x_arm),
        .x_hlo  (x_hlo),
        .x_hhi  (x_hhi),
        .y_fwd  (y_fwd),
        .y_rev  (y_rev),
        .y_brake(y_brake),
        .y_cmp  (y_cmp),
        .y_rep  (y_rep),
        .y_sens (y_sens),
        .y_tgt  (y_tgt),
        .y_moved(y_moved),
        .y_gate (y_gate),
        .y_arm  (y_arm),
        .y_hlo  (y_hlo),
        .y_hhi  (y_hhi)
    );

    com_ctrl u_com (
        .clk       (clk),
        .rx        (uart_rx),
        .tx        (uart_tx),
        .rep_a     (x_rep),
        .rep_b     (y_rep),
        .sensor1   (x_sens),
        .sensor2   (y_sens),
        .pot_a     (x_tgt),
        .pot_b     (y_tgt),
        .x_dig     (x_dig),
        .y_dig     (y_dig),
        .in_gate_a (x_gate),
        .in_gate_b (y_gate),
        .x_arm     (x_arm),
        .y_arm     (y_arm),
        .mode      (mode),
        .pwr_a     (pwr_a),
        .pwr_b     (pwr_b),
        .tgt_x     (pc_x),
        .tgt_y     (pc_y),
        .inv_x     (inv_x),
        .inv_y     (inv_y),
        .x_zero_p  (x_zero_p),
        .y_zero_p  (y_zero_p),
        .x_final_p (x_final_p),
        .y_final_p (y_final_p),
        .rst_p     (rst_p),
        .lock_p    (lock_p)
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
            sx_moved <= x_moved;
            sx_lock  <= x_arm;
            sy_moved <= y_moved;
            sy_lock  <= y_arm;
            sx_dig   <= x_dig;
            sy_dig   <= y_dig;
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
        .x_dig      (sx_dig),
        .x_moved    (sx_moved),
        .x_lock     (sx_lock),
        .y_dig      (sy_dig),
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
