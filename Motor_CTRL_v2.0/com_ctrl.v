`include "config.vh"
// Lab 206 serial protocol, CFG_BAUD 8N1 (BL702 USB-UART on this board).
// RX: M N B A,pa,pb I,ix,iy P,axis,sign,idx reset
//     x_zero y_zero x_final y_final  (one line each, volatile marks)
//     A line ends at CR or LF. M also ends calibration (leaves RESET).
// TX: header once, then
//     PotenciaA,PotenciaB,PotA,PotB,Sensor1,Sensor2,Estado,Settled
//     PotenciaA/B = % of the PWM period, signed. A = X, B = Y.
//     PotA/PotB = count the X/Y pot asks for. Sensor1/Sensor2 = X/Y count.
module com_ctrl #(
    parameter integer DIV   = `CFG_UART_DIV,
    parameter integer GAP   = `CFG_LINE_GAP,   // < 2^20 clocks
    parameter integer TICK  = `CFG_CLK_HZ / 1000,
    parameter integer POWER = `CFG_POWER,   // cap of A,pa,pb; P pulse power
    parameter integer INV_X = `CFG_INV_X,
    parameter integer INV_Y = `CFG_INV_Y
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
    output wire               inv_x,
    output wire               inv_y,
    output reg                x_zero_p,
    output reg                y_zero_p,
    output reg                x_final_p,
    output reg                y_final_p,
    output reg                rst_p,
    output reg                lock_p
);
    localparam [1:0] M_MAN  = 2'd0;
    localparam [1:0] M_AUTO = 2'd1;
    localparam [1:0] M_BRK  = 2'd2;
    localparam signed [15:0] PM16 = POWER;
    localparam signed [9:0]  PM10 = POWER;
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
    reg [15:0] acc     = 16'd0;
    reg        neg     = 1'b0;
    reg [1:0]  fld     = 2'd0;
    reg        saw_num = 1'b0;
    reg        saw_ax  = 1'b0;
    reg        have_c  = 1'b0;
    reg signed [15:0] fa = 16'sd0;
    reg signed [15:0] fb = 16'sd0;
    reg signed [15:0] fc = 16'sd0;
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
    reg signed [15:0] vtmp;

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
    assign mode  = pulsing ? M_AUTO : mode_q;
    assign pwr_a = pulsing ? (p_y ? 10'sd0 : p_mag) : pwr_a_q;
    assign pwr_b = pulsing ? (p_y ? p_mag : 10'sd0) : pwr_b_q;
    assign inv_x = inv_x_q;
    assign inv_y = inv_y_q;

    function [3:0] hun;
        input [11:0] v;
        begin
            if (v >= 12'd900) hun = 4'd9;
            else if (v >= 12'd800) hun = 4'd8;
            else if (v >= 12'd700) hun = 4'd7;
            else if (v >= 12'd600) hun = 4'd6;
            else if (v >= 12'd500) hun = 4'd5;
            else if (v >= 12'd400) hun = 4'd4;
            else if (v >= 12'd300) hun = 4'd3;
            else if (v >= 12'd200) hun = 4'd2;
            else if (v >= 12'd100) hun = 4'd1;
            else hun = 4'd0;
        end
    endfunction

    function [3:0] ten;
        input [11:0] v;
        begin
            if (v >= 12'd90) ten = 4'd9;
            else if (v >= 12'd80) ten = 4'd8;
            else if (v >= 12'd70) ten = 4'd7;
            else if (v >= 12'd60) ten = 4'd6;
            else if (v >= 12'd50) ten = 4'd5;
            else if (v >= 12'd40) ten = 4'd4;
            else if (v >= 12'd30) ten = 4'd3;
            else if (v >= 12'd20) ten = 4'd2;
            else if (v >= 12'd10) ten = 4'd1;
            else ten = 4'd0;
        end
    endfunction

    function [11:0] cut100;
        input [11:0] v;
        input [3:0] d;
        begin
            if (d == 4'd9) cut100 = v - 12'd900;
            else if (d == 4'd8) cut100 = v - 12'd800;
            else if (d == 4'd7) cut100 = v - 12'd700;
            else if (d == 4'd6) cut100 = v - 12'd600;
            else if (d == 4'd5) cut100 = v - 12'd500;
            else if (d == 4'd4) cut100 = v - 12'd400;
            else if (d == 4'd3) cut100 = v - 12'd300;
            else if (d == 4'd2) cut100 = v - 12'd200;
            else if (d == 4'd1) cut100 = v - 12'd100;
            else cut100 = v;
        end
    endfunction

    function [11:0] cut10;
        input [11:0] v;
        input [3:0] d;
        begin
            if (d == 4'd9) cut10 = v - 12'd90;
            else if (d == 4'd8) cut10 = v - 12'd80;
            else if (d == 4'd7) cut10 = v - 12'd70;
            else if (d == 4'd6) cut10 = v - 12'd60;
            else if (d == 4'd5) cut10 = v - 12'd50;
            else if (d == 4'd4) cut10 = v - 12'd40;
            else if (d == 4'd3) cut10 = v - 12'd30;
            else if (d == 4'd2) cut10 = v - 12'd20;
            else if (d == 4'd1) cut10 = v - 12'd10;
            else cut10 = v;
        end
    endfunction

    wire signed [9:0] ra = rep_a;
    wire signed [9:0] rb = rep_b;
    wire [9:0] ra_u = ra[9] ? (~ra + 10'd1) : ra;
    wire [9:0] rb_u = rb[9] ? (~rb + 10'd1) : rb;
    wire [11:0] ra_w = {2'd0, ra_u};
    wire [11:0] rb_w = {2'd0, rb_u};
    wire [3:0] ra_hd = hun(ra_w);
    wire [11:0] ra_a = cut100(ra_w, ra_hd);
    wire [3:0] ra_td = ten(ra_a);
    wire [11:0] ra_b = cut10(ra_a, ra_td);
    wire [3:0] rb_hd = hun(rb_w);
    wire [11:0] rb_a = cut100(rb_w, rb_hd);
    wire [3:0] rb_td = ten(rb_a);
    wire [11:0] rb_b = cut10(rb_a, rb_td);
    wire [9:0] ra_h10 = {6'd0, ra_hd};
    wire [9:0] ra_te  = {6'd0, ra_td};
    wire [9:0] ra_on  = {6'd0, ra_b[3:0]};
    wire [9:0] rb_h10 = {6'd0, rb_hd};
    wire [9:0] rb_te  = {6'd0, rb_td};
    wire [9:0] rb_on  = {6'd0, rb_b[3:0]};

    // Four six-digit fields, one subtractor. 0..999999.
    // Field 0 Sensor1 (Y), 1 Sensor2 (X), 2 PotA (X), 3 PotB (Y).
    // Slot {field, place}.
    reg [3:0] dw [0:31];
    reg [3:0] dd [0:31];
    reg [19:0] rem = 0;
    reg [3:0]  accd = 0;
    reg [2:0]  place = 0;
    reg [1:0]  which = 0;
    reg        conv = 0;
    wire [19:0] dec =
        (place == 3'd0) ? 20'd100000 :
        (place == 3'd1) ? 20'd10000 :
        (place == 3'd2) ? 20'd1000 :
        (place == 3'd3) ? 20'd100 :
        (place == 3'd4) ? 20'd10 : 20'd1;
    wire [19:0] fld_v =
        (which == 2'd0) ? sensor2 :
        (which == 2'd1) ? pot_a :
        pot_b;

    integer di;
    initial begin
        for (di = 0; di < 32; di = di + 1) begin
            dw[di] = 4'd0;
            dd[di] = 4'd0;
        end
    end

    always @(posedge clk) begin
        if (!conv) begin
            rem   <= sensor1;
            accd  <= 4'd0;
            place <= 3'd0;
            which <= 2'd0;
            conv  <= 1'b1;
        end else if (rem >= dec) begin
            rem  <= rem - dec;
            accd <= accd + 4'd1;
        end else begin
            accd <= 4'd0;
            dw[{which, place}] <= accd;
            if (place == 3'd5) begin
                if (which == 2'd3) begin
                    for (di = 0; di < 32; di = di + 1)
                        dd[di] <= dw[di];
                    dd[29] <= accd;
                    conv <= 1'b0;
                end else begin
                    rem   <= fld_v;
                    which <= which + 2'd1;
                    place <= 3'd0;
                end
            end else
                place <= place + 3'd1;
        end
    end
    assign x_dig = {dd[0], dd[1], dd[2], dd[3], dd[4], dd[5]};
    assign y_dig = {dd[8], dd[9], dd[10], dd[11], dd[12], dd[13]};

    wire [2:0] stc =
        rst_q ? 3'd4 :
        pulsing ? 3'd6 :
        (mode_q == M_AUTO) ? 3'd1 :
        (mode_q == M_BRK)  ? 3'd2 : 3'd0;
    wire set_b =
        pulsing ? 1'b0 :
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
    end

    always @(posedge clk) begin
        got       <= 1'b0;
        x_zero_p  <= 1'b0;
        y_zero_p  <= 1'b0;
        x_final_p <= 1'b0;
        y_final_p <= 1'b0;
        rst_p     <= 1'b0;
        lock_p    <= 1'b0;
        both_d    <= x_arm && y_arm;
        if (x_arm && y_arm && !both_d)
            rst_q <= 1'b0;

        if (ust == 2'd0) begin
            if (!rx) begin
                ust  <= 2'd1;
                divc <= 16'd0;
            end
        end else if (ust == 2'd1) begin
            if (divc == DIV[15:0] / 16'd2) begin
                if (rx)
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
                sh   <= {rx, sh[7:1]};
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
                    mode_q <= M_AUTO; pwr_a_q <= 10'sd0; pwr_b_q <= 10'sd0; pms <= 8'd0;
                end
                "A", "a": begin
                    mode_q <= M_AUTO;
                    pms    <= 8'd0;
                    if (fa > PM16)
                        pwr_a_q <= PM10;
                    else if (fa < -PM16)
                        pwr_a_q <= -PM10;
                    else
                        pwr_a_q <= fa[9:0];
                    if (fb > PM16)
                        pwr_b_q <= PM10;
                    else if (fb < -PM16)
                        pwr_b_q <= -PM10;
                    else
                        pwr_b_q <= fb[9:0];
                end
                "I", "i": begin
                    inv_x_q <= (fa != 16'sd0);
                    inv_y_q <= (fb != 16'sd0);
                end
                "P", "p": begin
                    if (fb != 16'sd0) begin
                        p_y   <= (axc == "B") || (axc == "b") || (axc == "Y") ||
                                 (axc == "y") || (axc == "1") ||
                                 ((axc == 8'd0) && (fa == 16'sd1));
                        p_mag <= (fb > 16'sd0) ? PM10 : -PM10;
                        tk    <= 16'd0;
                        if (fc < 16'sd0)
                            pms <= 8'd20;
                        else if (fc > 16'sd7)
                            pms <= 8'd160;
                        else
                            pms <= (fc[2:0] + 3'd1) * 8'd20;
                        mode_q  <= M_AUTO;
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
                    vtmp = neg ? -$signed(acc) : $signed(acc);
                    if (fld == 2'd0)
                        fa <= vtmp;
                    else if (fld == 2'd1)
                        fb <= vtmp;
                    else begin
                        fc     <= vtmp;
                        have_c <= 1'b1;
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
                    acc     <= (acc * 16'd10) + (rxb[pi] - 8'd48);
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
                        vtmp = neg ? -$signed(acc) : $signed(acc);
                        if (fld == 2'd0)
                            fa <= vtmp;
                        else if (fld == 2'd1)
                            fb <= vtmp;
                        else begin
                            fc     <= vtmp;
                            have_c <= 1'b1;
                        end
                        fld <= fld + 2'd1;
                    end else if (saw_ax)
                        fld <= fld + 2'd1;
                    acc     <= 16'd0;
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
            acc     <= 16'd0;
            neg     <= 1'b0;
            fld     <= 2'd0;
            saw_num <= 1'b0;
            saw_ax  <= 1'b0;
            have_c  <= 1'b0;
            fa      <= 16'sd0;
            fb      <= 16'sd0;
            fc      <= 16'sd0;
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
                txb[0]  <= ra[9] ? "-" : "+";
                txb[1]  <= dig(ra_h10[3:0]);
                txb[2]  <= dig(ra_te[3:0]);
                txb[3]  <= dig(ra_on[3:0]);
                txb[4]  <= ",";
                txb[5]  <= rb[9] ? "-" : "+";
                txb[6]  <= dig(rb_h10[3:0]);
                txb[7]  <= dig(rb_te[3:0]);
                txb[8]  <= dig(rb_on[3:0]);
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
