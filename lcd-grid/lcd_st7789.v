// ST7789V3 240x135 SPI driver for the Sipeed Tang Nano 9K 1.14" panel.
// Init sequence and CASET/RASET offsets match the official Sipeed demo
// (X=40..279, Y=53..187, MADCTL=0x70, COLMOD=16-bit).
// After init, streams a 24x15 turbo-colored grid that washes with phase.

module lcd_st7789 (
    input  wire       clk,       // 27 MHz
    input  wire [3:0] phase,
    output wire       lcd_resetn,
    output wire       lcd_clk,
    output wire       lcd_cs,
    output wire       lcd_rs,
    output wire       lcd_data,
    output wire       running
);

    localparam [3:0] ST_RESET   = 4'd0;
    localparam [3:0] ST_PREPARE = 4'd1;
    localparam [3:0] ST_WAKE    = 4'd2;
    localparam [3:0] ST_SNOOZE  = 4'd3;
    localparam [3:0] ST_INIT    = 4'd4;
    localparam [3:0] ST_STREAM  = 4'd5;

    localparam [6:0] INIT_N     = 7'd70; // words 0..69

    // Real panel delays @ 27 MHz (Sipeed source accidentally used sim values).
    localparam [23:0] CNT_100MS = 24'd2_700_000;
    localparam [23:0] CNT_120MS = 24'd3_240_000;
    localparam [23:0] CNT_200MS = 24'd5_400_000;

    localparam [7:0] X_MAX = 8'd239;
    localparam [7:0] Y_MAX = 8'd134;
    localparam [3:0] CELL_W = 4'd10;
    localparam [3:0] CELL_H = 4'd9;

    reg [3:0]  state     = 4'd0;
    reg [6:0]  cmd_index = 7'd0;
    reg [23:0] clk_cnt   = 24'd0;
    reg [4:0]  bit_loop  = 5'd0;

    reg        lcd_cs_r    = 1'b1;
    reg        lcd_rs_r    = 1'b1;
    reg        lcd_reset_r = 1'b0;
    reg [7:0]  spi_data    = 8'hFF;

    // Raster: 24 x 15 cells of 10 x 9 px (exactly 240 x 135).
    reg [7:0] pix_x  = 8'd0;
    reg [7:0] pix_y  = 8'd0;
    reg [3:0] sub_x  = 4'd0;
    reg [3:0] sub_y  = 4'd0;
    reg [4:0] cell_x = 5'd0;
    reg [3:0] cell_y = 4'd0;

    assign lcd_resetn = lcd_reset_r;
    assign lcd_clk    = ~clk;
    assign lcd_cs     = lcd_cs_r;
    assign lcd_rs     = lcd_rs_r;
    assign lcd_data   = spi_data[7];
    assign running    = (state == ST_STREAM);

    // Sipeed init ROM: bit8=0 command, bit8=1 data.
    function [8:0] init_word;
        input [6:0] idx;
        begin
            case (idx)
                7'd0:  init_word = 9'h036;
                7'd1:  init_word = 9'h170; // MADCTL landscape MX+MY+MV
                7'd2:  init_word = 9'h03A;
                7'd3:  init_word = 9'h105; // COLMOD 16-bit
                7'd4:  init_word = 9'h0B2;
                7'd5:  init_word = 9'h10C;
                7'd6:  init_word = 9'h10C;
                7'd7:  init_word = 9'h100;
                7'd8:  init_word = 9'h133;
                7'd9:  init_word = 9'h133;
                7'd10: init_word = 9'h0B7;
                7'd11: init_word = 9'h135;
                7'd12: init_word = 9'h0BB;
                7'd13: init_word = 9'h119;
                7'd14: init_word = 9'h0C0;
                7'd15: init_word = 9'h12C;
                7'd16: init_word = 9'h0C2;
                7'd17: init_word = 9'h101;
                7'd18: init_word = 9'h0C3;
                7'd19: init_word = 9'h112;
                7'd20: init_word = 9'h0C4;
                7'd21: init_word = 9'h120;
                7'd22: init_word = 9'h0C6;
                7'd23: init_word = 9'h10F;
                7'd24: init_word = 9'h0D0;
                7'd25: init_word = 9'h1A4;
                7'd26: init_word = 9'h1A1;
                7'd27: init_word = 9'h0E0;
                7'd28: init_word = 9'h1D0;
                7'd29: init_word = 9'h104;
                7'd30: init_word = 9'h10D;
                7'd31: init_word = 9'h111;
                7'd32: init_word = 9'h113;
                7'd33: init_word = 9'h12B;
                7'd34: init_word = 9'h13F;
                7'd35: init_word = 9'h154;
                7'd36: init_word = 9'h14C;
                7'd37: init_word = 9'h118;
                7'd38: init_word = 9'h10D;
                7'd39: init_word = 9'h10B;
                7'd40: init_word = 9'h11F;
                7'd41: init_word = 9'h123;
                7'd42: init_word = 9'h0E1;
                7'd43: init_word = 9'h1D0;
                7'd44: init_word = 9'h104;
                7'd45: init_word = 9'h10C;
                7'd46: init_word = 9'h111;
                7'd47: init_word = 9'h113;
                7'd48: init_word = 9'h12C;
                7'd49: init_word = 9'h13F;
                7'd50: init_word = 9'h144;
                7'd51: init_word = 9'h151;
                7'd52: init_word = 9'h12F;
                7'd53: init_word = 9'h11F;
                7'd54: init_word = 9'h11F;
                7'd55: init_word = 9'h120;
                7'd56: init_word = 9'h123;
                7'd57: init_word = 9'h021; // INVON
                7'd58: init_word = 9'h029; // DISPON
                7'd59: init_word = 9'h02A; // CASET
                7'd60: init_word = 9'h100;
                7'd61: init_word = 9'h128; // xs = 40
                7'd62: init_word = 9'h101;
                7'd63: init_word = 9'h117; // xe = 279
                7'd64: init_word = 9'h02B; // RASET
                7'd65: init_word = 9'h100;
                7'd66: init_word = 9'h135; // ys = 53
                7'd67: init_word = 9'h100;
                7'd68: init_word = 9'h1BB; // ye = 187
                7'd69: init_word = 9'h02C; // RAMWR
                default: init_word = 9'h000;
            endcase
        end
    endfunction

    // Compact turbo-like LUT (dark purple-blue → cyan → green → yellow → red).
    function [15:0] turbo_rgb565;
        input [3:0] idx;
        begin
            case (idx)
                4'd0:  turbo_rgb565 = 16'h3087;
                4'd1:  turbo_rgb565 = 16'h39B1;
                4'd2:  turbo_rgb565 = 16'h42B8;
                4'd3:  turbo_rgb565 = 16'h43BC;
                4'd4:  turbo_rgb565 = 16'h2ABD;
                4'd5:  turbo_rgb565 = 16'h1BBA;
                4'd6:  turbo_rgb565 = 16'h1E95;
                4'd7:  turbo_rgb565 = 16'h3F4F;
                4'd8:  turbo_rgb565 = 16'h8FEA;
                4'd9:  turbo_rgb565 = 16'hCF46;
                4'd10: turbo_rgb565 = 16'hF6A8;
                4'd11: turbo_rgb565 = 16'hF4E0;
                4'd12: turbo_rgb565 = 16'hF361;
                4'd13: turbo_rgb565 = 16'hE282;
                4'd14: turbo_rgb565 = 16'hC1C2;
                4'd15: turbo_rgb565 = 16'hB0A0;
                default: turbo_rgb565 = 16'h0000;
            endcase
        end
    endfunction

    wire [5:0] lut_sum = {1'b0, cell_x} + {2'b00, cell_y} + {2'b00, phase};
    wire       is_grid = (sub_x == 4'd0) || (sub_y == 4'd0);
    wire [15:0] pixel  = is_grid ? 16'h0000 : turbo_rgb565(lut_sum[3:0]);
    wire [8:0]  init_w = init_word(cmd_index);

    always @(posedge clk) begin
        case (state)
            ST_RESET: begin
                lcd_reset_r <= 1'b0;
                lcd_cs_r    <= 1'b1;
                lcd_rs_r    <= 1'b1;
                if (clk_cnt == CNT_100MS) begin
                    clk_cnt     <= 24'd0;
                    lcd_reset_r <= 1'b1;
                    state       <= ST_PREPARE;
                end else begin
                    clk_cnt <= clk_cnt + 24'd1;
                end
            end

            ST_PREPARE: begin
                lcd_reset_r <= 1'b1;
                if (clk_cnt == CNT_200MS) begin
                    clk_cnt  <= 24'd0;
                    bit_loop <= 5'd0;
                    state    <= ST_WAKE;
                end else begin
                    clk_cnt <= clk_cnt + 24'd1;
                end
            end

            ST_WAKE: begin
                // Sleep-out 0x11, one SPI byte.
                if (bit_loop == 5'd0) begin
                    lcd_cs_r  <= 1'b0;
                    lcd_rs_r  <= 1'b0;
                    spi_data  <= 8'h11;
                    bit_loop  <= 5'd1;
                end else if (bit_loop == 5'd8) begin
                    lcd_cs_r  <= 1'b1;
                    lcd_rs_r  <= 1'b1;
                    bit_loop  <= 5'd0;
                    clk_cnt   <= 24'd0;
                    state     <= ST_SNOOZE;
                end else begin
                    spi_data <= {spi_data[6:0], 1'b1};
                    bit_loop <= bit_loop + 5'd1;
                end
            end

            ST_SNOOZE: begin
                if (clk_cnt == CNT_120MS) begin
                    clk_cnt   <= 24'd0;
                    cmd_index <= 7'd0;
                    bit_loop  <= 5'd0;
                    state     <= ST_INIT;
                end else begin
                    clk_cnt <= clk_cnt + 24'd1;
                end
            end

            ST_INIT: begin
                if (cmd_index == INIT_N) begin
                    bit_loop <= 5'd0;
                    pix_x    <= 8'd0;
                    pix_y    <= 8'd0;
                    sub_x    <= 4'd0;
                    sub_y    <= 4'd0;
                    cell_x   <= 5'd0;
                    cell_y   <= 4'd0;
                    state    <= ST_STREAM;
                end else if (bit_loop == 5'd0) begin
                    lcd_cs_r <= 1'b0;
                    lcd_rs_r <= init_w[8];
                    spi_data <= init_w[7:0];
                    bit_loop <= 5'd1;
                end else if (bit_loop == 5'd8) begin
                    lcd_cs_r   <= 1'b1;
                    lcd_rs_r   <= 1'b1;
                    bit_loop   <= 5'd0;
                    cmd_index  <= cmd_index + 7'd1;
                end else begin
                    spi_data <= {spi_data[6:0], 1'b1};
                    bit_loop <= bit_loop + 5'd1;
                end
            end

            ST_STREAM: begin
                // 16-bit pixel, CS high for one cycle between pixels (Sipeed style).
                if (bit_loop == 5'd0) begin
                    lcd_cs_r <= 1'b0;
                    lcd_rs_r <= 1'b1;
                    spi_data <= pixel[15:8];
                    bit_loop <= 5'd1;
                end else if (bit_loop == 5'd8) begin
                    spi_data <= pixel[7:0];
                    bit_loop <= 5'd9;
                end else if (bit_loop == 5'd16) begin
                    lcd_cs_r <= 1'b1;
                    lcd_rs_r <= 1'b1;
                    bit_loop <= 5'd0;
                    if (pix_x == X_MAX) begin
                        pix_x  <= 8'd0;
                        sub_x  <= 4'd0;
                        cell_x <= 5'd0;
                        if (pix_y == Y_MAX) begin
                            pix_y  <= 8'd0;
                            sub_y  <= 4'd0;
                            cell_y <= 4'd0;
                        end else begin
                            pix_y <= pix_y + 8'd1;
                            if (sub_y == (CELL_H - 4'd1)) begin
                                sub_y  <= 4'd0;
                                cell_y <= cell_y + 4'd1;
                            end else begin
                                sub_y <= sub_y + 4'd1;
                            end
                        end
                    end else begin
                        pix_x <= pix_x + 8'd1;
                        if (sub_x == (CELL_W - 4'd1)) begin
                            sub_x  <= 4'd0;
                            cell_x <= cell_x + 5'd1;
                        end else begin
                            sub_x <= sub_x + 4'd1;
                        end
                    end
                end else begin
                    spi_data <= {spi_data[6:0], 1'b1};
                    bit_loop <= bit_loop + 5'd1;
                end
            end

            default: begin
                state   <= ST_RESET;
                clk_cnt <= 24'd0;
            end
        endcase
    end

endmodule
