// Sole owner of the ST7789 SPI pins. Init ROM + PHY copied from lcd-grid.
// Next state only when timed reset/sleep conditions or spi byte_done.
// Streaming starts after init_done; frame_done is last_pixel_of_frame.
module lcd_master (
    input  wire        clk,
    input  wire [15:0] pixel,
    output reg  [7:0]  pix_x,
    output reg  [7:0]  pix_y,
    output wire        init_done,
    output reg         frame_done,
    output wire        lcd_resetn,
    output wire        lcd_clk,
    output wire        lcd_cs,
    output wire        lcd_rs,
    output wire        lcd_data
);
    localparam [3:0] ST_RESET   = 4'd0;
    localparam [3:0] ST_PREPARE = 4'd1;
    localparam [3:0] ST_WAKE    = 4'd2;
    localparam [3:0] ST_SNOOZE  = 4'd3;
    localparam [3:0] ST_INIT    = 4'd4;
    localparam [3:0] ST_STREAM  = 4'd5;

    localparam [6:0] INIT_N     = 7'd70;

    localparam [23:0] CNT_100MS = 24'd2_700_000;
    localparam [23:0] CNT_120MS = 24'd3_240_000;
    localparam [23:0] CNT_200MS = 24'd5_400_000;

    localparam [7:0] X_MAX = 8'd239;
    localparam [7:0] Y_MAX = 8'd134;

    reg [3:0]  state     = 4'd0;
    reg [6:0]  cmd_index = 7'd0;
    reg [23:0] clk_cnt   = 24'd0;
    reg [4:0]  bit_loop  = 5'd0;

    reg        lcd_cs_r    = 1'b1;
    reg        lcd_rs_r    = 1'b1;
    reg        lcd_reset_r = 1'b0;
    reg [7:0]  spi_data    = 8'hFF;
    reg [15:0] pixel_hold  = 16'd0;

    assign lcd_resetn = lcd_reset_r;
    assign lcd_clk    = ~clk;
    assign lcd_cs     = lcd_cs_r;
    assign lcd_rs     = lcd_rs_r;
    assign lcd_data   = spi_data[7];
    assign init_done  = (state == ST_STREAM);

    wire spi_idle  = (bit_loop == 5'd0);
    wire byte_done = (bit_loop == 5'd8);
    wire pix_done  = (bit_loop == 5'd16);

    // Sipeed init ROM: bit8=0 command, bit8=1 data. Same as lcd-grid.
    function [8:0] init_word;
        input [6:0] idx;
        begin
            case (idx)
                7'd0:  init_word = 9'h036;
                7'd1:  init_word = 9'h170;
                7'd2:  init_word = 9'h03A;
                7'd3:  init_word = 9'h105;
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
                7'd57: init_word = 9'h021;
                7'd58: init_word = 9'h029;
                7'd59: init_word = 9'h02A;
                7'd60: init_word = 9'h100;
                7'd61: init_word = 9'h128;
                7'd62: init_word = 9'h101;
                7'd63: init_word = 9'h117;
                7'd64: init_word = 9'h02B;
                7'd65: init_word = 9'h100;
                7'd66: init_word = 9'h135;
                7'd67: init_word = 9'h100;
                7'd68: init_word = 9'h1BB;
                7'd69: init_word = 9'h02C;
                default: init_word = 9'h000;
            endcase
        end
    endfunction

    wire [8:0] init_w = init_word(cmd_index);

    always @(posedge clk) begin
        frame_done <= 1'b0;

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
                if (spi_idle) begin
                    lcd_cs_r  <= 1'b0;
                    lcd_rs_r  <= 1'b0;
                    spi_data  <= 8'h11;
                    bit_loop  <= 5'd1;
                end else if (byte_done) begin
                    lcd_cs_r <= 1'b1;
                    lcd_rs_r <= 1'b1;
                    bit_loop <= 5'd0;
                    clk_cnt  <= 24'd0;
                    state    <= ST_SNOOZE;
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
                    state    <= ST_STREAM;
                end else if (spi_idle) begin
                    lcd_cs_r <= 1'b0;
                    lcd_rs_r <= init_w[8];
                    spi_data <= init_w[7:0];
                    bit_loop <= 5'd1;
                end else if (byte_done) begin
                    lcd_cs_r  <= 1'b1;
                    lcd_rs_r  <= 1'b1;
                    bit_loop  <= 5'd0;
                    cmd_index <= cmd_index + 7'd1;
                end else begin
                    spi_data <= {spi_data[6:0], 1'b1};
                    bit_loop <= bit_loop + 5'd1;
                end
            end

            ST_STREAM: begin
                if (spi_idle) begin
                    lcd_cs_r    <= 1'b0;
                    lcd_rs_r    <= 1'b1;
                    pixel_hold  <= pixel;
                    spi_data    <= pixel[15:8];
                    bit_loop    <= 5'd1;
                end else if (byte_done) begin
                    spi_data <= pixel_hold[7:0];
                    bit_loop <= 5'd9;
                end else if (pix_done) begin
                    lcd_cs_r <= 1'b1;
                    lcd_rs_r <= 1'b1;
                    bit_loop <= 5'd0;
                    if (pix_x == X_MAX) begin
                        pix_x <= 8'd0;
                        if (pix_y == Y_MAX) begin
                            pix_y      <= 8'd0;
                            frame_done <= 1'b1;
                        end else begin
                            pix_y <= pix_y + 8'd1;
                        end
                    end else begin
                        pix_x <= pix_x + 8'd1;
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
