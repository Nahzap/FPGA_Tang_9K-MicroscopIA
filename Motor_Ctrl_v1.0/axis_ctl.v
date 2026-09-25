// One motor. MANUAL follows its pot (Lab 206 getManualPower).
// FINE follows F,ref against this axis encoder rate (not a distance).
// AUTO applies a host power. BRAKE is IN1=IN2 high.
module axis_ctl #(
    parameter integer PERIOD   = 1350,
    parameter integer LO       = 7124,
    parameter integer HI       = 14269,
    parameter integer FULL     = 21626,
    parameter integer UMAN_MIN = 476,
    parameter integer UMIN     = 476,
    parameter integer UMAX     = 488,
    parameter integer TH       = 10813,
    parameter integer WIN      = 64,
    parameter integer SOFT     = 2048
) (
    input  wire               clk,
    input  wire               sample,
    input  wire [1:0]         mode,
    input  wire signed [9:0]  auto_pwr,
    input  wire [11:0]        ref_s,
    input  wire [5:0]         gate_e,
    input  wire               inv,
    input  wire [15:0]        pot,
    input  wire [15:0]        raw_a,
    input  wire [15:0]        raw_b,
    output reg                fwd,
    output reg                rev,
    output reg                brake,
    output reg         [10:0] cmp,
    output reg  signed [9:0]  rep,
    output reg         [11:0] sensor,
    output reg                moved,
    output reg                in_gate,
    output reg         [3:0]  spd_th,
    output reg         [3:0]  spd_hu,
    output reg         [3:0]  spd_te,
    output reg         [3:0]  spd_on
);
    localparam [1:0] M_MAN  = 2'd0;
    localparam [1:0] M_AUTO = 2'd1;
    localparam [1:0] M_BRK  = 2'd2;
    localparam [1:0] M_FINE = 2'd3;
    // Manual slope is dlt>>3. Both axes clamp at UMAX (power ±92).

    reg        have  = 1'b0;
    reg        a_r   = 1'b0;
    reg        b_r   = 1'b0;
    reg [5:0]  n     = 6'd0;
    reg [6:0]  edges = 7'd0;
    reg [5:0]  skips = 6'd0;
    reg        saw   = 1'b0;

    wire [15:0] pot_m = pot[15] ? 16'd0 : pot;
    wire [15:0] pot_c = (pot_m > FULL[15:0]) ? FULL[15:0] : pot_m;
    wire        man_hi = pot_c > HI[15:0];
    wire        man_lo = pot_c < LO[15:0];
    wire [15:0] dlt_f  = pot_c - HI[15:0];
    wire [15:0] dlt_r  = LO[15:0] - pot_c;
    wire [10:0] cmp_f  = UMAN_MIN[10:0] + dlt_f[13:3];
    wire [10:0] cmp_r  = UMAN_MIN[10:0] + dlt_r[13:3];

    wire signed [9:0] ap = auto_pwr;
    wire signed [9:0] ap_c =
        (ap > 10'sd92) ? 10'sd92 : (ap < -10'sd92) ? -10'sd92 : ap;
    wire [9:0] ap_abs = ap_c[9] ? (~ap_c + 10'd1) : ap_c;
    wire [19:0] ap_sc = ap_abs * 11'd1359;
    wire [10:0] cmp_raw = ap_sc[18:8];
    wire [10:0] cmp_a = (cmp_raw > UMAX[10:0]) ? UMAX[10:0] : cmp_raw;

    wire a_bit = !raw_a[15] && (raw_a >= TH[15:0]);
    wire b_bit = !raw_b[15] && (raw_b >= TH[15:0]);
    wire [1:0] prev = {a_r, b_r};
    wire [1:0] nows = {a_bit, b_bit};
    wire [3:0] tr   = {prev, nows};
    wire plus  = have && (tr == 4'b0001 || tr == 4'b0111 ||
                          tr == 4'b1110 || tr == 4'b1000);
    wire minus = have && (tr == 4'b0010 || tr == 4'b1011 ||
                          tr == 4'b1101 || tr == 4'b0100);
    wire flank = plus || minus;
    wire skip1 = have && (nows != prev) && !flank;

    wire [6:0] edge_n = edges + {6'd0, flank};
    wire [5:0] skip_n = skips + {5'd0, skip1};
    wire [12:0] sens_w = {edge_n, 6'b000000};
    wire [11:0] sens_n = (edge_n >= 7'd64) ? 12'd4095 : sens_w[11:0];
    wire [5:0] g_e = (gate_e == 6'd0) ? 6'd2 : gate_e;
    wire [11:0] g_lim = {g_e, 6'b000000};
    wire [11:0] ref_c = ref_s;
    wire [11:0] err_a = (ref_c > sens_n) ? (ref_c - sens_n) : (sens_n - ref_c);
    wire        in_band = !(err_a > g_lim);
    wire        need_up = inv ? (sens_n > ref_c) : (ref_c > sens_n);
    wire [11:0] over = in_band ? 12'd0 : (err_a - g_lim);
    wire [11:0] ae = (over > SOFT[11:0]) ? SOFT[11:0] : over;
    wire [21:0] cap_p = (UMAX[10:0] - UMIN[10:0]) * ae;
    wire [10:0] u_cap = UMIN[10:0] + cap_p[21:11];

    wire [24:0] mag_p = {14'd0, cmp} * 15'd12373;
    wire [8:0]  mag8  = mag_p[24:16];
    wire [11:0] ums   = {5'd0, edge_n} * 12'd28;
    wire [3:0]  th_w  = (ums >= 12'd1000) ? 4'd1 : 4'd0;
    wire [11:0] a1    = th_w ? (ums - 12'd1000) : ums;
    wire [3:0]  hu_w  =
        (a1 >= 12'd900) ? 4'd9 : (a1 >= 12'd800) ? 4'd8 :
        (a1 >= 12'd700) ? 4'd7 : (a1 >= 12'd600) ? 4'd6 :
        (a1 >= 12'd500) ? 4'd5 : (a1 >= 12'd400) ? 4'd4 :
        (a1 >= 12'd300) ? 4'd3 : (a1 >= 12'd200) ? 4'd2 :
        (a1 >= 12'd100) ? 4'd1 : 4'd0;
    wire [11:0] a2 = a1 - ({8'd0, hu_w} * 12'd100);
    wire [3:0]  te_w =
        (a2 >= 12'd90) ? 4'd9 : (a2 >= 12'd80) ? 4'd8 :
        (a2 >= 12'd70) ? 4'd7 : (a2 >= 12'd60) ? 4'd6 :
        (a2 >= 12'd50) ? 4'd5 : (a2 >= 12'd40) ? 4'd4 :
        (a2 >= 12'd30) ? 4'd3 : (a2 >= 12'd20) ? 4'd2 :
        (a2 >= 12'd10) ? 4'd1 : 4'd0;
    wire [11:0] a3 = a2 - ({8'd0, te_w} * 12'd10);
    wire [3:0]  on_w = a3[3:0];

    initial begin
        fwd = 1'b0; rev = 1'b0; brake = 1'b0; cmp = 11'd0;
        rep = 10'sd0; sensor = 12'd0; moved = 1'b0; in_gate = 1'b0;
        spd_th = 4'd0; spd_hu = 4'd0; spd_te = 4'd0; spd_on = 4'd0;
    end

    always @(posedge clk) begin
        if (sample) begin
            a_r  <= a_bit;
            b_r  <= b_bit;
            have <= 1'b1;

            if (n == WIN[5:0] - 6'd1) begin
                sensor  <= sens_n;
                moved   <= saw | flank;
                spd_th  <= th_w;
                spd_hu  <= hu_w;
                spd_te  <= te_w;
                spd_on  <= on_w;
                edges   <= 7'd0;
                skips   <= 6'd0;
                saw     <= 1'b0;
                n       <= 6'd0;
                if (mode == M_FINE) begin
                    if (skip_n != 6'd0) begin
                        fwd <= 1'b0; rev <= 1'b0; cmp <= 11'd0; in_gate <= 1'b0;
                    end else if (in_band) begin
                        fwd <= 1'b0; rev <= 1'b0; cmp <= 11'd0; in_gate <= 1'b1;
                    end else begin
                        in_gate <= 1'b0;
                        cmp <= u_cap;
                        fwd <= need_up;
                        rev <= !need_up;
                    end
                end
            end else begin
                edges <= edge_n;
                skips <= skip_n;
                saw   <= saw | flank;
                n     <= n + 6'd1;
            end

            brake <= (mode == M_BRK);
            if (mode == M_BRK) begin
                fwd <= 1'b0; rev <= 1'b0; cmp <= 11'd0; in_gate <= 1'b0;
            end else if (mode == M_AUTO) begin
                in_gate <= 1'b0;
                if (ap_c == 10'sd0) begin
                    fwd <= 1'b0; rev <= 1'b0; cmp <= 11'd0;
                end else if (!ap_c[9]) begin
                    fwd <= 1'b1; rev <= 1'b0; cmp <= cmp_a;
                end else begin
                    fwd <= 1'b0; rev <= 1'b1; cmp <= cmp_a;
                end
            end else if (mode == M_MAN) begin
                in_gate <= 1'b0;
                if (man_hi) begin
                    fwd <= 1'b1; rev <= 1'b0;
                    cmp <= (cmp_f > UMAX[10:0]) ? UMAX[10:0] : cmp_f;
                end else if (man_lo) begin
                    fwd <= 1'b0; rev <= 1'b1;
                    cmp <= (cmp_r > UMAX[10:0]) ? UMAX[10:0] : cmp_r;
                end else begin
                    fwd <= 1'b0; rev <= 1'b0; cmp <= 11'd0;
                end
            end

            if (brake || (mode == M_BRK) || !(fwd || rev))
                rep <= 10'sd0;
            else if (fwd && !rev)
                rep <= {1'b0, mag8};
            else
                rep <= -{1'b0, mag8};
        end
    end
endmodule
