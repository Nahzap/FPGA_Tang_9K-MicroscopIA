// ROM of parameter lines + 8x8 font. Combinational pixel from (x,y,scroll_y,paused).
// Font: public-domain IBM VGA 8x8 (font8x8_basic); LSB of each row is the leftmost pixel.
module text_source (
    input  wire [7:0]  pix_x,
    input  wire [7:0]  pix_y,
    input  wire [7:0]  scroll_y,
    input  wire        paused,
    output wire [15:0] pixel
);
    localparam [7:0] HUD_H    = 8'd10;
    localparam [7:0] MARGIN_X = 8'd8;
    localparam [4:0] N_COLS   = 5'd29;
    localparam [4:0] N_LINES  = 5'd26;
    localparam [8:0] TOTAL_H  = 9'd208; // 26*8
    localparam [4:0] ESTADO_L = 5'd20;

    localparam [15:0] COL_BG     = 16'h0000;
    localparam [15:0] COL_AMBER  = 16'hFE40;
    localparam [15:0] COL_HUD_R  = 16'hFFE0; // RUN yellow
    localparam [15:0] COL_HUD_P  = 16'hF800; // PAUSA red
    localparam [15:0] COL_RULE   = 16'hA320;
    localparam [15:0] COL_HUD_BG = 16'h2100;

    function [63:0] glyph64;
        input [6:0] ch;
        begin
            case (ch)
                7'd32: glyph64 = 64'h0000000000000000; //  
                7'd33: glyph64 = 64'h183C3C1818001800; // !
                7'd34: glyph64 = 64'h3636000000000000; // "
                7'd35: glyph64 = 64'h36367F367F363600; // #
                7'd36: glyph64 = 64'h0C3E031E301F0C00; // $
                7'd37: glyph64 = 64'h006333180C666300; // %
                7'd38: glyph64 = 64'h1C361C6E3B336E00; // &
                7'd39: glyph64 = 64'h0606030000000000; // '
                7'd40: glyph64 = 64'h180C0606060C1800; // (
                7'd41: glyph64 = 64'h060C1818180C0600; // )
                7'd42: glyph64 = 64'h00663CFF3C660000; // *
                7'd43: glyph64 = 64'h000C0C3F0C0C0000; // +
                7'd44: glyph64 = 64'h00000000000C0C06; // ,
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
                7'd59: glyph64 = 64'h000C0C00000C0C06; // ;
                7'd60: glyph64 = 64'h180C0603060C1800; // <
                7'd61: glyph64 = 64'h00003F00003F0000; // =
                7'd62: glyph64 = 64'h060C1830180C0600; // >
                7'd63: glyph64 = 64'h1E3330180C000C00; // ?
                7'd64: glyph64 = 64'h3E637B7B7B031E00; // @
                7'd65: glyph64 = 64'h0C1E33333F333300; // A
                7'd66: glyph64 = 64'h3F66663E66663F00; // B
                7'd67: glyph64 = 64'h3C66030303663C00; // C
                7'd68: glyph64 = 64'h1F36666666361F00; // D
                7'd69: glyph64 = 64'h7F46161E16467F00; // E
                7'd70: glyph64 = 64'h7F46161E16060F00; // F
                7'd71: glyph64 = 64'h3C66030373667C00; // G
                7'd72: glyph64 = 64'h3333333F33333300; // H
                7'd73: glyph64 = 64'h1E0C0C0C0C0C1E00; // I
                7'd74: glyph64 = 64'h7830303033331E00; // J
                7'd75: glyph64 = 64'h6766361E36666700; // K
                7'd76: glyph64 = 64'h0F06060646667F00; // L
                7'd77: glyph64 = 64'h63777F7F6B636300; // M
                7'd78: glyph64 = 64'h63676F7B73636300; // N
                7'd79: glyph64 = 64'h1C36636363361C00; // O
                7'd80: glyph64 = 64'h3F66663E06060F00; // P
                7'd81: glyph64 = 64'h1E3333333B1E3800; // Q
                7'd82: glyph64 = 64'h3F66663E36666700; // R
                7'd83: glyph64 = 64'h1E33070E38331E00; // S
                7'd84: glyph64 = 64'h3F2D0C0C0C0C1E00; // T
                7'd85: glyph64 = 64'h3333333333333F00; // U
                7'd86: glyph64 = 64'h33333333331E0C00; // V
                7'd87: glyph64 = 64'h6363636B7F776300; // W
                7'd88: glyph64 = 64'h6363361C1C366300; // X
                7'd89: glyph64 = 64'h3333331E0C0C1E00; // Y
                7'd90: glyph64 = 64'h7F6331184C667F00; // Z
                7'd91: glyph64 = 64'h1E06060606061E00; // [
                7'd92: glyph64 = 64'h03060C1830604000; // backslash
                7'd93: glyph64 = 64'h1E18181818181E00; // ]
                7'd94: glyph64 = 64'h081C366300000000; // ^
                7'd95: glyph64 = 64'h00000000000000FF; // _
                7'd96: glyph64 = 64'h0C0C180000000000; // `
                7'd97: glyph64 = 64'h00001E303E336E00; // a
                7'd98: glyph64 = 64'h0706063E66663B00; // b
                7'd99: glyph64 = 64'h00001E3303331E00; // c
                7'd100: glyph64 = 64'h3830303E33336E00; // d
                7'd101: glyph64 = 64'h00001E333F031E00; // e
                7'd102: glyph64 = 64'h1C36060F06060F00; // f
                7'd103: glyph64 = 64'h00006E33333E301F; // g
                7'd104: glyph64 = 64'h0706366E66666700; // h
                7'd105: glyph64 = 64'h0C000E0C0C0C1E00; // i
                7'd106: glyph64 = 64'h300030303033331E; // j
                7'd107: glyph64 = 64'h070666361E366700; // k
                7'd108: glyph64 = 64'h0E0C0C0C0C0C1E00; // l
                7'd109: glyph64 = 64'h0000337F7F6B6300; // m
                7'd110: glyph64 = 64'h00001F3333333300; // n
                7'd111: glyph64 = 64'h00001E3333331E00; // o
                7'd112: glyph64 = 64'h00003B66663E060F; // p
                7'd113: glyph64 = 64'h00006E33333E3078; // q
                7'd114: glyph64 = 64'h00003B6E66060F00; // r
                7'd115: glyph64 = 64'h00003E031E301F00; // s
                7'd116: glyph64 = 64'h080C3E0C0C2C1800; // t
                7'd117: glyph64 = 64'h0000333333336E00; // u
                7'd118: glyph64 = 64'h00003333331E0C00; // v
                7'd119: glyph64 = 64'h0000636B7F7F3600; // w
                7'd120: glyph64 = 64'h000063361C366300; // x
                7'd121: glyph64 = 64'h00003333333E301F; // y
                7'd122: glyph64 = 64'h00003F190C263F00; // z
                7'd123: glyph64 = 64'h380C0C070C0C3800; // {
                7'd124: glyph64 = 64'h1818180018181800; // |
                7'd125: glyph64 = 64'h070C0C380C0C0700; // }
                7'd126: glyph64 = 64'h6E3B000000000000; // ~
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

    function [7:0] line_char;
        input [4:0] li;
        input [4:0] ci;
        input       paused_i;
        reg [231:0] s;
        reg [7:0]   ch;
        begin
            case (li)
                5'd0: s = "Placa: Sipeed Tang Nano 9K   ";
                5'd1: s = "FPGA: GW1NR-LV9QN88PC6/I5    ";
                5'd2: s = "Familia: GW1N(R)-9C          ";
                5'd3: s = "IDCODE: 0x100481B            ";
                5'd4: s = "Reloj: 27 MHz pin 52         ";
                5'd5: s = "Flash: persiste al apagar    ";
                5'd6: s = "LCD: ST7789 240x135 SPI      ";
                5'd7: s = "PSRAM: 64 Mbit               ";
                5'd8: s = "LEDs: 10 11 13 14 15 16      ";
                5'd9: s = "     activo bajo             ";
                5'd10: s = "Botones: pines 3 y 4         ";
                5'd11: s = "     activo bajo             ";
                5'd12: s = "Pulsa cualquiera:            ";
                5'd13: s = "     pausa / reanuda         ";
                5'd14: s = "JTAG: BL702 FT2232           ";
                5'd15: s = "     USB 0403:6010           ";
                5'd16: s = "Toolchain: Yosys             ";
                5'd17: s = "     nextpnr-himbaechel      ";
                5'd18: s = "     gowin_pack              ";
                5'd19: s = "                             ";
                5'd20: s = "Estado: RUN                  ";
                5'd21: s = "                             ";
                5'd22: s = "                             ";
                5'd23: s = "                             ";
                5'd24: s = "                             ";
                5'd25: s = "                             ";
                default: s = "                             ";
            endcase
            ch = s[8*(28-ci) +: 8];
            // Live RUN/PAUSA on the Estado line (cols 8..12).
            if (li == ESTADO_L && ci >= 5'd8 && ci <= 5'd12) begin
                if (paused_i) begin
                    case (ci)
                        5'd8:  ch = "P";
                        5'd9:  ch = "A";
                        5'd10: ch = "U";
                        5'd11: ch = "S";
                        5'd12: ch = "A";
                        default: ch = " ";
                    endcase
                end else begin
                    case (ci)
                        5'd8:  ch = "R";
                        5'd9:  ch = "U";
                        5'd10: ch = "N";
                        5'd11: ch = " ";
                        5'd12: ch = " ";
                        default: ch = " ";
                    endcase
                end
            end
            line_char = ch;
        end
    endfunction

    function [7:0] hud_char;
        input [2:0] ci;
        input       paused_i;
        begin
            if (paused_i) begin
                case (ci)
                    3'd0: hud_char = "P";
                    3'd1: hud_char = "A";
                    3'd2: hud_char = "U";
                    3'd3: hud_char = "S";
                    3'd4: hud_char = "A";
                    default: hud_char = " ";
                endcase
            end else begin
                case (ci)
                    3'd0: hud_char = "R";
                    3'd1: hud_char = "U";
                    3'd2: hud_char = "N";
                    default: hud_char = " ";
                endcase
            end
        end
    endfunction

    wire        in_hud    = (pix_y < HUD_H);
    wire        hud_rule  = (pix_y == 8'd9);
    wire        hud_text  = (pix_y >= 8'd1) && (pix_y <= 8'd8);
    wire [7:0]  content_y = pix_y - HUD_H;
    wire [8:0]  virt_y    = {1'b0, content_y} + {1'b0, scroll_y};
    wire [8:0]  wrap_y    = (virt_y >= TOTAL_H) ? (virt_y - TOTAL_H) : virt_y;
    wire [4:0]  line_i    = wrap_y[7:3];
    wire [2:0]  glyph_row = wrap_y[2:0];
    wire        in_margin = (pix_x < MARGIN_X);
    wire [7:0]  rel_x     = pix_x - MARGIN_X;
    wire [4:0]  col_i     = rel_x[7:3];
    wire [2:0]  glyph_bit = rel_x[2:0];
    wire        col_ok    = !in_margin && (col_i < N_COLS);

    wire [7:0]  body_ch   = line_char(line_i, col_i, paused);
    wire [7:0]  body_bits = font_row(body_ch[6:0], glyph_row);
    wire        body_on   = col_ok && body_bits[glyph_bit];

    wire [7:0]  hud_rel_x = pix_x - MARGIN_X;
    wire [2:0]  hud_col   = hud_rel_x[5:3];
    wire [2:0]  hud_bit   = hud_rel_x[2:0];
    wire [3:0]  hud_row4  = pix_y[3:0] - 4'd1;
    wire [2:0]  hud_row   = hud_row4[2:0];
    wire        hud_ok    = hud_text && (pix_x >= MARGIN_X) && (hud_rel_x < 8'd40);
    wire [7:0]  hch       = hud_char(hud_col, paused);
    wire [7:0]  hud_bits  = font_row(hch[6:0], hud_row);
    wire        hud_on    = hud_ok && hud_bits[hud_bit];

    wire [15:0] hud_fg    = paused ? COL_HUD_P : COL_HUD_R;

    assign pixel =
        in_hud ? (hud_rule ? COL_RULE :
                  (hud_on  ? hud_fg   : COL_HUD_BG)) :
        (body_on ? COL_AMBER : COL_BG);
endmodule
