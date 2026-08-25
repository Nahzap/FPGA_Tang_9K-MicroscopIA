// format_imu: 16384 LSB -> 1.000 g; 131 LSB gyro -> 1 dps (rounded).
`timescale 1ns/1ps
module tb_format_imu;
    reg         clk = 1'b0;
    reg         start = 1'b0;
    reg  [15:0] ax, ay, az, gx, gy, gz;
    wire        idle;
    wire [16:0] p0, p1, p2, p3, p4, p5;
    wire [15:0] r0, r1, r2, r3, r4, r5;
    integer     fail, cyc;

    format_imu uut (
        .clk(clk), .start(start),
        .ax(ax), .ay(ay), .az(az), .gx(gx), .gy(gy), .gz(gz),
        .idle(idle),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5),
        .r0(r0), .r1(r1), .r2(r2), .r3(r3), .r4(r4), .r5(r5)
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
        ax = 16'd16384;
        ay = 16'd0;
        az = -16'sd16384;
        gx = 16'd131;
        gy = 16'd0;
        gz = -16'sd131;
        repeat (4) @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;
        cyc = 0;
        while (idle && cyc < 20) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        cyc = 0;
        while (!idle && cyc < 8000) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        $display("format_imu cycles=%0d idle=%b", cyc, idle);
        if (!idle) begin
            $display("FAIL timeout");
            fail = fail + 1;
        end
        expect_p(p0, 1'b0, 4'd1, 4'd0, 4'd0, 4'd0, "ax 1.000g");
        expect_p(p1, 1'b0, 4'd0, 4'd0, 4'd0, 4'd0, "ay 0");
        expect_p(p2, 1'b1, 4'd1, 4'd0, 4'd0, 4'd0, "az -1.000g");
        expect_p(p3, 1'b0, 4'd0, 4'd0, 4'd0, 4'd1, "gx 1 dps");
        expect_p(p4, 1'b0, 4'd0, 4'd0, 4'd0, 4'd0, "gy 0");
        expect_p(p5, 1'b1, 4'd0, 4'd0, 4'd0, 4'd1, "gz -1 dps");
        if (r0 !== 16'd16384) begin
            $display("FAIL r0");
            fail = fail + 1;
        end
        if (fail == 0)
            $display("ALL PASS");
        else
            $display("%0d FAIL", fail);
        $finish;
    end
endmodule
