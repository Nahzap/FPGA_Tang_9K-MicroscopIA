`include "config.vh"
// One DRV8871 (SLVSCY9B Table 1, 7.3): 00 coast, 10 forward, 01 reverse,
// 11 brake (slow decay). The chop alternates drive and brake.
//   cmd and q_cmd are signed integer %, |x| <= 100; inv flips the sense.
//   1 % = 10 clocks of the PERIOD-clock period. 0 is brake. Under MINP
//   becomes MINP, over PERIOD-MINP becomes static 100 %: no high or low
//   on IN1/IN2 is shorter than MINP (800 ns).
//   The command is taken only on the period boundary (cnt == 0).
//   A reversal spends one whole period in 11; 10 never meets 01.
//   Leaving 00 spends two periods in 11 (wake: 5 us high + tON 50 us),
//   so the first chopped period is always whole.
//   halt is 00 at once (pause). coast is 00 from the next boundary.
//   q_on: the next periods use q_cmd; q_took marks each one that drives.
//   Stall: STALL ms of drive with no Hall edge -> brake until clr_stall.
// The meter counts the clocks with IN1 != IN2 in each period on the
// output registers and compares them with the legal command of that
// period; any mismatch, or a direct 10 <-> 01, sets err until clr_err.
module pwm_drv #(
    parameter integer PERIOD = `CFG_PWM_PERIOD,
    parameter integer MINP   = `CFG_PWM_MIN,
    parameter integer STALL  = `CFG_STALL_MS
) (
    input  wire              clk,
    input  wire [9:0]        cnt,
    input  wire              halt,
    input  wire              coast,
    input  wire signed [9:0] cmd,
    input  wire              q_on,
    input  wire signed [9:0] q_cmd,
    input  wire              inv,
    input  wire              edge_seen,
    input  wire              tick,
    input  wire              clr_stall,
    input  wire              clr_err,
    output reg               in1,
    output reg               in2,
    output reg               q_took,
    output reg               stalled,
    output reg               err
);
    localparam [1:0] C_COAST = 2'd0;
    localparam [1:0] C_BRAKE = 2'd1;
    localparam [1:0] C_FWD   = 2'd2;
    localparam [1:0] C_REV   = 2'd3;
    localparam [9:0] PER = PERIOD;
    localparam [9:0] LO  = MINP;
    localparam [9:0] HI  = PERIOD - MINP;
    localparam [9:0] STL = STALL;

    function [9:0] legal;
        input [9:0] m;
        begin
            if (m > HI)
                legal = PER;
            else if (m < LO)
                legal = LO;
            else
                legal = m;
        end
    endfunction

    reg [1:0] cur = C_COAST;
    reg [9:0] d_r = 10'd0;
    reg [1:0] wk  = 2'd2;
    reg [9:0] sc  = 10'd0;

    wire              load = (cnt == 10'd0);
    wire signed [9:0] c    = q_on ? q_cmd : cmd;
    wire [6:0]        mag  = c[9] ? -c[6:0] : c[6:0];
    wire [9:0]        m    = {mag, 3'b000} + {2'b00, mag, 1'b0};
    wire [1:0]        rq   = (c[9] ^ inv) ? C_REV : C_FWD;
    wire              flip = ((cur == C_FWD) && (rq == C_REV)) ||
                             ((cur == C_REV) && (rq == C_FWD));

    reg [1:0] nc;
    reg [9:0] nd;
    reg [1:0] nwk;
    always @(*) begin
        nc     = cur;
        nd     = d_r;
        nwk    = wk;
        q_took = 1'b0;
        if (halt) begin
            nc  = C_COAST;
            nwk = 2'd2;
        end else if (load) begin
            if (coast && !q_on) begin
                nc  = C_COAST;
                nwk = 2'd2;
            end else if (wk != 2'd0) begin
                nc  = C_BRAKE;
                nwk = wk - 2'd1;
            end else if (stalled || (mag == 7'd0) || flip) begin
                nc = C_BRAKE;
            end else begin
                nc     = rq;
                nd     = legal(m);
                q_took = q_on;
            end
        end
    end

    wire on    = (cnt < nd);
    wire drive = (cur == C_FWD) || (cur == C_REV);

    initial begin
        in1     = 1'b0;
        in2     = 1'b0;
        stalled = 1'b0;
        err     = 1'b0;
    end

    always @(posedge clk) begin
        cur <= nc;
        d_r <= nd;
        wk  <= nwk;

        case (nc)
            C_FWD:   begin in1 <= 1'b1; in2 <= !on;  end
            C_REV:   begin in1 <= !on;  in2 <= 1'b1; end
            C_BRAKE: begin in1 <= 1'b1; in2 <= 1'b1; end
            default: begin in1 <= 1'b0; in2 <= 1'b0; end
        endcase

        if (halt || clr_stall) begin
            stalled <= 1'b0;
            sc      <= 10'd0;
        end else if (!drive || edge_seen)
            sc <= 10'd0;
        else if (sc == STL)
            stalled <= 1'b1;
        else if (tick)
            sc <= sc + 10'd1;
    end

    // ---- meter ----
    reg       load_q = 1'b0;
    reg       p1 = 1'b0, p2 = 1'b0;
    reg       hz = 1'b0;
    reg [1:0] sk = 2'd0;
    reg [9:0] seen  = 10'd0;
    reg [9:0] exp_d = 10'd0;

    always @(posedge clk) begin
        load_q <= load;
        p1     <= in1;
        p2     <= in2;
        hz     <= halt;
        if (p1 && !p2 && !in1 && in2)
            err <= 1'b1;
        if (!p1 && p2 && in1 && !in2)
            err <= 1'b1;
        if (load_q) begin
            if ((sk == 2'd0) && (seen != exp_d))
                err <= 1'b1;
            seen  <= (in1 != in2) ? 10'd1 : 10'd0;
            exp_d <= drive ? d_r : 10'd0;
            if (sk != 2'd0)
                sk <= sk - 2'd1;
        end else if (in1 != in2)
            seen <= seen + 10'd1;
        if (halt != hz)
            sk <= 2'd2;
        if (clr_err)
            err <= 1'b0;
    end
endmodule
