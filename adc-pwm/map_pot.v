// One pot (signed AD7606 raw, +/-5 V FS) -> one motor command.
// Center 1.65 V = 0 %. Toward 3.3 V = forward. Toward 0 V = reverse.
// Two registered stages, no subtract-loop. No PWM pins. No LCD.
module map_pot #(
    parameter integer PERIOD   = 1350,
    parameter integer VREF_MV  = 3300,
    parameter integer CENTER   = 1650,
    parameter integer DEAD_MV  = 66,
    parameter integer MIN_HIGH = 27
) (
    input  wire        clk,
    input  wire        start,
    input  wire [15:0] raw,
    output wire        idle,
    output reg         fwd,
    output reg         rev,
    output reg  [10:0] cmp,
    output reg  [6:0]  pct,
    output reg  [3:0]  hun,
    output reg  [3:0]  ten,
    output reg  [3:0]  one
);
    wire [15:0] mag  = raw[15] ? 16'd0 : raw;
    wire [31:0] acc  = ({16'd0, mag} << 9) + ({16'd0, mag} << 6) +
                       ({16'd0, mag} << 5) + ({16'd0, mag} << 4) +
                       {16'd0, mag};
    wire [15:0] mv_w = (acc[27:12] > 16'd9999) ? 16'd9999 : acc[27:12];
    wire [15:0] mv   = (mv_w > VREF_MV[15:0]) ? VREF_MV[15:0] : mv_w;
    wire        high = (mv >= CENTER[15:0]);
    wire [15:0] dlt  = high ? (mv - CENTER[15:0]) : (CENTER[15:0] - mv);
    wire        dead = (dlt < DEAD_MV[15:0]);

    reg        busy  = 1'b0;
    reg        phase = 1'b0;
    reg        dir_r = 1'b0;
    reg        dead_r = 1'b0;
    reg [15:0] dlt_r = 16'd0;

    wire [14:0] prod  = {1'b0, dlt_r[13:0]} + {dlt_r[11:0], 3'b000};
    wire [10:0] q     = prod / 15'd11;
    wire [10:0] q_cap = (q > PERIOD[10:0]) ? PERIOD[10:0] :
                        ((q > 11'd0) && (q < MIN_HIGH[10:0])) ? MIN_HIGH[10:0] : q;
    wire [17:0] pnum  = {7'd0, q_cap} * 18'd100;
    wire [6:0]  pct_w = pnum / 18'd1350;
    wire [6:0]  pct_c = (pct_w > 7'd100) ? 7'd100 : pct_w;
    wire [3:0]  hun_c = (pct_c >= 7'd100) ? 4'd1 : 4'd0;
    wire [6:0]  rem   = (pct_c >= 7'd100) ? 7'd0 : pct_c;
    wire [3:0]  ten_c = rem / 7'd10;
    wire [3:0]  one_c = rem % 7'd10;

    assign idle = !busy;

    initial begin
        fwd = 1'b0;
        rev = 1'b0;
        cmp = 11'd0;
        pct = 7'd0;
        hun = 4'd0;
        ten = 4'd0;
        one = 4'd0;
    end

    always @(posedge clk) begin
        if (start && !phase) begin
            dir_r  <= high;
            dead_r <= dead;
            dlt_r  <= dlt;
            busy   <= 1'b1;
            phase  <= 1'b1;
        end else if (phase) begin
            phase <= 1'b0;
            busy  <= 1'b0;
            if (dead_r) begin
                fwd <= 1'b0;
                rev <= 1'b0;
                cmp <= 11'd0;
                pct <= 7'd0;
                hun <= 4'd0;
                ten <= 4'd0;
                one <= 4'd0;
            end else begin
                fwd <= dir_r;
                rev <= ~dir_r;
                cmp <= q_cap;
                pct <= pct_c;
                hun <= hun_c;
                ten <= ten_c;
                one <= one_c;
            end
        end
    end
endmodule
