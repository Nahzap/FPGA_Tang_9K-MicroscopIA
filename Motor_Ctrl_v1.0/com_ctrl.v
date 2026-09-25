// Lab 206 serial protocol, 115200 8N1 (BL702 USB-UART on this board).
// RX: M N B A,pa,pb F,rx,ry[,gate] I,ix,iy P,axis,sign,idx
// TX: header once, then PotenciaA,PotenciaB,Sensor1,Sensor2,Estado,Settled
module com_ctrl #(
    parameter integer DIV  = 234,
    parameter integer GAP  = 540000,
    parameter integer TICK = 27000
) (
    input  wire               clk,
    input  wire               rx,
    output reg                tx,
    input  wire signed [9:0]  rep_a,
    input  wire signed [9:0]  rep_b,
    input  wire [11:0]        sensor1,
    input  wire [11:0]        sensor2,
    input  wire               in_gate_a,
    input  wire               in_gate_b,
    output wire [1:0]         mode,
    output wire signed [9:0]  pwr_a,
    output wire signed [9:0]  pwr_b,
    output wire [11:0]        ref_x,
    output wire [11:0]        ref_y,
    output wire [5:0]         gate_e,
    output wire               inv_x,
    output wire               inv_y
);
    localparam [1:0] M_MAN  = 2'd0;
    localparam [1:0] M_AUTO = 2'd1;
    localparam [1:0] M_BRK  = 2'd2;
    localparam [1:0] M_FINE = 2'd3;
    localparam [415:0] HDR =
        "PotenciaA,PotenciaB,Sensor1,Sensor2,Estado,Settled\r\n";

    (* mem2reg *) reg [7:0] rxb [0:39];
    (* mem2reg *) reg [7:0] txb [0:63];

    reg [1:0]        mode_q   = M_MAN;
    reg signed [9:0] pwr_a_q  = 10'sd0;
    reg signed [9:0] pwr_b_q  = 10'sd0;
    reg [11:0]       ref_x_q  = 12'd0;
    reg [11:0]       ref_y_q  = 12'd0;
    reg [5:0]        gate_q   = 6'd2;
    reg              inv_x_q  = 1'b0;
    reg              inv_y_q  = 1'b0;
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
    assign ref_x = ref_x_q;
    assign ref_y = ref_y_q;
    assign gate_e = gate_q;
    assign inv_x = inv_x_q;
    assign inv_y = inv_y_q;

    function [3:0] thou;
        input [11:0] v;
        begin
            if (v >= 12'd4000) thou = 4'd4;
            else if (v >= 12'd3000) thou = 4'd3;
            else if (v >= 12'd2000) thou = 4'd2;
            else if (v >= 12'd1000) thou = 4'd1;
            else thou = 4'd0;
        end
    endfunction

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

    function [11:0] cut1000;
        input [11:0] v;
        input [3:0] d;
        begin
            if (d == 4'd4) cut1000 = v - 12'd4000;
            else if (d == 4'd3) cut1000 = v - 12'd3000;
            else if (d == 4'd2) cut1000 = v - 12'd2000;
            else if (d == 4'd1) cut1000 = v - 12'd1000;
            else cut1000 = v;
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

    wire [11:0] s1 = sensor1;
    wire [11:0] s2 = sensor2;
    wire [3:0] s1_thd = thou(s1);
    wire [11:0] s1_a = cut1000(s1, s1_thd);
    wire [3:0] s1_hud = hun(s1_a);
    wire [11:0] s1_b = cut100(s1_a, s1_hud);
    wire [3:0] s1_ted = ten(s1_b);
    wire [11:0] s1_c = cut10(s1_b, s1_ted);
    wire [3:0] s2_thd = thou(s2);
    wire [11:0] s2_a = cut1000(s2, s2_thd);
    wire [3:0] s2_hud = hun(s2_a);
    wire [11:0] s2_b = cut100(s2_a, s2_hud);
    wire [3:0] s2_ted = ten(s2_b);
    wire [11:0] s2_c = cut10(s2_b, s2_ted);
    wire [11:0] s1_q1000 = {8'd0, s1_thd};
    wire [11:0] s1_hu = {8'd0, s1_hud};
    wire [11:0] s1_te = {8'd0, s1_ted};
    wire [11:0] s1_on = {8'd0, s1_c[3:0]};
    wire [11:0] s2_q1000 = {8'd0, s2_thd};
    wire [11:0] s2_hu = {8'd0, s2_hud};
    wire [11:0] s2_te = {8'd0, s2_ted};
    wire [11:0] s2_on = {8'd0, s2_c[3:0]};

    wire both = in_gate_a & in_gate_b;
    wire [2:0] stc =
        pulsing ? 3'd6 :
        (mode_q == M_MAN)  ? 3'd0 :
        (mode_q == M_AUTO) ? 3'd1 :
        (mode_q == M_BRK)  ? 3'd2 :
        both ? 3'd5 : 3'd3;
    wire set_b =
        pulsing ? 1'b0 :
        (mode_q == M_BRK) ? 1'b1 :
        (mode_q == M_FINE) ? both :
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
            hdr_at = HDR[((51 - idx) * 8) +: 8];
        end
    endfunction

    initial tx = 1'b1;

    always @(posedge clk) begin
        got <= 1'b0;

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
            case (cmd)
                "M", "m": begin
                    mode_q <= M_MAN; pwr_a_q <= 10'sd0; pwr_b_q <= 10'sd0; pms <= 8'd0;
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
                    if (fa > 16'sd92)
                        pwr_a_q <= 10'sd92;
                    else if (fa < -16'sd92)
                        pwr_a_q <= -10'sd92;
                    else
                        pwr_a_q <= fa[9:0];
                    if (fb > 16'sd92)
                        pwr_b_q <= 10'sd92;
                    else if (fb < -16'sd92)
                        pwr_b_q <= -10'sd92;
                    else
                        pwr_b_q <= fb[9:0];
                end
                "F", "f": begin
                    mode_q <= M_FINE;
                    pms    <= 8'd0;
                    if (fa < 16'sd0)
                        ref_x_q <= 12'd0;
                    else if (fa > 16'sd4095)
                        ref_x_q <= 12'd4095;
                    else
                        ref_x_q <= fa[11:0];
                    if (fb < 16'sd0)
                        ref_y_q <= 12'd0;
                    else if (fb > 16'sd4095)
                        ref_y_q <= 12'd4095;
                    else
                        ref_y_q <= fb[11:0];
                    if (!have_c)
                        gate_q <= 6'd2;
                    else if (fc < 16'sd1)
                        gate_q <= 6'd1;
                    else if (fc > 16'sd40)
                        gate_q <= 6'd40;
                    else
                        gate_q <= fc[5:0];
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
                        p_mag <= (fb > 16'sd0) ? 10'sd92 : -10'sd92;
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
        end else if (got && (gdat == "\n") && (rlen != 6'd0)) begin
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
        end else if (got && (gdat != "\r") && (gdat != "\n") && (rlen < 6'd40)) begin
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
                for (hi = 0; hi < 52; hi = hi + 1)
                    txb[hi] <= hdr_at(hi);
                tlen <= 6'd52;
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
                txb[10] <= dig(s1_q1000[3:0]);
                txb[11] <= dig(s1_hu[3:0]);
                txb[12] <= dig(s1_te[3:0]);
                txb[13] <= dig(s1_on[3:0]);
                txb[14] <= ",";
                txb[15] <= dig(s2_q1000[3:0]);
                txb[16] <= dig(s2_hu[3:0]);
                txb[17] <= dig(s2_te[3:0]);
                txb[18] <= dig(s2_on[3:0]);
                txb[19] <= ",";
                case (stc)
                    3'd0: begin
                        txb[20] <= "M"; txb[21] <= "A"; txb[22] <= "N";
                        txb[23] <= "U"; txb[24] <= "A"; txb[25] <= "L";
                        txb[26] <= ","; txb[27] <= set_b ? "1" : "0";
                        txb[28] <= "\r"; txb[29] <= "\n";
                        tlen <= 6'd30;
                    end
                    3'd1: begin
                        txb[20] <= "A"; txb[21] <= "U"; txb[22] <= "T"; txb[23] <= "O";
                        txb[24] <= ","; txb[25] <= set_b ? "1" : "0";
                        txb[26] <= "\r"; txb[27] <= "\n";
                        tlen <= 6'd28;
                    end
                    3'd2: begin
                        txb[20] <= "B"; txb[21] <= "R"; txb[22] <= "A";
                        txb[23] <= "K"; txb[24] <= "E";
                        txb[25] <= ","; txb[26] <= "1";
                        txb[27] <= "\r"; txb[28] <= "\n";
                        tlen <= 6'd29;
                    end
                    3'd6: begin
                        txb[20] <= "P"; txb[21] <= "U"; txb[22] <= "L";
                        txb[23] <= "S"; txb[24] <= "E";
                        txb[25] <= ","; txb[26] <= "0";
                        txb[27] <= "\r"; txb[28] <= "\n";
                        tlen <= 6'd29;
                    end
                    3'd5: begin
                        txb[20] <= "S"; txb[21] <= "E"; txb[22] <= "T";
                        txb[23] <= "T"; txb[24] <= "L"; txb[25] <= "E"; txb[26] <= "D";
                        txb[27] <= ","; txb[28] <= "1";
                        txb[29] <= "\r"; txb[30] <= "\n";
                        tlen <= 6'd31;
                    end
                    default: begin
                        txb[20] <= "F"; txb[21] <= "I"; txb[22] <= "N"; txb[23] <= "E";
                        txb[24] <= ","; txb[25] <= "0";
                        txb[26] <= "\r"; txb[27] <= "\n";
                        tlen <= 6'd28;
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
