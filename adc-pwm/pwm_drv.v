// One DRV8871. Table 1 (SLVSCY9B): 00 coast/sleep, 10 fwd, 01 rev, 11 brake.
// PWM = drive vs brake (slow decay), not drive vs coast. TI §7.3.1.
// Commands latch on cnt==0. After 00, one full period static drive (tON ~50 us).
// Pulse high time is at least MIN clocks when 0 < duty < 100 % (800 ns datasheet).
module pwm_drv #(
    parameter integer PERIOD = 1350
) (
    input  wire        clk,
    input  wire        enable,
    input  wire        fwd,
    input  wire        rev,
    input  wire [10:0] cmp,
    input  wire [10:0] cnt,
    output reg         in1,
    output reg         in2
);
    reg         en_r  = 1'b0;
    reg         fwd_r = 1'b0;
    reg         rev_r = 1'b0;
    reg         wake  = 1'b0;
    reg  [10:0] cmp_r = 11'd0;

    wire        load  = (cnt == 11'd0);
    wire        drive = en_r && (fwd_r ^ rev_r) && (cmp_r != 11'd0);
    wire        full  = wake || (cmp_r >= PERIOD[10:0]);
    wire        on    = drive && (full || (cnt < cmp_r));

    initial begin
        in1 = 1'b0;
        in2 = 1'b0;
    end

    always @(posedge clk) begin
        if (load) begin
            wake  <= enable && (fwd ^ rev) && (cmp != 11'd0) && !drive;
            en_r  <= enable;
            fwd_r <= fwd && !rev;
            rev_r <= rev && !fwd;
            cmp_r <= cmp;
        end

        if (!drive) begin
            in1 <= 1'b0;
            in2 <= 1'b0;
        end else if (fwd_r) begin
            in1 <= 1'b1;
            in2 <= !on;
        end else begin
            in1 <= !on;
            in2 <= 1'b1;
        end
    end
endmodule
