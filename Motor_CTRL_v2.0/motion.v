`include "config.vh"
// Both motors, one datapath. X and Y take turns on the same Hall counter,
// pot scaler, multiplier and position comparator. Only their registers
// (index 0 = X, 1 = Y) and their ports differ.
//
// Manual: target = pot fraction * max of that axis (counts). The pot is
// averaged over 2^POT_FILT samples, held within POT_HYST codes, and its
// first and last POT_END codes read as 0 and full. Until x_final the max
// is the highest count reached.
// Each Hall edge is one STEP of the count; GATE and RESUME are in edges.
// Outside GATE the motor runs at POWER % toward the target, + or -. Within
// GATE it stops, and stays stopped until the error passes RESUME. While it
// runs toward the target it stops BRAKE_MS early: with the H-bridge brake
// the coast is about speed * a fixed time.
// POWER is % of the PWM period; the serial reports that same %.
module motion #(
    parameter integer FULL       = `CFG_POT_FULL,
    parameter integer POT_END    = `CFG_POT_END,
    parameter integer POT_FILT   = `CFG_POT_FILT,
    parameter integer POT_HYST   = `CFG_POT_HYST,
    parameter integer TH         = `CFG_HALL_TH,
    parameter integer SHIFT      = `CFG_HALL_SHIFT,
    parameter integer COUNT_MAX  = `CFG_COUNT_MAX,
    parameter integer PERIOD     = `CFG_PWM_PERIOD,
    parameter integer POWER      = `CFG_POWER,
    parameter integer GATE       = `CFG_GATE,
    parameter integer RESUME     = `CFG_RESUME,
    parameter integer BRAKE_MS   = `CFG_BRAKE_MS,
    parameter integer STOP_BRAKE = `CFG_STOP_BRAKE,
    parameter integer LEARN      = `CFG_POL_LEARN,
    parameter integer STALL_MS   = `CFG_STALL_MS
) (
    input  wire               clk,
    input  wire               conv,
    input  wire               tick,
    input  wire [1:0]         mode,
    input  wire signed [9:0]  pwr_a,
    input  wire signed [9:0]  pwr_b,
    input  wire               inv_x,
    input  wire               inv_y,
    input  wire               x_zero,
    input  wire               x_final,
    input  wire               y_zero,
    input  wire               y_final,
    input  wire               clr,
    input  wire               lock,    // end calibration: max reached = final
    input  wire [15:0]        pot_x,
    input  wire [15:0]        pot_y,
    input  wire [15:0]        xa,
    input  wire [15:0]        xb,
    input  wire [15:0]        ya,
    input  wire [15:0]        yb,
    output wire               x_fwd,
    output wire               x_rev,
    output wire               x_brake,
    output wire        [15:0] x_cmp,
    output wire signed [9:0]  x_rep,
    output wire        [19:0] x_sens,
    output wire        [19:0] x_tgt,
    output wire               x_moved,
    output wire               x_gate,
    output wire               x_arm,
    output wire               x_hlo,
    output wire               x_hhi,
    output wire               y_fwd,
    output wire               y_rev,
    output wire               y_brake,
    output wire        [15:0] y_cmp,
    output wire signed [9:0]  y_rep,
    output wire        [19:0] y_sens,
    output wire        [19:0] y_tgt,
    output wire               y_moved,
    output wire               y_gate,
    output wire               y_arm,
    output wire               y_hlo,
    output wire               y_hhi
);
    localparam [1:0] M_MAN = 2'd0, M_AUTO = 2'd1, M_BRK = 2'd2;
    localparam [2:0] S_H1 = 3'd0, S_H2 = 3'd1, S_Q = 3'd2, S_MUL = 3'd3,
                     S_CMP = 3'd4, S_OUT = 3'd5, S_Q2 = 3'd6;
    // Pot span between the dead ends, and 2^32 / span for the first multiply.
    localparam integer SPAN = FULL - 2 * POT_END;
    localparam [19:0]  KQ   = 64'h1_0000_0000 / SPAN;
    localparam integer AW   = 16 + POT_FILT;
    // Compare values for the PWM, computed at build time.
    localparam [15:0]       CMP_PWR = POWER * PERIOD / 100;
    localparam signed [9:0] REP_PWR = POWER;
    localparam [19:0] KC       = PERIOD * 1024 / 100;   // cmp per % << 10
    localparam [19:0] CMAX     = COUNT_MAX;
    // One Hall edge: a 0 V to 3.3 V swing is 2*TH codes, 2^SHIFT codes per count.
    localparam [19:0] STEP     = (2 * TH) >> SHIFT;
    localparam [20:0] GATE_C   = GATE * STEP;
    localparam [20:0] RES_C    = RESUME * STEP;
    localparam [15:0] KB       = STEP * BRAKE_MS;       // counts per (edge/ms)

    // ---- per-axis registers ----
    (* mem2reg *) reg [19:0]       posq  [0:1];
    (* mem2reg *) reg [19:0]       fmax  [0:1];
    // Speed for the early stop: edges in the last ms, or in this ms so far
    // if that is already more (the motor is speeding up).
    (* mem2reg *) reg [4:0]        ecnt  [0:1];
    (* mem2reg *) reg [4:0]        vel   [0:1];
    (* mem2reg *) reg [19:0]       tgt_q [0:1];
    (* mem2reg *) reg [15:0]       cmp_q [0:1];
    (* mem2reg *) reg signed [9:0] rep_q [0:1];
    (* mem2reg *) reg [3:0]        good  [0:1];
    (* mem2reg *) reg [3:0]        bad   [0:1];
    (* mem2reg *) reg [11:0]       stall [0:1];
    (* mem2reg *) reg [AW-1:0]     pacc  [0:1];
    (* mem2reg *) reg [15:0]       phold [0:1];
    reg [1:0] z_ok = 2'b00, f_ok = 2'b00, hold = 2'b11;
    reg [1:0] a_r = 2'b00, b_r = 2'b00, have = 2'b00;
    reg [1:0] dir_dn = 2'b00, dir_on = 2'b00;
    // pol: pin direction that makes the count go up (learned from the Hall
    // edges). conf: that polarity was confirmed by real motion.
    reg [1:0] pol = 2'b00, conf = 2'b00, saw = 2'b00;
    reg [1:0] fwd_q = 2'b00, rev_q = 2'b00, brk_q = 2'b00;
    reg [1:0] gate_q = 2'b11, moved_q = 2'b00, seek_q = 2'b00;
    reg [1:0] hpend = 2'b00, tpend = 2'b00;

    integer ii;
    initial begin
        for (ii = 0; ii < 2; ii = ii + 1) begin
            posq[ii] = 20'd0;  fmax[ii] = 20'd0;
            ecnt[ii] = 5'd0;   vel[ii] = 5'd0;
            tgt_q[ii] = 20'd0; cmp_q[ii] = 16'd0; rep_q[ii] = 10'sd0;
            good[ii] = 4'd0;   bad[ii] = 4'd0;    stall[ii] = 12'd0;
            pacc[ii] = 0;      phold[ii] = 16'd0;
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
    reg [20:0] d_r  = 21'd0;
    reg [20:0] stop_r = 21'd0, go_r = 21'd0;
    wire [4:0]  v_est = (ecnt[s] > vel[s]) ? ecnt[s] : vel[s];
    wire [20:0] coast = v_est * KB;

    wire [15:0]       ra  = s ? ya : xa;
    wire [15:0]       rb  = s ? yb : xb;
    wire [15:0]       pot = s ? pot_y : pot_x;
    wire signed [9:0] pw  = s ? pwr_b : pwr_a;
    wire              inv = s ? inv_y : inv_x;

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
    // With pins driven, the edge sense the current polarity predicts.
    wire        driven = fwd_q[s] || rev_q[s];
    wire        exp_up = fwd_q[s] ^ pol[s];
    wire        right  = (plus_r && exp_up) || (minus_r && !exp_up);

    // Pot: running average, then a held value that moves past POT_HYST.
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

    // Coming toward the target, both limits add the coast: it stops at
    // GATE + coast and, stopped or coasting in, starts again past RESUME + coast.
    wire [20:0] d_abs  = d_r[20] ? (~d_r + 21'd1) : d_r;
    wire        toward = (d_r[20] == dir_dn[s]);
    wire [20:0] lim    = toward ? (hold[s] ? go_r : stop_r)
                                : (hold[s] ? RES_C : GATE_C);
    wire        far    = d_abs > lim;
    // AUTO: cmp = |pwr| % * PERIOD / 100. com_ctrl already caps |pwr|.
    wire [9:0]  apc  = pw[9] ? (~pw + 10'd1) : pw;
    wire [29:0] cm_w = apc * KC;
    wire [15:0] cmpa = cm_w[25:10];

    // The count is 0 at power up, reset and x_zero, and floors at 0 at the
    // low end, so a final alone calibrates the axis.
    wire armed_s = f_ok[s];

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
                // Stall while seeking and polarity not yet confirmed: the
                // motor is pushing the wrong way into an end. Flip it.
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
                            pol[s] <= ~pol[s];
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
                tg_r  <= tg;
                d_r   <= {1'b0, tg} - {1'b0, pq};
                stop_r <= GATE_C + coast;
                go_r   <= RES_C + coast;
                st    <= S_OUT;
            end
            default: begin
                tgt_q[s] <= tg_r;
                fwd_q[s]  <= 1'b0;
                rev_q[s]  <= 1'b0;
                brk_q[s]  <= 1'b0;
                cmp_q[s]  <= 16'd0;
                rep_q[s]  <= 10'sd0;
                gate_q[s] <= 1'b1;
                seek_q[s] <= 1'b0;
                hold[s]   <= 1'b1;
                if (mode == M_BRK)
                    brk_q[s] <= 1'b1;
                else if (mode == M_AUTO) begin
                    if (apc != 10'd0) begin
                        gate_q[s] <= 1'b0;
                        cmp_q[s]  <= cmpa;
                        fwd_q[s]  <= pw[9] ? inv : !inv;
                        rev_q[s]  <= pw[9] ? !inv : inv;
                        rep_q[s]  <= (pw[9] ^ inv) ? -$signed(apc) : $signed(apc);
                    end
                end else if (armed_s && far) begin
                    // Position: + is toward the larger count.
                    hold[s]   <= 1'b0;
                    gate_q[s] <= 1'b0;
                    seek_q[s] <= 1'b1;
                    cmp_q[s]  <= CMP_PWR;
                    fwd_q[s]  <= d_r[20] ? pol[s] : !pol[s];
                    rev_q[s]  <= d_r[20] ? !pol[s] : pol[s];
                    rep_q[s]  <= d_r[20] ? -REP_PWR : REP_PWR;
                end else if (armed_s && (STOP_BRAKE != 0))
                    brk_q[s] <= 1'b1;
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
            z_ok[0] <= 1'b1;
            if (!f_ok[0])
                fmax[0] <= 20'd0;
        end
        if (x_final) begin
            fmax[0] <= posq[0];
            f_ok[0] <= 1'b1;
        end
        if (y_zero) begin
            posq[1] <= 20'd0;
            z_ok[1] <= 1'b1;
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
            z_ok    <= 2'b00;
            f_ok    <= 2'b00;
            have    <= 2'b00;
            dir_on  <= 2'b00;
            dir_dn  <= 2'b00;
        end
    end

    assign x_fwd   = fwd_q[0];
    assign x_rev   = rev_q[0];
    assign x_brake = brk_q[0];
    assign x_cmp   = cmp_q[0];
    assign x_rep   = rep_q[0];
    assign x_sens  = posq[0];
    assign x_tgt   = tgt_q[0];
    assign x_moved = moved_q[0];
    assign x_gate  = gate_q[0];
    assign x_arm   = f_ok[0];
    assign x_hlo   = z_ok[0];
    assign x_hhi   = f_ok[0];
    assign y_fwd   = fwd_q[1];
    assign y_rev   = rev_q[1];
    assign y_brake = brk_q[1];
    assign y_cmp   = cmp_q[1];
    assign y_rep   = rep_q[1];
    assign y_sens  = posq[1];
    assign y_tgt   = tgt_q[1];
    assign y_moved = moved_q[1];
    assign y_gate  = gate_q[1];
    assign y_arm   = f_ok[1];
    assign y_hlo   = z_ok[1];
    assign y_hhi   = f_ok[1];
endmodule
