// LCD text for one DRV8871. V1..V8 + one motor line from V3.
module text_drv (
    input  wire [7:0]  pix_x,
    input  wire [7:0]  pix_y,
    input  wire [15:0] ch0,
    input  wire [15:0] ch1,
    input  wire [15:0] ch2,
    input  wire [15:0] ch3,
    input  wire [15:0] ch4,
    input  wire [15:0] ch5,
    input  wire [15:0] ch6,
    input  wire [15:0] ch7,
    input  wire [16:0] p0,
    input  wire [16:0] p1,
    input  wire [16:0] p2,
    input  wire [16:0] p3,
    input  wire [16:0] p4,
    input  wire [16:0] p5,
    input  wire [16:0] p6,
    input  wire [16:0] p7,
    input  wire [2:0]  status,
    input  wire [15:0] conv_cnt,
    input  wire        paused,
    input  wire        regs_valid,
    input  wire        busy_pin,
    input  wire        dout_pin,
    input  wire        fwd,
    input  wire        rev,
    input  wire [3:0]  hun,
    input  wire [3:0]  ten,
    input  wire [3:0]  one,
    output wire [15:0] pixel
);
    localparam [7:0]  MARGIN_X = 8'd4;
    localparam [15:0] COL_BG    = 16'h0000;
    localparam [15:0] COL_AMBER = 16'hFE40;
    localparam [15:0] COL_GREEN = 16'h07E0;
    localparam [15:0] COL_RED   = 16'hF800;
    localparam [15:0] COL_YEL   = 16'hFFE0;
    localparam [15:0] COL_CYAN  = 16'h07FF;

    function [63:0] glyph64;
        input [6:0] ch;
        begin
            case (ch)
                7'd32: glyph64 = 64'h0000000000000000;
                7'd37: glyph64 = 64'h0063660C18336300; // %
                7'd62: glyph64 = 64'h00060C18300C0600; // >
                7'd43: glyph64 = 64'h000C0C3F0C0C0000; // +
                7'd45: glyph64 = 64'h0000003F00000000; // -
                7'd46: glyph64 = 64'h00000000000C0C00; // .
                7'd47: glyph64 = 64'h6030180C06030100; // /
                7'd48: glyph64 = 64'h3E63737B6F673E00; // 0
                7'd49: glyph64 = 64'h0C0E0C0C0C0C3F00; // 1
                7'd50: glyph64 = 64'h1E33301C06333F00; // 2
                7'd51: glyph64 = 64'h1E33301C30331E00; // 3
                7'd52: glyph64 = 64'h383C36337F307800; // 4
                7'd53: glyph64 = 64'h3F031F3030331E00; // 5
                7'd54: glyph64 = 64'h1C06031F33331E00; // 6
                7'd55: glyph64 = 64'h3F3330180C0C0C00; // 7
                7'd56: glyph64 = 64'h1E33331E33331E00; // 8
                7'd57: glyph64 = 64'h1E33333E30180E00; // 9
                7'd58: glyph64 = 64'h000C0C00000C0C00; // :
                7'd65: glyph64 = 64'h0C1E33333F333300; // A
                7'd66: glyph64 = 64'h3F66663E66663F00; // B
                7'd67: glyph64 = 64'h3C66030303663C00; // C
                7'd68: glyph64 = 64'h1F36666666361F00; // D
                7'd69: glyph64 = 64'h7F46161E16467F00; // E
                7'd70: glyph64 = 64'h7F46161E16060F00; // F
                7'd73: glyph64 = 64'h1E0C0C0C0C0C1E00; // I
                7'd75: glyph64 = 64'h6766361E36666700; // K
                7'd76: glyph64 = 64'h0F06060646667F00; // L
                7'd77: glyph64 = 64'h63777F6B63636300; // M
                7'd79: glyph64 = 64'h1C36636363361C00; // O
                7'd80: glyph64 = 64'h3F66663E06060F00; // P
                7'd82: glyph64 = 64'h3F66663E36666700; // R
                7'd83: glyph64 = 64'h1E33070E38331E00; // S
                7'd84: glyph64 = 64'h3F2D0C0C0C0C1E00; // T
                7'd85: glyph64 = 64'h3333333333333F00; // U
                7'd86: glyph64 = 64'h33333333331E0C00; // V
                7'd87: glyph64 = 64'h6363636B7F776300; // W
                7'd88: glyph64 = 64'h6363361C1C366300; // X
                7'd89: glyph64 = 64'h3333331E0C0C1E00; // Y
                default: glyph64 = 64'h0;
            endcase
        end
    endfunction

    function [7:0] font_row;
        input [6:0] ch;
        input [2:0] row;
        reg [63:0] g;
        begin
            g = glyph64(ch);
            font_row = g >> (8 * (7 - row));
        end
    endfunction

    function [7:0] hexc;
        input [3:0] n;
        begin
            if (n < 4'd10)
                hexc = 8'd48 + {4'd0, n};
            else
                hexc = 8'd55 + {4'd0, n};
        end
    endfunction

    function [15:0] pick_ch;
        input [3:0] idx;
        begin
            case (idx)
                4'd0: pick_ch = ch0;
                4'd1: pick_ch = ch1;
                4'd2: pick_ch = ch2;
                4'd3: pick_ch = ch3;
                4'd4: pick_ch = ch4;
                4'd5: pick_ch = ch5;
                4'd6: pick_ch = ch6;
                default: pick_ch = ch7;
            endcase
        end
    endfunction

    function [16:0] pick_p;
        input [3:0] idx;
        begin
            case (idx)
                4'd0: pick_p = p0;
                4'd1: pick_p = p1;
                4'd2: pick_p = p2;
                4'd3: pick_p = p3;
                4'd4: pick_p = p4;
                4'd5: pick_p = p5;
                4'd6: pick_p = p6;
                default: pick_p = p7;
            endcase
        end
    endfunction

    wire [4:0] line_i    = pix_y[7:3];
    wire [2:0] glyph_row = pix_y[2:0];
    wire       in_margin = (pix_x < MARGIN_X);
    wire [7:0] rel_x     = pix_x - MARGIN_X;
    wire [4:0] col_i     = rel_x[7:3];
    wire [2:0] glyph_bit = rel_x[2:0];
    wire       col_ok    = !in_margin && (col_i < 5'd22) && (line_i <= 5'd12);

    wire [3:0]  ch_sel = line_i[3:0] - 4'd1;
    wire [15:0] raw    = pick_ch(ch_sel);
    wire [16:0] pk     = pick_p(ch_sel);
    wire        neg    = pk[16];
    wire [3:0]  ip     = pk[15:12];
    wire [3:0]  d1     = pk[11:8];
    wire [3:0]  d2     = pk[7:4];
    wire [3:0]  d3     = pk[3:0];

    wire       ax_fwd = fwd;
    wire       ax_rev = rev;

    reg [7:0] ch;
    always @(*) begin
        ch = 8'd32;
        if (line_i == 5'd0) begin
            case (col_i)
                5'd0:  ch = "A";
                5'd1:  ch = "D";
                5'd2:  ch = "C";
                5'd3:  ch = " ";
                5'd4:  ch = "D";
                5'd5:  ch = "R";
                5'd6:  ch = "V";
                5'd7:  ch = "8";
                5'd8:  ch = "8";
                5'd9:  ch = "7";
                5'd10: ch = "1";
                default: ch = " ";
            endcase
        end else if (line_i >= 5'd1 && line_i <= 5'd8) begin
            case (col_i)
                5'd0:  ch = "V";
                5'd1:  ch = 8'd48 + {4'd0, line_i[3:0]};
                5'd2:  ch = ":";
                5'd3:  ch = hexc(raw[15:12]);
                5'd4:  ch = hexc(raw[11:8]);
                5'd5:  ch = hexc(raw[7:4]);
                5'd6:  ch = hexc(raw[3:0]);
                5'd7:  ch = " ";
                5'd8:  ch = neg ? "-" : "+";
                5'd9:  ch = 8'd48 + {4'd0, ip};
                5'd10: ch = ".";
                5'd11: ch = 8'd48 + {4'd0, d1};
                5'd12: ch = 8'd48 + {4'd0, d2};
                5'd13: ch = 8'd48 + {4'd0, d3};
                5'd14: ch = "V";
                default: ch = " ";
            endcase
        end else if (line_i == 5'd9) begin
            if (paused) begin
                case (col_i)
                    5'd0: ch = "P";
                    5'd1: ch = "A";
                    5'd2: ch = "U";
                    5'd3: ch = "S";
                    5'd4: ch = "A";
                    default: ch = " ";
                endcase
            end else if (!regs_valid) begin
                case (col_i)
                    5'd0: ch = "W";
                    5'd1: ch = "A";
                    5'd2: ch = "I";
                    5'd3: ch = "T";
                    default: ch = " ";
                endcase
            end else begin
                case (status)
                    3'd2: case (col_i)
                        5'd0: ch = "B";
                        5'd1: ch = "U";
                        5'd2: ch = "S";
                        5'd3: ch = "Y";
                        default: ch = " ";
                    endcase
                    3'd5: case (col_i)
                        5'd0: ch = "B";
                        5'd1: ch = "H";
                        5'd2: ch = "I";
                        default: ch = " ";
                    endcase
                    3'd4: case (col_i)
                        5'd0: ch = "B";
                        5'd1: ch = "L";
                        5'd2: ch = "O";
                        default: ch = " ";
                    endcase
                    3'd0: case (col_i)
                        5'd0: ch = "R";
                        5'd1: ch = "S";
                        5'd2: ch = "T";
                        default: ch = " ";
                    endcase
                    default: case (col_i)
                        5'd0: ch = "O";
                        5'd1: ch = "K";
                        default: ch = " ";
                    endcase
                endcase
                if (col_i == 5'd4) ch = hexc(conv_cnt[15:12]);
                if (col_i == 5'd5) ch = hexc(conv_cnt[11:8]);
                if (col_i == 5'd6) ch = hexc(conv_cnt[7:4]);
                if (col_i == 5'd7) ch = hexc(conv_cnt[3:0]);
            end
            if (col_i == 5'd9)  ch = "B";
            if (col_i == 5'd10) ch = busy_pin ? "1" : "0";
            if (col_i == 5'd12) ch = "D";
            if (col_i == 5'd13) ch = dout_pin ? "1" : "0";
        end else if (line_i == 5'd10) begin
            case (col_i)
                5'd0: ch = "M";
                5'd1: ch = ":";
                5'd2: ch = ax_fwd ? "F" : (ax_rev ? "R" : " ");
                5'd3: ch = " ";
                5'd4: ch = 8'd48 + {4'd0, hun};
                5'd5: ch = 8'd48 + {4'd0, ten};
                5'd6: ch = 8'd48 + {4'd0, one};
                5'd7: ch = "%";
                default: ch = " ";
            endcase
        end else if (line_i == 5'd11) begin
            case (col_i)
                5'd0:  ch = "V";
                5'd1:  ch = "3";
                5'd2:  ch = ">";
                5'd3:  ch = "M";
                5'd4:  ch = "1";
                default: ch = " ";
            endcase
        end
    end

    wire [7:0] bits = font_row(ch[6:0], glyph_row);
    wire       on   = col_ok && bits[glyph_bit];

    wire [15:0] fg =
        (line_i == 5'd0) ? COL_YEL :
        (line_i == 5'd9 && (paused || status == 3'd4 || status == 3'd5)) ? COL_RED :
        (line_i == 5'd9) ? COL_GREEN :
        (line_i == 5'd3 || line_i == 5'd4 || line_i >= 5'd10) ? COL_CYAN :
        COL_AMBER;

    assign pixel = on ? fg : COL_BG;
endmodule
