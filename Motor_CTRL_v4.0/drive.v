`include "config.vh"
// Both DRV8871 from the com_ctrl orders: one timebase, one pwm_drv per
// bridge (its own pins), one Q counter for both (one Q at a time).
//   PWM mode (A, N, P, Q) drives at the ordered %.
//   MANUAL drives at man_a/man_b (the pot position loop). AUTO and BRAKE
//   hold 11. RESET with nothing to drive coasts (00); pause is 00 at once.
//   Q: q_n driving periods at q_pot on one axis. Any other order, pause,
//   or a stall of that axis ends it.
// rep_a/rep_b: % applied, for PotenciaA/B. 0 when stalled or paused.
module drive #(
    parameter integer TICK = `CFG_CLK_HZ / 1000
) (
    input  wire              clk,
    input  wire              paused,
    input  wire [1:0]        mode,
    input  wire              in_reset,
    input  wire signed [9:0] pwr_a,
    input  wire signed [9:0] pwr_b,
    input  wire              inv_x,
    input  wire              inv_y,
    input  wire signed [9:0] man_a,
    input  wire signed [9:0] man_b,
    input  wire              q_go_x,
    input  wire              q_go_y,
    input  wire signed [9:0] q_pot,
    input  wire [15:0]       q_n,
    input  wire              ord_p,
    input  wire              rst_p,
    input  wire              x_moved,
    input  wire              y_moved,
    output wire              x_in1,
    output wire              x_in2,
    output wire              y_in1,
    output wire              y_in2,
    output wire signed [9:0] rep_a,
    output wire signed [9:0] rep_b,
    output wire              q_busy,
    output wire              x_stl,
    output wire              y_stl,
    output wire              err,
    output wire              ms_tick
);
    localparam [1:0] M_MAN = 2'd0;
    localparam [1:0] M_PWM = 2'd1;
    localparam [1:0] M_BRK = 2'd2;

    wire [9:0]  cnt_x, cnt_y;
    wire        x_took, y_took, x_err, y_err;
    reg  [14:0] ms_c  = 15'd0;
    reg         tick  = 1'b0;
    reg  [15:0] q_cnt = 16'd0;
    reg         q_y   = 1'b0;

    always @(posedge clk) begin
        tick <= (ms_c == TICK - 1);
        ms_c <= (ms_c == TICK - 1) ? 15'd0 : ms_c + 15'd1;

        if ((q_go_x || q_go_y) && !paused) begin
            q_cnt <= q_n;
            q_y   <= q_go_y;
        end else if (paused || ord_p || (q_y ? y_stl : x_stl))
            q_cnt <= 16'd0;
        else if (x_took || y_took)
            q_cnt <= q_cnt - 16'd1;
    end

    wire              pos    = (mode == M_MAN);
    wire signed [9:0] cmd_x  = (mode == M_PWM) ? pwr_a : pos ? man_a : 10'sd0;
    wire signed [9:0] cmd_y  = (mode == M_PWM) ? pwr_b : pos ? man_b : 10'sd0;
    wire              idle_r = in_reset && (mode != M_BRK);
    wire              q_on   = (q_cnt != 16'd0);
    wire              q_x_on = q_on && !q_y;
    wire              q_y_on = q_on && q_y;

    assign rep_a  = (paused || x_stl) ? 10'sd0 : q_x_on ? q_pot : cmd_x;
    assign rep_b  = (paused || y_stl) ? 10'sd0 : q_y_on ? q_pot : cmd_y;
    assign q_busy = q_on;
    assign err    = x_err || y_err;
    assign ms_tick = tick;

    pwm_timer u_tim (
        .clk   (clk),
        .cnt_x (cnt_x),
        .cnt_y (cnt_y)
    );

    pwm_drv u_px (
        .clk       (clk),
        .cnt       (cnt_x),
        .halt      (paused),
        .coast     (idle_r && (cmd_x == 10'sd0)),
        .cmd       (cmd_x),
        .q_on      (q_x_on),
        .q_cmd     (q_pot),
        .inv       (inv_x),
        .edge_seen (x_moved),
        .tick      (tick),
        .clr_stall (ord_p || pos),
        .clr_err   (rst_p),
        .in1       (x_in1),
        .in2       (x_in2),
        .q_took    (x_took),
        .stalled   (x_stl),
        .err       (x_err)
    );

    pwm_drv u_py (
        .clk       (clk),
        .cnt       (cnt_y),
        .halt      (paused),
        .coast     (idle_r && (cmd_y == 10'sd0)),
        .cmd       (cmd_y),
        .q_on      (q_y_on),
        .q_cmd     (q_pot),
        .inv       (inv_y),
        .edge_seen (y_moved),
        .tick      (tick),
        .clr_stall (ord_p || pos),
        .clr_err   (rst_p),
        .in1       (y_in1),
        .in2       (y_in2),
        .q_took    (y_took),
        .stalled   (y_stl),
        .err       (y_err)
    );
endmodule
