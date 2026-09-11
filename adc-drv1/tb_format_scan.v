// Measured checks for format_scan. mV = |raw|*625/4096 (trunc toward 0).
// Run: iverilog -o tb_fmt.vvp format_scan.v tb_format_scan.v && vvp tb_fmt.vvp
`timescale 1ns/1ps
module tb_format_scan;
    reg         clk = 1'b0;
    reg         start = 1'b0;
    reg  [15:0] ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7;
    wire        idle;
    wire [16:0] p0, p1, p2, p3, p4, p5, p6, p7;
    wire [15:0] r0, r1, r2, r3, r4, r5, r6, r7;
    integer     i;
    integer     fail;
    integer     cyc;

    format_scan uut (
        .clk(clk), .start(start),
        .ch0(ch0), .ch1(ch1), .ch2(ch2), .ch3(ch3),
        .ch4(ch4), .ch5(ch5), .ch6(ch6), .ch7(ch7),
        .idle(idle),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3),
        .p4(p4), .p5(p5), .p6(p6), .p7(p7),
        .r0(r0), .r1(r1), .r2(r2), .r3(r3),
        .r4(r4), .r5(r5), .r6(r6), .r7(r7)
    );

    always #5 clk = ~clk;

    task expect_p;
        input [16:0] got;
        input        exp_neg;
        input [3:0]  exp_ip, exp_d1, exp_d2, exp_d3;
        input [8*16-1:0] tag;
        begin
            if (got[16] !== exp_neg || got[15:12] !== exp_ip ||
                got[11:8] !== exp_d1 || got[7:4] !== exp_d2 ||
                got[3:0] !== exp_d3) begin
                $display("FAIL %s got=%b.%0d.%0d%0d%0d exp=%b.%0d.%0d%0d%0d",
                    tag, got[16], got[15:12], got[11:8], got[7:4], got[3:0],
                    exp_neg, exp_ip, exp_d1, exp_d2, exp_d3);
                fail = fail + 1;
            end else
                $display("PASS %s", tag);
        end
    endtask

    initial begin
        fail = 0;
        ch0 = 16'd0;
        ch1 = 16'd32767;
        ch2 = 16'h8000;
        ch3 = 16'd6554;
        ch4 = 16'd4096;
        ch5 = -16'sd6554;
        ch6 = 16'd1;
        ch7 = 16'd0;
        repeat (4) @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;
        @(posedge clk);
        cyc = 0;
        while (idle && cyc < 10) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        if (idle) begin
            $display("FAIL never left idle");
            fail = fail + 1;
        end
        cyc = 0;
        while (!idle && cyc < 4000) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        $display("format_scan cycles=%0d idle=%b", cyc, idle);
        if (!idle) begin
            $display("FAIL timeout still busy");
            fail = fail + 1;
        end
        expect_p(p0, 1'b0, 4'd0, 4'd0, 4'd0, 4'd0, "ch0 raw0");
        expect_p(p1, 1'b0, 4'd4, 4'd9, 4'd9, 4'd9, "ch1 FS+");
        expect_p(p2, 1'b1, 4'd5, 4'd0, 4'd0, 4'd0, "ch2 FS-");
        expect_p(p3, 1'b0, 4'd1, 4'd0, 4'd0, 4'd0, "ch3 1.000V");
        expect_p(p4, 1'b0, 4'd0, 4'd6, 4'd2, 4'd5, "ch4 0.625V");
        expect_p(p5, 1'b1, 4'd1, 4'd0, 4'd0, 4'd0, "ch5 -1.000V");
        expect_p(p6, 1'b0, 4'd0, 4'd0, 4'd0, 4'd0, "ch6 1LSB");
        expect_p(p7, 1'b0, 4'd0, 4'd0, 4'd0, 4'd0, "ch7 raw0");
        if (r0 !== 16'd0 || r1 !== 16'd32767 || r2 !== 16'h8000 ||
            r3 !== 16'd6554 || r5 !== -16'sd6554) begin
            $display("FAIL raw pass-through r0=%h r1=%h r2=%h r3=%h r5=%h",
                r0, r1, r2, r3, r5);
            fail = fail + 1;
        end else
            $display("PASS raw pass-through");
        if (fail == 0)
            $display("tb_format_scan: ALL PASS");
        else
            $display("tb_format_scan: %0d FAIL", fail);
        $finish;
    end
endmodule
