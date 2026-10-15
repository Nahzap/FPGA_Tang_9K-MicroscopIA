`include "config.vh"
// Both axes, one datapath: Hall count, pot target and the position loop.
// X and Y take turns on the same Hall counter, pot scaler, multiplier and
// comparator. Only their registers (index 0 = X, 1 = Y) and their ports differ.
//
// Hall: each quadrature edge is one STEP of the count. The count is 0 at
// power up, reset and x_zero, floors at 0, and once the axis has its final
// never passes its max. Until x_final the max is the highest count reached.
//
// Pot: averaged over 2^POT_FILT samples, held within POT_HYST codes. The
// first and last POT_END codes read as 0 and full, so the regulator rail
// (FULL) only has to be known to about POT_END codes.
// MANUAL: target = pot fraction * max of that axis (counts). With the axis
// calibrated, x_cmd/y_cmd is +-CFG_MAN_X_PCT / CFG_MAN_Y_PCT toward that target and 0 inside
// the stop zone (brake). The sign is the one that makes the count move
// toward the target; it is learned from the Hall edges. A reversal waits
// until the Hall edges stop, so the 3 V pin and the 12 V pin do not swap
// while the shaft is still moving.
// AUTO: target = tgt_x / tgt_y from the PC, capped at the max. No drive.
module motion #(
    parameter integer FULL      = `CFG_POT_FULL,
    parameter integer POT_END   = `CFG_POT_END,
    parameter integer POT_FILT  = `CFG_POT_FILT,
    parameter integer POT_HYST  = `CFG_POT_HYST,
    parameter integer TH        = `CFG_HALL_TH,
    parameter integer SHIFT     = `CFG_HALL_SHIFT,
    parameter integer COUNT_MAX = `CFG_COUNT_MAX,
    parameter integer MAN_X_PCT = `CFG_MAN_X_PCT,
    parameter integer MAN_Y_PCT = `CFG_MAN_Y_PCT,
    parameter integer GATE      = `CFG_GATE,
    parameter integer RESUME    = `CFG_RESUME,
    parameter integer BRAKE_MS  = `CFG_BRAKE_MS,
    parameter integer LEARN     = `CFG_POL_LEARN,
    parameter integer STALL_MS  = `CFG_STALL_MS
) (
    input  wire        clk,
    input  wire        conv,
    input  wire        tick,
    input  wire [1:0]  mode,
    input  wire [19:0] tgt_x,
    input  wire [19:0] tgt_y,
    input  wire        x_zero,
    input  wire        x_final,
    input  wire        y_zero,
    input  wire        y_final,
    input  wire        clr,
    input  wire        lock,    // end calibration: max reached = final
    input  wire [15:0] pot_x,
    input  wire [15:0] pot_y,
    input  wire [15:0] xa,
    input  wire [15:0] xb,
    input  wire [15:0] ya,
    input  wire [15:0] yb,
    output wire [19:0] x_sens,
    output wire [19:0] x_tgt,
    output wire        x_moved,
    output wire        x_arm,
    output wire signed [9:0] x_cmd,
    output wire [19:0] y_sens,
    output wire [19:0] y_tgt,
    output wire        y_moved,
    output wire        y_arm,
    output wire signed [9:0] y_cmd
);
    localparam [1:0] M_MAN = 2'd0;
    localparam [1:0] M_AUTO = 2'd3;
    localparam [2:0] S_H1 = 3'd0, S_H2 = 3'd1, S_Q = 3'd2, S_MUL = 3'd3,
                     S_Q2 = 3'd4, S_OUT = 3'd5, S_CMP = 3'd6;
    // Pot span between the dead ends, and 2^32 / span for the first multiply.
    localparam integer SPAN = FULL - 2 * POT_END;
    localparam [19:0]  KQ   = 64'h1_0000_0000 / SPAN;
    localparam integer AW   = 16 + POT_FILT;
    localparam [19:0]  CMAX = COUNT_MAX;
    // One Hall edge: a 0 V to 3.3 V swing is 2*TH codes, 2^SHIFT codes per count.
    localparam [19:0]  STEP = (2 * TH) >> SHIFT;
    localparam [20:0]  GATE_C = GATE * STEP;
    localparam [20:0]  RES_C  = RESUME * STEP;
    localparam [15:0]  KB     = STEP * BRAKE_MS;
    localparam signed [9:0] MAN_X = MAN_X_PCT;
    localparam signed [9:0] MAN_Y = MAN_Y_PCT;

    // ---- per-axis registers ----
    (* mem2reg *) reg [19:0]   posq  [0:1];
    (* mem2reg *) reg [19:0]   fmax  [0:1];
    (* mem2reg *) reg [19:0]   tgt_q [0:1];
    (* mem2reg *) reg [AW-1:0] pacc  [0:1];
    (* mem2reg *) reg [15:0]   phold [0:1];
    (* mem2reg *) reg [4:0]    ecnt  [0:1];
    (* mem2reg *) reg [4:0]    vel   [0:1];
    (* mem2reg *) reg [3:0]    good  [0:1];
    (* mem2reg *) reg [3:0]    bad   [0:1];
    (* mem2reg *) reg [11:0]   stall [0:1];
    (* mem2reg *) reg signed [9:0] cmd_q [0:1];
    reg [1:0] f_ok = 2'b00;
    reg [1:0] a_r = 2'b00, b_r = 2'b00, have = 2'b00;
    reg [1:0] dir_dn = 2'b00, dir_on = 2'b00;
    reg [1:0] moved_q = 2'b00, hpend = 2'b00, tpend = 2'b00;
    reg [1:0] hold = 2'b11, seek_q = 2'b00, pol = 2'b00, conf = 2'b00, saw = 2'b00;
    reg [1:0] rev_hold = 2'b00;

    integer ii;
    initial begin
        for (ii = 0; ii < 2; ii = ii + 1) begin
            posq[ii] = 20'd0;  fmax[ii] = 20'd0;  tgt_q[ii] = 20'd0;
            pacc[ii] = 0;      phold[ii] = 16'd0;
            ecnt[ii] = 5'd0;   vel[ii] = 5'd0;
            good[ii] = 4'd0;   bad[ii] = 4'd0;    stall[ii] = 12'd0;
            cmd_q[ii] = 10'sd0;
        end
    end

    // ---- shared datapath ----
    reg        s  = 1'b0;
    reg [2:0]  st = S_H1;
    reg [4:0]  n  = 5'd0;
    reg        pass = 1'b0;
    reg [19:0] hi = 20'd0, m = 20'd0;
    reg [16:0] lo = 17'd0;
    reg [1:0]  ne_r = 2'd0;
    reg        plus_r = 1'b0, minus_r = 1'b0;
    reg [19:0] tg_r = 20'd0;
    reg [20:0] d_r = 21'd0, stop_r = 21'd0, go_r = 21'd0;

    wire [15:0] ra  = s ? ya : xa;
    wire [15:0] rb  = s ? yb : xb;
    wire [15:0] pot = s ? pot_y : pot_x;

    // Hall: one STEP per edge. Both channels changed in one conversion: two
    // edges, in the last known direction. ADC noise between edges adds nothing.
    wire        a_bit = !ra[15] && !(ra < TH[15:0]);
    wire        b_bit = !rb[15] && !(rb < TH[15:0]);
    wire        a_new = have[s] && (a_bit != a_r[s]);
    wire        b_new = have[s] && (b_bit != b_r[s]);
    wire        a_chg = a_new && !b_new;
    wire        b_chg = b_new && !a_new;
    wire        plus  = (a_chg && (a_bit == b_bit)) || (b_chg && (a_bit != b_bit));
    wire        minus = (a_chg && (a_bit != b_bit)) || (b_chg && (a_bit == b_bit));
    wire [1:0]  ne_w  = {a_new && b_new, a_new ^ b_new};

    wire [19:0] pq    = posq[s];
    wire [19:0] fine  = ne_r[1] ? {STEP[18:0], 1'b0} : STEP;
    wire [20:0] up_v  = {1'b0, pq} + {1'b0, fine};
    wire [19:0] cap   = f_ok[s] ? fmax[s] : CMAX;
    wire [19:0] pq_up = (up_v > {1'b0, cap}) ? cap : up_v[19:0];
    wire [19:0] pq_dn = (pq < fine) ? 20'd0 : (pq - fine);
    wire        go_dn = minus_r || (dir_dn[s] && !plus_r);
    wire [19:0] nq    = go_dn ? pq_dn : pq_up;
    wire        edge_r = plus_r || minus_r;

    // Pot: running average, then a held value that moves past POT_HYST.
    // A negative reading (below 0 V) counts as 0.
    wire [15:0]   p0    = pot[15] ? 16'd0 : pot;
    wire [AW-1:0] pa_s  = pacc[s];
    wire [AW-1:0] pa_nx = pa_s - (pa_s >> POT_FILT) + p0;
    wire [15:0]   pf    = pa_s[AW-1:POT_FILT];
    wire [15:0]   ph    = phold[s];
    wire          pmov  = (pf > ph + POT_HYST) || (pf + POT_HYST < ph);
    // Fraction of 65536: (ph - POT_END) / SPAN, 65536 from the top end up.
    wire [15:0]   ps    = (ph > POT_END) ? (ph - POT_END) : 16'd0;
    wire          pfull = !(ps < SPAN);

    // Two passes on one shift-add multiplier, 17 rounds each:
    // q = ps * KQ >> 16, then target = q * max >> 16.
    wire [20:0] madd = {1'b0, hi} + {1'b0, m};
    wire [19:0] tg   = {hi[18:0], lo[16]};
    wire [19:0] pc_t = s ? tgt_y : tgt_x;
    wire [19:0] pc_c = (pc_t > fmax[s]) ? fmax[s] : pc_t;
    wire [19:0] tsel = (mode == M_AUTO) ? pc_c : tg;

    // Stop zone. Coming toward the target, both limits add the coast of
    // the last full millisecond (vel). Edges still arriving this
    // millisecond stay in ecnt and must not widen the zone: one new edge
    // would add BRAKE_MS steps of brake and only one of travel, and the
    // bridge would drop on that same edge.
    wire [20:0] coast = vel[s] * KB;
    wire [20:0] d_abs = d_r[20] ? (~d_r + 21'd1) : d_r;
    wire        toward = (d_r[20] == dir_dn[s]);
    wire [20:0] lim = toward ? (hold[s] ? go_r : stop_r)
                             : (hold[s] ? RES_C : GATE_C);
    wire        far = d_abs > lim;
    wire        armed_s = f_ok[s];
    wire        driven = seek_q[s];
    // While edges are still arriving, the opposite sign would move the
    // solid 3 V from one bridge input to the other. Hold the brake instead.
    wire        moving   = (vel[s] != 0) || (ecnt[s] != 0);
    wire        want_neg = d_r[20] ^ pol[s];
    wire        opp      = (cmd_q[s] != 0) && (want_neg != cmd_q[s][9]);
    wire        rev_lock = rev_hold[s] || (moving && opp);
    // pol: forward pins make the count go up when pol is 0.
    wire        exp_up = (cmd_q[s][9] == pol[s]);
    wire        right  = (plus_r && exp_up) || (minus_r && !exp_up);

    always @(posedge clk) begin
        case (st)
            S_H1: begin
                plus_r  <= 1'b0;
                minus_r <= 1'b0;
                ne_r    <= 2'd0;
                if (hpend[s]) begin
                    hpend[s] <= 1'b0;
                    a_r[s]   <= a_bit;
                    b_r[s]   <= b_bit;
                    pacc[s]  <= pa_nx;
                    have[s]  <= 1'b1;
                    plus_r   <= plus;
                    minus_r  <= minus;
                    ne_r     <= ne_w;
                end
                st <= S_H2;
            end
            S_H2: begin
                moved_q[s] <= edge_r;
                if (plus_r && !minus_r) begin
                    dir_dn[s] <= 1'b0;
                    dir_on[s] <= 1'b1;
                end else if (minus_r && !plus_r) begin
                    dir_dn[s] <= 1'b1;
                    dir_on[s] <= 1'b1;
                end
                if (pmov)
                    phold[s] <= pf;
                if ((ne_r != 2'd0) && (dir_on[s] || edge_r)) begin
                    posq[s] <= nq;
                    if (!f_ok[s] && (nq > fmax[s]))
                        fmax[s] <= nq;
                end
                if (!tpend[s] && (ecnt[s] < 5'd30))
                    ecnt[s] <= ecnt[s] + {3'd0, ne_r};
                // Pushing the wrong way into an end: no edge while seeking
                // and the polarity is still unconfirmed. Flip it.
                if (tpend[s]) begin
                    tpend[s] <= 1'b0;
                    saw[s]   <= 1'b0;
                    vel[s]   <= ecnt[s];
                    ecnt[s]  <= {3'd0, ne_r};
                    if ((LEARN == 0) || !seek_q[s] || conf[s] || saw[s])
                        stall[s] <= 12'd0;
                    else if (stall[s] == STALL_MS - 1) begin
                        stall[s] <= 12'd0;
                        pol[s]   <= ~pol[s];
                    end else
                        stall[s] <= stall[s] + 12'd1;
                end
                if (edge_r)
                    saw[s] <= 1'b1;
                if ((LEARN != 0) && edge_r && driven && !conf[s]) begin
                    if (right) begin
                        bad[s] <= 4'd0;
                        if (good[s] == 4'd14)
                            conf[s] <= 1'b1;
                        else
                            good[s] <= good[s] + 4'd1;
                    end else begin
                        good[s] <= 4'd0;
                        if (bad[s] == 4'd14) begin
                            bad[s] <= 4'd0;
                            pol[s]  <= ~pol[s];
                        end else
                            bad[s] <= bad[s] + 4'd1;
                    end
                end
                st <= S_Q;
            end
            S_Q: begin
                hi   <= 20'd0;
                lo   <= {1'b0, ps};
                m    <= KQ;
                n    <= 5'd0;
                pass <= 1'b0;
                st   <= S_MUL;
            end
            S_Q2: begin
                hi   <= 20'd0;
                lo   <= pfull ? 17'd65536 : tg[16:0];
                m    <= fmax[s];
                n    <= 5'd0;
                pass <= 1'b1;
                st   <= S_MUL;
            end
            S_MUL: begin
                if (lo[0])
                    {hi, lo} <= {madd, lo[16:1]};
                else
                    {hi, lo} <= {1'b0, hi, lo[16:1]};
                n <= n + 5'd1;
                if (n == 5'd16)
                    st <= pass ? S_CMP : S_Q2;
            end
            S_CMP: begin
                tg_r   <= tsel;
                d_r    <= {1'b0, tsel} - {1'b0, pq};
                stop_r <= GATE_C + coast;
                go_r   <= RES_C + coast;
                st     <= S_OUT;
            end
            default: begin
                tgt_q[s]  <= tg_r;
                cmd_q[s]  <= 10'sd0;
                seek_q[s] <= 1'b0;
                hold[s]   <= 1'b1;
                if (!moving)
                    rev_hold[s] <= 1'b0;
                else if (opp)
                    rev_hold[s] <= 1'b1;
                if ((mode == M_MAN) && armed_s && far && !rev_lock) begin
                    hold[s]     <= 1'b0;
                    seek_q[s]   <= 1'b1;
                    rev_hold[s] <= 1'b0;
                    cmd_q[s]    <= want_neg ? (s ? -MAN_Y : -MAN_X)
                                            : (s ?  MAN_Y :  MAN_X);
                end
                s  <= ~s;
                st <= S_H1;
            end
        endcase

        if (conv)
            hpend <= 2'b11;
        if (tick)
            tpend <= 2'b11;

        // Marks. Each command touches only its axis; reset touches both.
        if (x_zero) begin
            posq[0] <= 20'd0;
            if (!f_ok[0])
                fmax[0] <= 20'd0;
        end
        if (x_final) begin
            fmax[0] <= posq[0];
            f_ok[0] <= 1'b1;
        end
        if (y_zero) begin
            posq[1] <= 20'd0;
            if (!f_ok[1])
                fmax[1] <= 20'd0;
        end
        if (y_final) begin
            fmax[1] <= posq[1];
            f_ok[1] <= 1'b1;
        end
        if (lock) begin
            if (fmax[0] != 20'd0)
                f_ok[0] <= 1'b1;
            if (fmax[1] != 20'd0)
                f_ok[1] <= 1'b1;
        end
        if (clr) begin
            posq[0] <= 20'd0;
            posq[1] <= 20'd0;
            fmax[0] <= 20'd0;
            fmax[1] <= 20'd0;
            f_ok    <= 2'b00;
            have    <= 2'b00;
            dir_on  <= 2'b00;
            dir_dn  <= 2'b00;
            hold     <= 2'b11;
            seek_q   <= 2'b00;
            rev_hold <= 2'b00;
            pol      <= 2'b00;
            conf    <= 2'b00;
            cmd_q[0] <= 10'sd0;
            cmd_q[1] <= 10'sd0;
        end
    end

    assign x_sens  = posq[0];
    assign x_tgt   = tgt_q[0];
    assign x_moved = moved_q[0];
    assign x_arm   = f_ok[0];
    assign x_cmd   = cmd_q[0];
    assign y_sens  = posq[1];
    assign y_tgt   = tgt_q[1];
    assign y_moved = moved_q[1];
    assign y_arm   = f_ok[1];
    assign y_cmd   = cmd_q[1];
endmodule
