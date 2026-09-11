// One Hall A/B pair from AD7606 raw -> live ±100 % and stall locks.
// Display % uses stretching min/max. Power locks only after stall.
// Percent is 7 sequential compare-add bits (0..100), not a 23-bit / in one cycle.
module enc_pos #(
    parameter integer TH    = 10813,
    parameter integer STALL = 100
) (
    input  wire        clk,
    input  wire        sample,
    input  wire [15:0] raw_a,
    input  wire [15:0] raw_b,
    input  wire        cmd_fwd,
    input  wire        cmd_rev,
    input  wire        cmd_on,
    output reg         moved,
    output reg         lock_p,
    output reg         lock_n,
    output reg         pos_neg,
    output reg  [6:0]  pct,
    output reg  [3:0]  hun,
    output reg  [3:0]  ten,
    output reg  [3:0]  one
);
    localparam [15:0] TH16 = TH[15:0];
    localparam [7:0]  ST8  = STALL[7:0];

    wire a_bit = !raw_a[15] && (raw_a >= TH16);
    wire b_bit = !raw_b[15] && (raw_b >= TH16);

    reg        have  = 1'b0;
    reg        a_r   = 1'b0;
    reg        b_r   = 1'b0;
    reg        busy  = 1'b0;
    reg [2:0]  bit_i = 3'd0;
    reg [7:0]  stall = 8'd0;
    reg [15:0] pos   = 16'd0;
    reg [15:0] maxp  = 16'd0;
    reg [15:0] minp  = 16'd0;
    reg [15:0] mag_r = 16'd0;
    reg [15:0] den_r = 16'd0;
    reg [22:0] rhs   = 23'd0;
    reg [6:0]  acc   = 7'd0;

    wire [1:0] prev = {a_r, b_r};
    wire [1:0] nows = {a_bit, b_bit};
    wire [3:0] tr   = {prev, nows};

    wire plus  = have && (tr == 4'b0001 || tr == 4'b0111 ||
                           tr == 4'b1110 || tr == 4'b1000);
    wire minus = have && (tr == 4'b0010 || tr == 4'b1011 ||
                           tr == 4'b1101 || tr == 4'b0100);
    wire flank = plus || minus;

    wire [15:0] pos_plus  = pos + 16'd1;
    wire [15:0] pos_minus = pos - 16'd1;
    wire [15:0] pos_n =
        (plus  && pos != 16'h7fff) ? pos_plus  :
        (minus && pos != 16'h8001) ? pos_minus :
        pos;

    wire pos_gt_max = ($signed(pos_n) > $signed(maxp));
    wire pos_lt_min = ($signed(pos_n) < $signed(minp));
    wire [15:0] max_n = pos_gt_max ? pos_n : maxp;
    wire [15:0] min_n = pos_lt_min ? pos_n : minp;

    wire        cmd_p   = cmd_on && cmd_fwd && !cmd_rev;
    wire        cmd_m   = cmd_on && cmd_rev && !cmd_fwd;
    wire        driving = cmd_p || cmd_m;
    wire [7:0]  stall_n = (!driving || flank) ? 8'd0 :
                          (stall == ST8) ? ST8 : (stall + 8'd1);
    wire        fire    = driving && !flank && (stall_n == ST8);

    wire [15:0] mag_n = pos_n[15] ? (16'd0 - pos_n) : pos_n;
    wire [15:0] den_n = pos_n[15] ? (16'd0 - min_n) : max_n;

    wire [6:0] try_bit =
        (bit_i == 3'd0) ? 7'd64 :
        (bit_i == 3'd1) ? 7'd32 :
        (bit_i == 3'd2) ? 7'd16 :
        (bit_i == 3'd3) ? 7'd8  :
        (bit_i == 3'd4) ? 7'd4  :
        (bit_i == 3'd5) ? 7'd2  : 7'd1;
    wire [6:0]  try_v = acc | try_bit;
    wire [22:0] lhs   = {16'd0, try_v} * {7'd0, den_r};
    wire        take  = (den_r != 16'd0) && (lhs <= rhs);
    wire [6:0]  acc_n = take ? try_v : acc;
    wire [6:0]  pct_c = (acc_n > 7'd100) ? 7'd100 : acc_n;
    wire [3:0]  hun_c = (pct_c >= 7'd100) ? 4'd1 : 4'd0;
    wire [6:0]  rem   = (pct_c >= 7'd100) ? 7'd0 : pct_c;
    wire [3:0]  ten_c = rem / 7'd10;
    wire [3:0]  one_c = rem % 7'd10;

    initial begin
        moved   = 1'b0;
        lock_p  = 1'b0;
        lock_n  = 1'b0;
        pos_neg = 1'b0;
        pct     = 7'd0;
        hun     = 4'd0;
        ten     = 4'd0;
        one     = 4'd0;
    end

    always @(posedge clk) begin
        if (sample) begin
            a_r     <= a_bit;
            b_r     <= b_bit;
            have    <= 1'b1;
            pos     <= pos_n;
            maxp    <= max_n;
            minp    <= min_n;
            moved   <= flank;
            stall   <= stall_n;
            if (fire && cmd_p)
                lock_p <= 1'b1;
            if (fire && cmd_m)
                lock_n <= 1'b1;
            mag_r   <= mag_n;
            den_r   <= den_n;
            rhs     <= {7'd0, mag_n} * 23'd100;
            acc     <= 7'd0;
            bit_i   <= 3'd0;
            pos_neg <= pos_n[15];
            busy    <= 1'b1;
        end else if (busy) begin
            acc   <= acc_n;
            if (bit_i == 3'd6) begin
                busy <= 1'b0;
                pct  <= pct_c;
                hun  <= hun_c;
                ten  <= ten_c;
                one  <= one_c;
            end else
                bit_i <= bit_i + 3'd1;
        end
    end
endmodule
