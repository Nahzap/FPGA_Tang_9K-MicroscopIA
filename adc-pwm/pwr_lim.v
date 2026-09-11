// Scale a pot command near a locked end. Explore (no lock) passes through.
// Toward a locked stop: cmp * (100 - pct) / BAND. At 100 % that sense coasts.
// The opposite sense is untouched so the carriage can leave the stop.
module pwr_lim #(
    parameter integer BAND     = 20,
    parameter integer PERIOD   = 1350,
    parameter integer MIN_HIGH = 27
) (
    input  wire        fwd_i,
    input  wire        rev_i,
    input  wire [10:0] cmp_i,
    input  wire [6:0]  pct,
    input  wire        pos_neg,
    input  wire        lock_p,
    input  wire        lock_n,
    output wire        fwd_o,
    output wire        rev_o,
    output wire [10:0] cmp_o
);
    localparam [6:0] EDGE = 7'd100 - BAND[6:0];

    wire toward_p = lock_p && fwd_i && !rev_i && !pos_neg;
    wire toward_n = lock_n && rev_i && !fwd_i &&  pos_neg;
    wire apply    = (toward_p || toward_n) && (pct >= EDGE);
    wire at_end   = apply && (pct >= 7'd100);

    wire [6:0]  remain = (pct >= 7'd100) ? 7'd0 : (7'd100 - pct);
    wire [17:0] prod   = {7'd0, cmp_i} * {11'd0, remain};
    wire [10:0] raw    = prod / BAND;
    wire [10:0] scaled = (raw > PERIOD[10:0]) ? PERIOD[10:0] :
                         ((raw != 11'd0) && (raw < MIN_HIGH[10:0])) ? MIN_HIGH[10:0] :
                         raw;

    assign fwd_o = at_end ? 1'b0 : fwd_i;
    assign rev_o = at_end ? 1'b0 : rev_i;
    assign cmp_o = at_end ? 11'd0 : (apply ? scaled : cmp_i);
endmodule
