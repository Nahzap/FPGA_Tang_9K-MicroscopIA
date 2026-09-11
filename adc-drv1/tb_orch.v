// orch: ADC without LCD; map+format together; snap_pwm while format busy.
// Run: iverilog -o tb_orch.vvp orch.v tb_orch.v && vvp tb_orch.vvp
`timescale 1ns/1ps
module tb_worker #(
    parameter integer LAT = 4
) (
    input  wire clk,
    input  wire go,
    output reg  idle,
    output reg  done
);
    reg [3:0] left = 4'd0;

    initial begin
        idle = 1'b1;
        done = 1'b0;
    end

    always @(posedge clk) begin
        done <= 1'b0;
        if (left != 4'd0) begin
            if (left == 4'd1) begin
                idle <= 1'b1;
                done <= 1'b1;
            end
            left <= left - 4'd1;
        end else if (go) begin
            idle <= 1'b0;
            left <= LAT[3:0];
        end
    end
endmodule

module tb_orch;
    reg  clk = 1'b0;
    reg  paused = 1'b0;
    wire adc_idle, adc_done, map_idle, fmt_idle;
    wire adc_go, map_go, fmt_go, snap_pwm, snap_lcd, pwm_en;
    integer fail, cyc, saw_par, pwm_before_fmt, first_adc;

    orch #(.GAP(8)) uut (
        .clk(clk), .paused(paused),
        .adc_idle(adc_idle), .adc_done(adc_done),
        .map_idle(map_idle), .fmt_idle(fmt_idle),
        .adc_go(adc_go), .map_go(map_go), .fmt_go(fmt_go),
        .snap_pwm(snap_pwm), .snap_lcd(snap_lcd), .pwm_en(pwm_en)
    );

    tb_worker #(.LAT(4))  u_adc (.clk(clk), .go(adc_go), .idle(adc_idle), .done(adc_done));
    tb_worker #(.LAT(2))  u_map (.clk(clk), .go(map_go), .idle(map_idle), .done());
    tb_worker #(.LAT(10)) u_fmt (.clk(clk), .go(fmt_go), .idle(fmt_idle), .done());

    always #5 clk = ~clk;

    initial begin
        fail = 0;
        saw_par = 0;
        pwm_before_fmt = 0;
        first_adc = 0;
        repeat (6) @(posedge clk);

        for (cyc = 0; cyc < 80; cyc = cyc + 1) begin
            @(posedge clk);
            if (adc_go)
                first_adc = first_adc + 1;
            if (map_go && fmt_go)
                saw_par = 1;
            if (snap_pwm && !fmt_idle)
                pwm_before_fmt = 1;
        end

        if (first_adc == 0) begin
            $display("FAIL no ADC kick");
            fail = fail + 1;
        end else
            $display("PASS ADC without LCD");

        if (!saw_par) begin
            $display("FAIL map+format not together");
            fail = fail + 1;
        end else
            $display("PASS parallel kick");

        if (!pwm_before_fmt) begin
            $display("FAIL snap_pwm waited for format");
            fail = fail + 1;
        end else
            $display("PASS PWM before format");

        if (!pwm_en) begin
            $display("FAIL pwm_en");
            fail = fail + 1;
        end else
            $display("PASS pwm_en");

        paused = 1'b1;
        @(posedge clk);
        if (pwm_en) begin
            $display("FAIL pause");
            fail = fail + 1;
        end else
            $display("PASS pause");

        if (fail == 0)
            $display("ALL PASS");
        else
            $display("FAILURES %0d", fail);
        $finish;
    end
endmodule
