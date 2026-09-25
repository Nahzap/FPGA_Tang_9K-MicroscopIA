// Status line out the Tang Nano 9K USB serial (FPGA pin 17 -> BL702).
// 115200 8N1. Two lines every GAP clocks, X then Y.
// pot and cmp are hex. Speed digits are decimal um/s. mov/skip stick
// for the whole gap so a one-sample edge is still visible.
module dbg_uart #(
    parameter integer DIV = 234,
    parameter integer GAP = 5400000
) (
    input  wire        clk,
    input  wire        paused,
    input  wire        x_fwd,
    input  wire        x_rev,
    input  wire        y_fwd,
    input  wire        y_rev,
    input  wire [6:0]  x_pct,
    input  wire [6:0]  y_pct,
    input  wire [10:0] x_cmp,
    input  wire [10:0] y_cmp,
    input  wire        x_eff,
    input  wire        y_eff,
    input  wire        x_moved,
    input  wire        y_moved,
    input  wire        x_skip,
    input  wire        y_skip,
    input  wire        x_lp,
    input  wire        x_ln,
    input  wire        y_lp,
    input  wire        y_ln,
    input  wire [3:0]  x_sth,
    input  wire [3:0]  x_shu,
    input  wire [3:0]  x_ste,
    input  wire [3:0]  x_son,
    input  wire [3:0]  y_sth,
    input  wire [3:0]  y_shu,
    input  wire [3:0]  y_ste,
    input  wire [3:0]  y_son,
    input  wire [15:0] x_a,
    input  wire [15:0] x_b,
    input  wire [15:0] y_a,
    input  wire [15:0] y_b,
    output reg         tx
);
    reg [22:0] gap   = 23'd0;
    reg        phase = 1'b0;
    reg [6:0]  slot  = 7'd0;
    reg [3:0]  ph    = 4'd0;
    reg [15:0] bc    = 16'd0;
    reg [7:0]  sh    = 8'd0;

    reg        p_h   = 1'b0;
    reg        xf_h  = 1'b0;
    reg        xr_h  = 1'b0;
    reg        yf_h  = 1'b0;
    reg        yr_h  = 1'b0;
    reg [6:0]  xp_h  = 7'd0;
    reg [6:0]  yp_h  = 7'd0;
    reg [10:0] xc_h  = 11'd0;
    reg [10:0] yc_h  = 11'd0;
    reg        xe_h  = 1'b0;
    reg        ye_h  = 1'b0;
    reg        xm_h  = 1'b0;
    reg        ym_h  = 1'b0;
    reg        xs_h  = 1'b0;
    reg        ys_h  = 1'b0;
    reg        xlp_h = 1'b0;
    reg        xln_h = 1'b0;
    reg        ylp_h = 1'b0;
    reg        yln_h = 1'b0;
    reg [3:0]  x0_h  = 4'd0;
    reg [3:0]  x1_h  = 4'd0;
    reg [3:0]  x2_h  = 4'd0;
    reg [3:0]  x3_h  = 4'd0;
    reg [3:0]  y0_h  = 4'd0;
    reg [3:0]  y1_h  = 4'd0;
    reg [3:0]  y2_h  = 4'd0;
    reg [3:0]  y3_h  = 4'd0;
    reg [15:0] xa_h  = 16'd0;
    reg [15:0] xb_h  = 16'd0;
    reg [15:0] ya_h  = 16'd0;
    reg [15:0] yb_h  = 16'd0;
    reg        xm    = 1'b0;
    reg        ym    = 1'b0;
    reg        xs    = 1'b0;
    reg        ys    = 1'b0;

    wire        arm  = (phase == 1'b0) && (gap == GAP[22:0] - 23'd1);
    wire        ysel = slot >= 7'd36;
    wire [5:0]  col  = ysel ? (slot - 7'd36) : slot[5:0];
    wire        fwd  = ysel ? yf_h : xf_h;
    wire        rev  = ysel ? yr_h : xr_h;
    wire [6:0]  pct  = ysel ? yp_h : xp_h;
    wire [10:0] cmp  = ysel ? yc_h : xc_h;
    wire        eff  = ysel ? ye_h : xe_h;
    wire        mov  = ysel ? ym_h : xm_h;
    wire        skp  = ysel ? ys_h : xs_h;
    wire        lp   = ysel ? ylp_h : xlp_h;
    wire        ln   = ysel ? yln_h : xln_h;
    wire [15:0] rawa = ysel ? ya_h : xa_h;
    wire [15:0] rawb = ysel ? yb_h : xb_h;
    wire [3:0]  s0   = ysel ? y0_h : x0_h;
    wire [3:0]  s1   = ysel ? y1_h : x1_h;
    wire [3:0]  s2   = ysel ? y2_h : x2_h;
    wire [3:0]  s3   = ysel ? y3_h : x3_h;

    function [7:0] hexd;
        input [3:0] n;
        begin
            if (n < 4'd10)
                hexd = 8'd48 + {4'd0, n};
            else
                hexd = 8'd55 + {4'd0, n};
        end
    endfunction

    function [7:0] digit;
        input [3:0] n;
        begin
            digit = 8'd48 + {4'd0, n};
        end
    endfunction

    reg [7:0] cur;
    always @(*) begin
        cur = 8'd32;
        case (col)
            6'd0:  cur = ysel ? "Y" : "X";
            6'd1:  cur = ",";
            6'd2:  cur = p_h ? "1" : "0";
            6'd3:  cur = ",";
            6'd4:  cur = fwd ? "F" : (rev ? "R" : "-");
            6'd5:  cur = ",";
            6'd6:  cur = hexd(pct[6:4]);
            6'd7:  cur = hexd(pct[3:0]);
            6'd8:  cur = ",";
            6'd9:  cur = hexd(cmp[10:8]);
            6'd10: cur = hexd(cmp[7:4]);
            6'd11: cur = hexd(cmp[3:0]);
            6'd12: cur = ",";
            6'd13: cur = eff ? "1" : "0";
            6'd14: cur = ",";
            6'd15: cur = mov ? "1" : "0";
            6'd16: cur = ",";
            6'd17: cur = skp ? "1" : "0";
            6'd18: cur = ",";
            6'd19: cur = (lp && ln) ? "B" : (lp ? "P" : (ln ? "N" : "-"));
            6'd20: cur = ",";
            6'd21: cur = digit(s0);
            6'd22: cur = digit(s1);
            6'd23: cur = digit(s2);
            6'd24: cur = digit(s3);
            6'd25: cur = ",";
            6'd26: cur = hexd(rawa[15:12]);
            6'd27: cur = hexd(rawa[11:8]);
            6'd28: cur = hexd(rawa[7:4]);
            6'd29: cur = hexd(rawa[3:0]);
            6'd30: cur = ",";
            6'd31: cur = hexd(rawb[15:12]);
            6'd32: cur = hexd(rawb[11:8]);
            6'd33: cur = hexd(rawb[7:4]);
            6'd34: cur = hexd(rawb[3:0]);
            default: cur = 8'd10;
        endcase
    end

    initial tx = 1'b1;

    always @(posedge clk) begin
        if (x_moved) xm <= 1'b1;
        if (y_moved) ym <= 1'b1;
        if (x_skip)  xs <= 1'b1;
        if (y_skip)  ys <= 1'b1;

        if (phase == 1'b0) begin
            if (arm) begin
                p_h   <= paused;
                xf_h  <= x_fwd;  xr_h <= x_rev;
                yf_h  <= y_fwd;  yr_h <= y_rev;
                xp_h  <= x_pct;  yp_h <= y_pct;
                xc_h  <= x_cmp;  yc_h <= y_cmp;
                xe_h  <= x_eff;  ye_h <= y_eff;
                xm_h  <= xm | x_moved;
                ym_h  <= ym | y_moved;
                xs_h  <= xs | x_skip;
                ys_h  <= ys | y_skip;
                xm <= 1'b0; ym <= 1'b0; xs <= 1'b0; ys <= 1'b0;
                xlp_h <= x_lp; xln_h <= x_ln;
                ylp_h <= y_lp; yln_h <= y_ln;
                x0_h <= x_sth; x1_h <= x_shu; x2_h <= x_ste; x3_h <= x_son;
                y0_h <= y_sth; y1_h <= y_shu; y2_h <= y_ste; y3_h <= y_son;
                xa_h <= x_a; xb_h <= x_b; ya_h <= y_a; yb_h <= y_b;
                phase <= 1'b1;
                slot  <= 7'd0;
                gap   <= 23'd0;
            end else
                gap <= gap + 23'd1;
        end

        if (ph == 4'd0) begin
            tx <= 1'b1;
            if (phase == 1'b1) begin
                sh <= cur;
                ph <= 4'd1;
                bc <= 16'd0;
                tx <= 1'b0;
            end
        end else if (bc != DIV[15:0] - 16'd1) begin
            bc <= bc + 16'd1;
        end else begin
            bc <= 16'd0;
            if (ph == 4'd1) begin
                tx <= sh[0];
                sh <= {1'b1, sh[7:1]};
                ph <= 4'd2;
            end else if (ph < 4'd9) begin
                tx <= sh[0];
                sh <= {1'b1, sh[7:1]};
                ph <= ph + 4'd1;
            end else if (ph == 4'd9) begin
                tx <= 1'b1;
                ph <= 4'd10;
            end else begin
                ph <= 4'd0;
                if (slot == 7'd71)
                    phase <= 1'b0;
                else
                    slot <= slot + 7'd1;
            end
        end
    end
endmodule
