// DRV8871 Table 1: forward = IN1 high + IN2 PWM brake; reverse mirrored.
// First period after 00 is wake (static drive). Then duty applies.
// Run: iverilog -o tb_pwm.vvp pwm_timer.v pwm_drv.v tb_pwm_drv.v && vvp tb_pwm.vvp
`timescale 1ns/1ps
module tb_pwm_drv;
    reg         clk = 1'b0;
    reg         enable = 1'b0;
    reg         fwd = 1'b0;
    reg         rev = 1'b0;
    reg  [10:0] cmp = 11'd0;
    wire [10:0] cnt;
    wire        in1, in2;
    integer     i, h1, h2, both, fail;

    pwm_timer u_t (.clk(clk), .cnt(cnt));
    pwm_drv   u_d (
        .clk(clk), .enable(enable), .fwd(fwd), .rev(rev),
        .cmp(cmp), .cnt(cnt), .in1(in1), .in2(in2)
    );

    always #5 clk = ~clk;

    task count_period;
        begin
            h1 = 0;
            h2 = 0;
            both = 0;
            @(posedge clk);
            while (cnt != 11'd0) @(posedge clk);
            for (i = 0; i < 1350; i = i + 1) begin
                @(posedge clk);
                if (in1) h1 = h1 + 1;
                if (in2) h2 = h2 + 1;
                if (in1 && in2) both = both + 1;
            end
        end
    endtask

    initial begin
        fail = 0;
        repeat (8) @(posedge clk);

        enable = 1'b1;
        fwd = 1'b1;
        rev = 1'b0;
        cmp = 11'd675;
        count_period;
        if (h1 < 1340 || h2 > 10) begin
            $display("FAIL wake-fwd h1=%0d h2=%0d", h1, h2);
            fail = fail + 1;
        end else
            $display("PASS wake-fwd h1=%0d h2=%0d", h1, h2);

        count_period;
        if (h1 < 1340 || h2 < 665 || h2 > 685 || both < 665 || both > 685) begin
            $display("FAIL fwd50 h1=%0d h2=%0d both=%0d", h1, h2, both);
            fail = fail + 1;
        end else
            $display("PASS fwd50 h1=%0d h2=%0d brake=%0d", h1, h2, both);

        fwd = 1'b0;
        rev = 1'b1;
        cmp = 11'd270;
        count_period;
        count_period;
        if (h2 < 1340 || h1 < 1070 || h1 > 1090) begin
            $display("FAIL rev20 h1=%0d h2=%0d", h1, h2);
            fail = fail + 1;
        end else
            $display("PASS rev20 h1=%0d h2=%0d", h1, h2);

        enable = 1'b0;
        count_period;
        count_period;
        if (h1 != 0 || h2 != 0) begin
            $display("FAIL disable h1=%0d h2=%0d", h1, h2);
            fail = fail + 1;
        end else
            $display("PASS disable 00");

        if (fail == 0)
            $display("ALL PASS");
        else
            $display("FAILURES %0d", fail);
        $finish;
    end
endmodule
