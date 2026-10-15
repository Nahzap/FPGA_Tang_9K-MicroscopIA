`include "config.vh"
// Lab 206 serial protocol, CFG_BAUD 8N1 (BL702 USB-UART on this board).
// RX: M N B A,pa,pb T,cx,cy,px,py I,ix,iy P,axis,sign,idx Q,axis,pot,n reset
//     x_zero y_zero x_final y_final  (one line each, volatile marks)
//     A line ends at CR or LF. M also ends calibration (leaves RESET).
//     Powers are integer %, signed, clipped to +-POWER.
//     T: AUTO, X to count cx and Y to cy, at px and py % (0 brakes that
//     axis). Ignored in RESET. Counts 0..999999, motion caps them at the max.
//     Reset or a mark in AUTO leaves PWM_0.
//     P: 20*(idx+1) ms at +-PULSE %. Q: n PWM periods (1..65535) at pot %,
//     counted by pwm_drv (q_busy). Both end in PWM_0.
// TX: header once, then
//     PotenciaA,PotenciaB,PotA,PotB,Sensor1,Sensor2,Estado,Settled
//     PotenciaA/B = % applied, signed, from top (rep_a/rep_b). A = X, B = Y.
//     PotA/PotB = count X/Y goes to (pot, or cx/cy in AUTO).
//     Sensor1/Sensor2 = X/Y count.
//     Estado: RESET MANUAL AUTO BRAKE PULSE, or PWM_X PWM_Y PWM_XY PWM_0
//     (A/N: free power, named by the axes with power).
module com_ctrl #(
    parameter integer DIV   = `CFG_UART_DIV,
    parameter integer GAP   = `CFG_LINE_GAP,   // < 2^20 clocks
    parameter integer TICK  = `CFG_CLK_HZ / 1000,
    parameter integer POWER = 100,   // % cap of A, T and Q power
    parameter integer PULSE = `CFG_PULSE_PCT,
    parameter integer INV_X = 0,
    parameter integer INV_Y = 0
) (
    input  wire               clk,
    input  wire               rx,
    output reg                tx,
    input  wire signed [9:0]  rep_a,
    input  wire signed [9:0]  rep_b,
    input  wire [19:0]        sensor1,
    input  wire [19:0]        sensor2,
    input  wire [19:0]        pot_a,
    input  wire [19:0]        pot_b,
    output wire [23:0]        x_dig,
    output wire [23:0]        y_dig,
    input  wire               in_gate_a,
    input  wire               in_gate_b,
    input  wire               x_arm,
    input  wire               y_arm,
    output wire [1:0]         mode,
    output wire signed [9:0]  pwr_a,
    output wire signed [9:0]  pwr_b,
    output wire [19:0]        tgt_x,
    output wire [19:0]        tgt_y,
    output wire               inv_x,
    output wire               inv_y,
    output reg                x_zero_p,
    output reg                y_zero_p,
    output reg                x_final_p,
    output reg                y_final_p,
    output reg                rst_p,
    output reg                lock_p,
    input  wire               q_busy,
    output reg                q_go_x,
    output reg                q_go_y,
    output reg signed [9:0]   q_pot,
    output reg [15:0]         q_n,
    output wire               in_reset,
    output reg                ord_p
);
    localparam [1:0] M_MAN  = 2'd0;
    localparam [1:0] M_PWM  = 2'd1;
    localparam [1:0] M_BRK  = 2'd2;
    localparam [1:0] M_AUTO = 2'd3;
    localparam signed [20:0] PMF  = POWER;
    localparam signed [9:0]  PM10 = POWER;
    localparam signed [9:0]  PP10 = PULSE;
    localparam [495:0] HDR =
        "PotenciaA,PotenciaB,PotA,PotB,Sensor1,Sensor2,Estado,Settled\015\012";
    localparam [7:0] CR = 8'h0D, LF = 8'h0A;

    (* mem2reg *) reg [7:0] rxb [0:39];
    (* mem2reg *) reg [7:0] txb [0:61];   // longest line: the 62-byte header

    reg [1:0]        mode_q   = M_MAN;
    reg              rst_q    = 1'b1;   // RESET until both axes are calibrated
    reg              both_d   = 1'b0;
    reg signed [9:0] pwr_a_q  = 10'sd0;
    reg signed [9:0] pwr_b_q  = 10'sd0;
    reg [19:0]       tgt_x_q  = 20'd0;
    reg [19:0]       tgt_y_q  = 20'd0;
    reg              inv_x_q  = (INV_X != 0);
    reg              inv_y_q  = (INV_Y != 0);
    reg              p_y      = 1'b0;
    reg signed [9:0] p_mag    = 10'sd0;
    reg [7:0]        pms      = 8'd0;
    reg [15:0]       tk       = 16'd0;

    reg        parsing = 1'b0;
    reg        apply   = 1'b0;
    reg [5:0]  rlen    = 6'd0;
    reg [5:0]  plen    = 6'd0;
    reg [5:0]  pi      = 6'd0;
    reg [19:0] acc     = 20'd0;   // saturates at 999999
    reg        neg     = 1'b0;
    reg [1:0]  fld     = 2'd0;
    reg        saw_num = 1'b0;
    reg        saw_ax  = 1'b0;
    reg        have_c  = 1'b0;
    reg        have_d  = 1'b0;
    reg signed [20:0] fa = 21'sd0;
    reg signed [20:0] fb = 21'sd0;
    reg signed [20:0] fc = 21'sd0;
    reg signed [20:0] fd = 21'sd0;
    reg [7:0]  cmd     = 8'd0;
    reg [7:0]  axc     = 8'd0;

    function [7:0] lowc;
        input [7:0] c;
        begin
            if ((c >= "A") && (c <= "Z"))
                lowc = c + 8'd32;
            else
                lowc = c;
        end
    endfunction

    wire mark_xz = (plen == 6'd6) &&
                   (lowc(rxb[0]) == "x") && (rxb[1] == "_") &&
                   (lowc(rxb[2]) == "z") && (lowc(rxb[3]) == "e") &&
                   (lowc(rxb[4]) == "r") && (lowc(rxb[5]) == "o");
    wire mark_yz = (plen == 6'd6) &&
                   (lowc(rxb[0]) == "y") && (rxb[1] == "_") &&
                   (lowc(rxb[2]) == "z") && (lowc(rxb[3]) == "e") &&
                   (lowc(rxb[4]) == "r") && (lowc(rxb[5]) == "o");
    wire mark_xf = (plen == 6'd7) &&
                   (lowc(rxb[0]) == "x") && (rxb[1] == "_") &&
                   (lowc(rxb[2]) == "f") && (lowc(rxb[3]) == "i") &&
                   (lowc(rxb[4]) == "n") && (lowc(rxb[5]) == "a") &&
                   (lowc(rxb[6]) == "l");
    wire mark_yf = (plen == 6'd7) &&
                   (lowc(rxb[0]) == "y") && (rxb[1] == "_") &&
                   (lowc(rxb[2]) == "f") && (lowc(rxb[3]) == "i") &&
                   (lowc(rxb[4]) == "n") && (lowc(rxb[5]) == "a") &&
                   (lowc(rxb[6]) == "l");
    wire mark_rst = (plen == 6'd5) &&
                    (lowc(rxb[0]) == "r") && (lowc(rxb[1]) == "e") &&
                    (lowc(rxb[2]) == "s") && (lowc(rxb[3]) == "e") &&
                    (lowc(rxb[4]) == "t");
    wire is_mark = mark_rst || mark_xz || mark_yz || mark_xf || mark_yf;
    reg signed [20:0] vtmp;

    // rx comes from the BL702, asynchronous to clk: two flops first.
    reg [1:0]  rx_ff = 2'b11;
    wire       rx_s  = rx_ff[1];
    always @(posedge clk)
        rx_ff <= {rx_ff[0], rx};

    reg [1:0]  ust  = 2'd0;
    reg [15:0] divc = 16'd0;
    reg [3:0]  bitn = 4'd0;
    reg [7:0]  sh   = 8'd0;
    reg        got  = 1'b0;
    reg [7:0]  gdat = 8'd0;

    reg        sent_hdr = 1'b0;
    reg        load     = 1'b0;
    reg        is_hdr   = 1'b0;
    reg        arm      = 1'b0;
    reg        tx_on    = 1'b0;
    reg [5:0]  tlen     = 6'd0;
    reg [5:0]  ti       = 6'd0;
    reg [3:0]  bc       = 4'd0;
    reg [15:0] dv       = 16'd0;
    reg [7:0]  cur      = 8'd0;
    reg [19:0] gapc     = 20'd0;

    integer hi;

    wire pulsing = (pms != 8'd0);
    wire pul_st  = pulsing || q_busy;
    wire ax_y    = (axc == "B") || (axc == "b") || (axc == "Y") ||
                   (axc == "y") || (axc == "1") ||
                   ((axc == 8'd0) && (fa == 21'sd1));
    assign in_reset = rst_q;
    assign mode  = pulsing ? M_PWM : mode_q;
    assign pwr_a = pulsing ? (p_y ? 10'sd0 : p_mag) : pwr_a_q;
    assign pwr_b = pulsing ? (p_y ? p_mag : 10'sd0) : pwr_b_q;
    assign tgt_x = tgt_x_q;
    assign tgt_y = tgt_y_q;
    assign inv_x = inv_x_q;
    assign inv_y = inv_y_q;

    // Four six-digit fields and two three-digit ones, one subtractor.
    // Field 0 Sensor1 (Y), 1 Sensor2 (X), 2 PotA (X), 3 PotB (Y): 0..999999.
    // Field 4 |PotenciaA|, 5 |PotenciaB|: places 3..5 only (|rep| <= 100).
    // Slot {field, place}.
    reg [3:0] dw [0:47];
    reg [3:0] dd [0:47];
    reg [19:0] rem = 0;
    reg [3:0]  accd = 0;
    reg [2:0]  place = 0;
    reg [2:0]  which = 0;
    reg        conv = 0;
    reg        sa_w = 0, sb_w = 0, sa_d = 0, sb_d = 0;
    wire [6:0] ra_m = rep_a[9] ? -rep_a[6:0] : rep_a[6:0];
    wire [6:0] rb_m = rep_b[9] ? -rep_b[6:0] : rep_b[6:0];
    wire [19:0] dec =
        (place == 3'd0) ? 20'd100000 :
        (place == 3'd1) ? 20'd10000 :
        (place == 3'd2) ? 20'd1000 :
        (place == 3'd3) ? 20'd100 :
        (place == 3'd4) ? 20'd10 : 20'd1;
    wire [19:0] fld_v =
        (which == 3'd0) ? sensor2 :
        (which == 3'd1) ? pot_a :
        (which == 3'd2) ? pot_b :
        (which == 3'd3) ? {13'd0, ra_m} : {13'd0, rb_m};

    integer di;
    initial begin
        for (di = 0; di < 48; di = di + 1) begin
            dw[di] = 4'd0;
            dd[di] = 4'd0;
        end
    end

    always @(posedge clk) begin
        if (!conv) begin
            rem   <= sensor1;
            accd  <= 4'd0;
            place <= 3'd0;
            which <= 3'd0;
            conv  <= 1'b1;
        end else if (rem >= dec) begin
            rem  <= rem - dec;
            accd <= accd + 4'd1;
        end else begin
            accd <= 4'd0;
            dw[{which, place}] <= accd;
            if (place == 3'd5) begin
                if (which == 3'd5) begin
                    for (di = 0; di < 48; di = di + 1)
                        dd[di] <= dw[di];
                    dd[45] <= accd;
                    sa_d <= sa_w;
                    sb_d <= sb_w;
                    conv <= 1'b0;
                end else begin
                    rem   <= fld_v;
                    which <= which + 3'd1;
                    place <= (which >= 3'd3) ? 3'd3 : 3'd0;
                    if (which == 3'd3) sa_w <= rep_a[9];
                    if (which == 3'd4) sb_w <= rep_b[9];
                end
            end else
                place <= place + 3'd1;
        end
    end
    assign x_dig = {dd[0], dd[1], dd[2], dd[3], dd[4], dd[5]};
    assign y_dig = {dd[8], dd[9], dd[10], dd[11], dd[12], dd[13]};

    wire [2:0] stc =
        rst_q ? 3'd4 :
        pul_st ? 3'd6 :
        (mode_q == M_AUTO) ? 3'd1 :
        (mode_q == M_BRK)  ? 3'd2 :
        (mode_q == M_PWM)  ? 3'd3 : 3'd0;
    wire pwm_x = (pwr_a_q != 10'sd0);
    wire pwm_y = (pwr_b_q != 10'sd0);
    wire set_b =
        pul_st ? 1'b0 :
        (mode_q == M_BRK) ? 1'b1 :
        ((rep_a == 10'sd0) && (rep_b == 10'sd0));

    function [7:0] dig;
        input [3:0] d;
        begin
            dig = 8'd48 + {4'd0, d};
        end
    endfunction

    function [7:0] hdr_at;
        input integer idx;
        begin
            hdr_at = HDR[((61 - idx) * 8) +: 8];
        end
    endfunction

    initial tx = 1'b1;

    initial begin
        x_zero_p  = 1'b0;
        y_zero_p  = 1'b0;
        x_final_p = 1'b0;
        y_final_p = 1'b0;
        rst_p     = 1'b0;
        lock_p    = 1'b0;
        q_go_x    = 1'b0;
        q_go_y    = 1'b0;
        q_pot     = 10'sd0;
        q_n       = 16'd0;
        ord_p     = 1'b0;
    end

    always @(posedge clk) begin
        got       <= 1'b0;
        x_zero_p  <= 1'b0;
        y_zero_p  <= 1'b0;
        x_final_p <= 1'b0;
        y_final_p <= 1'b0;
        rst_p     <= 1'b0;
        lock_p    <= 1'b0;
        q_go_x    <= 1'b0;
        q_go_y    <= 1'b0;
        ord_p     <= 1'b0;
        both_d    <= x_arm && y_arm;
        if (x_arm && y_arm && !both_d)
            rst_q <= 1'b0;

        if (ust == 2'd0) begin
            if (!rx_s) begin
                ust  <= 2'd1;
                divc <= 16'd0;
            end
        end else if (ust == 2'd1) begin
            if (divc == DIV[15:0] / 16'd2) begin
                if (rx_s)
                    ust <= 2'd0;
                else begin
                    ust  <= 2'd2;
                    divc <= 16'd0;
                    bitn <= 4'd0;
                end
            end else
                divc <= divc + 16'd1;
        end else if (divc == DIV[15:0] - 16'd1) begin
            divc <= 16'd0;
            if (bitn < 4'd8) begin
                sh   <= {rx_s, sh[7:1]};
                bitn <= bitn + 4'd1;
            end else begin
                ust  <= 2'd0;
                got  <= 1'b1;
                gdat <= sh;
            end
        end else
            divc <= divc + 16'd1;

        if (apply) begin
            apply <= 1'b0;
            ord_p <= 1'b1;
            if (is_mark && (mode_q == M_AUTO)) begin
                mode_q <= M_PWM; pwr_a_q <= 10'sd0; pwr_b_q <= 10'sd0;
            end
            if (mark_rst) begin
                rst_p <= 1'b1;
                rst_q <= 1'b1;
            end else if (mark_xz)
                x_zero_p <= 1'b1;
            else if (mark_yz)
                y_zero_p <= 1'b1;
            else if (mark_xf)
                x_final_p <= 1'b1;
            else if (mark_yf)
                y_final_p <= 1'b1;
            else case (cmd)
                "M", "m": begin
                    // Also ends calibration: leave RESET, keep the max reached.
                    mode_q <= M_MAN; pwr_a_q <= 10'sd0; pwr_b_q <= 10'sd0; pms <= 8'd0;
                    rst_q  <= 1'b0;
                    lock_p <= 1'b1;
                end
                "B", "b": begin
                    mode_q <= M_BRK; pwr_a_q <= 10'sd0; pwr_b_q <= 10'sd0; pms <= 8'd0;
                end
                "N", "n": begin
                    mode_q <= M_PWM; pwr_a_q <= 10'sd0; pwr_b_q <= 10'sd0; pms <= 8'd0;
                end
                "A", "a": begin
                    mode_q <= M_PWM;
                    pms    <= 8'd0;
                    if (fa > PMF)
                        pwr_a_q <= PM10;
                    else if (fa < -PMF)
                        pwr_a_q <= -PM10;
                    else
                        pwr_a_q <= fa[9:0];
                    if (fb > PMF)
                        pwr_b_q <= PM10;
                    else if (fb < -PMF)
                        pwr_b_q <= -PM10;
                    else
                        pwr_b_q <= fb[9:0];
                end
                "T", "t": begin
                    if (!rst_q && have_d) begin
                        mode_q  <= M_AUTO;
                        pms     <= 8'd0;
                        tgt_x_q <= fa[20] ? 20'd0 : fa[19:0];
                        tgt_y_q <= fb[20] ? 20'd0 : fb[19:0];
                        pwr_a_q <= fc[20] ? 10'sd0 : (fc > PMF) ? PM10 : fc[9:0];
                        pwr_b_q <= fd[20] ? 10'sd0 : (fd > PMF) ? PM10 : fd[9:0];
                    end
                end
                "I", "i": begin
                    inv_x_q <= (fa != 21'sd0);
                    inv_y_q <= (fb != 21'sd0);
                end
                "P", "p": begin
                    if (fb != 21'sd0) begin
                        p_y   <= ax_y;
                        p_mag <= (fb > 21'sd0) ? PP10 : -PP10;
                        tk    <= 16'd0;
                        if (fc < 21'sd0)
                            pms <= 8'd20;
                        else if (fc > 21'sd7)
                            pms <= 8'd160;
                        else
                            pms <= (fc[2:0] + 3'd1) * 8'd20;
                        mode_q  <= M_PWM;
                        pwr_a_q <= 10'sd0;
                        pwr_b_q <= 10'sd0;
                    end
                end
                "Q", "q": begin
                    if ((fb != 21'sd0) && (fc > 21'sd0)) begin
                        q_go_x  <= !ax_y;
                        q_go_y  <= ax_y;
                        q_pot   <= (fb > PMF) ? PM10 : (fb < -PMF) ? -PM10 : fb[9:0];
                        q_n     <= (fc > 21'sd65535) ? 16'hFFFF : fc[15:0];
                        mode_q  <= M_PWM;
                        pms     <= 8'd0;
                        pwr_a_q <= 10'sd0;
                        pwr_b_q <= 10'sd0;
                    end
                end
                default: ;
            endcase
        end else if (pms != 8'd0) begin
            if (tk == TICK[15:0] - 16'd1) begin
                tk  <= 16'd0;
                pms <= pms - 8'd1;
            end else
                tk <= tk + 16'd1;
        end

        if (parsing) begin
            if (pi >= plen) begin
                parsing <= 1'b0;
                rlen    <= 6'd0;
                apply   <= 1'b1;
                if (saw_num) begin
                    vtmp = neg ? -$signed({1'b0, acc}) : $signed({1'b0, acc});
                    if (fld == 2'd0)
                        fa <= vtmp;
                    else if (fld == 2'd1)
                        fb <= vtmp;
                    else if (fld == 2'd2) begin
                        fc     <= vtmp;
                        have_c <= 1'b1;
                    end else begin
                        fd     <= vtmp;
                        have_d <= 1'b1;
                    end
                end
            end else begin
                if (pi == 6'd0) begin
                    cmd <= rxb[pi];
                end else if ((rxb[pi] == "+")) begin
                    neg <= 1'b0;
                end else if (rxb[pi] == "-") begin
                    neg <= 1'b1;
                end else if ((rxb[pi] >= "0") && (rxb[pi] <= "9")) begin
                    acc     <= (acc > 20'd99999) ? 20'd999999 :
                               (acc * 20'd10) + (rxb[pi] - 8'd48);
                    saw_num <= 1'b1;
                end else if ((fld == 2'd0) &&
                             ((rxb[pi] == "A") || (rxb[pi] == "a") ||
                              (rxb[pi] == "B") || (rxb[pi] == "b") ||
                              (rxb[pi] == "X") || (rxb[pi] == "x") ||
                              (rxb[pi] == "Y") || (rxb[pi] == "y"))) begin
                    axc    <= rxb[pi];
                    saw_ax <= 1'b1;
                end else if (rxb[pi] == ",") begin
                    if (saw_num) begin
                        vtmp = neg ? -$signed({1'b0, acc}) : $signed({1'b0, acc});
                        if (fld == 2'd0)
                            fa <= vtmp;
                        else if (fld == 2'd1)
                            fb <= vtmp;
                        else if (fld == 2'd2) begin
                            fc     <= vtmp;
                            have_c <= 1'b1;
                        end else begin
                            fd     <= vtmp;
                            have_d <= 1'b1;
                        end
                    end
                    if ((saw_num || saw_ax) && (fld != 2'd3))
                        fld <= fld + 2'd1;
                    acc     <= 20'd0;
                    neg     <= 1'b0;
                    saw_num <= 1'b0;
                    saw_ax  <= 1'b0;
                end
                pi <= pi + 6'd1;
            end
        end else if (got && ((gdat == LF) || (gdat == CR)) && (rlen != 6'd0)) begin
            parsing <= 1'b1;
            plen    <= rlen;
            pi      <= 6'd0;
            acc     <= 20'd0;
            neg     <= 1'b0;
            fld     <= 2'd0;
            saw_num <= 1'b0;
            saw_ax  <= 1'b0;
            have_c  <= 1'b0;
            have_d  <= 1'b0;
            fa      <= 21'sd0;
            fb      <= 21'sd0;
            fc      <= 21'sd0;
            fd      <= 21'sd0;
            axc     <= 8'd0;
        end else if (got && (gdat != CR) && (gdat != LF) && (rlen < 6'd40)) begin
            rxb[rlen] <= gdat;
            rlen      <= rlen + 6'd1;
        end
    end

    always @(posedge clk) begin
        if (!tx_on && !arm && !load) begin
            if (!sent_hdr) begin
                load     <= 1'b1;
                is_hdr   <= 1'b1;
                sent_hdr <= 1'b1;
            end else if (gapc == GAP[19:0] - 20'd1) begin
                gapc   <= 20'd0;
                load   <= 1'b1;
                is_hdr <= 1'b0;
            end else
                gapc <= gapc + 20'd1;
        end

        if (load) begin
            load <= 1'b0;
            arm  <= 1'b1;
            if (is_hdr) begin
                for (hi = 0; hi < 62; hi = hi + 1)
                    txb[hi] <= hdr_at(hi);
                tlen <= 6'd62;
            end else begin
                txb[0]  <= sa_d ? "-" : "+";
                txb[1]  <= dig(dd[35]);
                txb[2]  <= dig(dd[36]);
                txb[3]  <= dig(dd[37]);
                txb[4]  <= ",";
                txb[5]  <= sb_d ? "-" : "+";
                txb[6]  <= dig(dd[43]);
                txb[7]  <= dig(dd[44]);
                txb[8]  <= dig(dd[45]);
                txb[9]  <= ",";
                txb[10] <= dig(dd[16]);
                txb[11] <= dig(dd[17]);
                txb[12] <= dig(dd[18]);
                txb[13] <= dig(dd[19]);
                txb[14] <= dig(dd[20]);
                txb[15] <= dig(dd[21]);
                txb[16] <= ",";
                txb[17] <= dig(dd[24]);
                txb[18] <= dig(dd[25]);
                txb[19] <= dig(dd[26]);
                txb[20] <= dig(dd[27]);
                txb[21] <= dig(dd[28]);
                txb[22] <= dig(dd[29]);
                txb[23] <= ",";
                txb[24] <= dig(dd[0]);
                txb[25] <= dig(dd[1]);
                txb[26] <= dig(dd[2]);
                txb[27] <= dig(dd[3]);
                txb[28] <= dig(dd[4]);
                txb[29] <= dig(dd[5]);
                txb[30] <= ",";
                txb[31] <= dig(dd[8]);
                txb[32] <= dig(dd[9]);
                txb[33] <= dig(dd[10]);
                txb[34] <= dig(dd[11]);
                txb[35] <= dig(dd[12]);
                txb[36] <= dig(dd[13]);
                txb[37] <= ",";
                case (stc)
                    3'd1: begin
                        txb[38] <= "A"; txb[39] <= "U"; txb[40] <= "T"; txb[41] <= "O";
                        txb[42] <= ","; txb[43] <= set_b ? "1" : "0";
                        txb[44] <= CR; txb[45] <= LF;
                        tlen <= 6'd46;
                    end
                    3'd3: begin
                        txb[38] <= "P"; txb[39] <= "W"; txb[40] <= "M"; txb[41] <= "_";
                        if (pwm_x && pwm_y) begin
                            txb[42] <= "X"; txb[43] <= "Y";
                            txb[44] <= ","; txb[45] <= set_b ? "1" : "0";
                            txb[46] <= CR; txb[47] <= LF;
                            tlen <= 6'd48;
                        end else begin
                            txb[42] <= pwm_x ? "X" : pwm_y ? "Y" : "0";
                            txb[43] <= ","; txb[44] <= set_b ? "1" : "0";
                            txb[45] <= CR; txb[46] <= LF;
                            tlen <= 6'd47;
                        end
                    end
                    3'd2: begin
                        txb[38] <= "B"; txb[39] <= "R"; txb[40] <= "A";
                        txb[41] <= "K"; txb[42] <= "E";
                        txb[43] <= ","; txb[44] <= "1";
                        txb[45] <= CR; txb[46] <= LF;
                        tlen <= 6'd47;
                    end
                    3'd6: begin
                        txb[38] <= "P"; txb[39] <= "U"; txb[40] <= "L";
                        txb[41] <= "S"; txb[42] <= "E";
                        txb[43] <= ","; txb[44] <= "0";
                        txb[45] <= CR; txb[46] <= LF;
                        tlen <= 6'd47;
                    end
                    3'd4: begin
                        txb[38] <= "R"; txb[39] <= "E"; txb[40] <= "S";
                        txb[41] <= "E"; txb[42] <= "T";
                        txb[43] <= ","; txb[44] <= "0";
                        txb[45] <= CR; txb[46] <= LF;
                        tlen <= 6'd47;
                    end
                    default: begin
                        txb[38] <= "M"; txb[39] <= "A"; txb[40] <= "N";
                        txb[41] <= "U"; txb[42] <= "A"; txb[43] <= "L";
                        txb[44] <= ","; txb[45] <= set_b ? "1" : "0";
                        txb[46] <= CR; txb[47] <= LF;
                        tlen <= 6'd48;
                    end
                endcase
            end
        end else if (arm) begin
            arm   <= 1'b0;
            tx_on <= 1'b1;
            ti    <= 6'd0;
            bc    <= 4'd0;
            dv    <= 16'd0;
            cur   <= txb[0];
            tx    <= 1'b0;
        end else if (tx_on) begin
            if (dv == DIV[15:0] - 16'd1) begin
                dv <= 16'd0;
                if (bc == 4'd9) begin
                    if (ti + 6'd1 >= tlen) begin
                        tx_on <= 1'b0;
                        tx    <= 1'b1;
                    end else begin
                        ti  <= ti + 6'd1;
                        cur <= txb[ti + 6'd1];
                        bc  <= 4'd0;
                        tx  <= 1'b0;
                    end
                end else if (bc == 4'd8) begin
                    tx <= 1'b1;
                    bc <= 4'd9;
                end else begin
                    tx <= cur[bc[2:0]];
                    bc <= bc + 4'd1;
                end
            end else
                dv <= dv + 16'd1;
        end
    end
endmodule
