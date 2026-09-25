// Pot percent is a speed setpoint, 100 % = 1000 um/s.
// N20 12 V 3000 RPM is 1:10. Hall 7 PPR, quadrature = 280 counts
// per output turn. Assumed screw 500 um/turn -> 560 counts/s at the cap.
// Edges faster than the setpoint lower the PWM. A skipped Gray step
// (ADC missed pulses) cuts harder. End-stop is enc_pos, via effort.
// Top gives Y twice X's PWM ceiling: Y carries X, both target 1000 um/s.
// Hall feedback is crossed vs the V5..V8 labels: X hears V7/V8, Y hears V5/V6.
module spd_ctl #(
    parameter integer PERIOD   = 1350,
    parameter integer MAX_CMP  = 270,
    parameter integer MIN_HIGH = 27,
    parameter integer STEP_UP  = 20,
    parameter integer STEP_DN  = 60,
    parameter integer SAT      = 54
) (
    input  wire        clk,
    input  wire        sample,
    input  wire        pot_fwd,
    input  wire        pot_rev,
    input  wire [6:0]  pot_pct,
    input  wire        moved,
    input  wire        skip,
    input  wire        lock_p,
    input  wire        lock_n,
    output reg         fwd,
    output reg         rev,
    output reg  [10:0] cmp,
    output reg         effort,
    output reg  [3:0]  spd_th,
    output reg  [3:0]  spd_hu,
    output reg  [3:0]  spd_te,
    output reg  [3:0]  spd_on
);
    localparam [17:0] BIAS = 18'd20000;
    localparam [17:0] HI   = 18'd28000;
    localparam [17:0] LO   = 18'd12000;
    localparam [17:0] UP   = 18'd21500;
    localparam [17:0] DN   = 18'd18500;

    reg [17:0] acc   = 18'd20000;
    reg [6:0]  win   = 7'd0;
    reg [7:0]  edges = 8'd0;

    wire        want = pot_fwd ^ pot_rev;
    wire        blocked = (pot_fwd && !pot_rev && lock_p) ||
                          (pot_rev && !pot_fwd && lock_n);
    wire        run = want && !blocked;
    wire [12:0] prod = {6'd0, pot_pct} * 13'd56;
    wire [9:0]  add = prod / 13'd10;

    wire [17:0] sum = acc + {8'd0, add};
    wire [17:0] cut = skip ? 18'd4000 : (moved ? 18'd1000 : 18'd0);
    wire [17:0] raw = (sum > cut) ? (sum - cut) : 18'd0;
    wire [17:0] nxt = (raw < LO) ? LO : (raw > HI) ? HI : raw;

    wire        up = run && (nxt > UP);
    wire        dn = run && ((nxt < DN) || skip);
    wire [11:0] raised = {1'b0, cmp} + STEP_UP[11:0];
    wire [10:0] up_c = (raised > MAX_CMP[11:0]) ? MAX_CMP[10:0] : raised[10:0];
    wire [10:0] up_m = ((up_c != 11'd0) && (up_c < MIN_HIGH[10:0])) ? MIN_HIGH[10:0] : up_c;
    wire [10:0] dn_c = (cmp > STEP_DN[10:0]) ? (cmp - STEP_DN[10:0]) : 11'd0;

    wire [7:0]  tally = edges + {7'd0, moved};
    wire [11:0] ums   = {3'd0, tally, 1'b0} + {2'd0, tally, 2'b00} + {1'd0, tally, 3'b000};
    wire [11:0] a1    = (ums >= 12'd1000) ? (ums - 12'd1000) : ums;
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
    wire [11:0] a3 = a2 - {8'd0, te_w} * 12'd10;

    initial begin
        fwd    = 1'b0;
        rev    = 1'b0;
        cmp    = 11'd0;
        effort = 1'b0;
        spd_th = 4'd0;
        spd_hu = 4'd0;
        spd_te = 4'd0;
        spd_on = 4'd0;
    end

    always @(posedge clk) begin
        if (sample) begin
            if (!run)
                acc <= BIAS;
            else
                acc <= nxt;

            if (!run) begin
                fwd <= 1'b0;
                rev <= 1'b0;
                cmp <= 11'd0;
            end else begin
                fwd <= pot_fwd;
                rev <= pot_rev;
                if (dn)
                    cmp <= dn_c;
                else if (up)
                    cmp <= up_m;
            end
            effort <= run && (up ? (up_m >= SAT[10:0]) : (dn ? (dn_c >= SAT[10:0]) : (cmp >= SAT[10:0])));

            if (win == 7'd127) begin
                spd_th <= (ums >= 12'd1000) ? 4'd1 : 4'd0;
                spd_hu <= hu_w;
                spd_te <= te_w;
                spd_on <= a3[3:0];
                edges  <= 8'd0;
                win    <= 7'd0;
            end else begin
                edges <= tally;
                win   <= win + 7'd1;
            end
        end
    end
endmodule
