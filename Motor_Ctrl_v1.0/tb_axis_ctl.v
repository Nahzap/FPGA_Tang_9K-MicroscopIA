`timescale 1ns/1ps
module tb_axis_ctl;
    reg clk = 0;
    reg sample = 0;
    reg [1:0] mode = 0;
    reg signed [9:0] auto_pwr = 0;
    reg [11:0] ref_s = 0;
    reg [5:0] gate_e = 2;
    reg inv = 0;
    reg [15:0] pot = 16'd10813;
    reg [15:0] raw_a = 0;
    reg [15:0] raw_b = 0;
    wire fwd, rev, brake;
    wire [10:0] cmp;
    wire signed [9:0] rep;
    wire [11:0] sensor;
    wire moved, in_gate;
    wire [3:0] sth, shu, ste, son;
    integer i;
    integer fails;

    axis_ctl dut (
        .clk(clk), .sample(sample), .mode(mode), .auto_pwr(auto_pwr),
        .ref_s(ref_s), .gate_e(gate_e), .inv(inv), .pot(pot),
        .raw_a(raw_a), .raw_b(raw_b),
        .fwd(fwd), .rev(rev), .brake(brake), .cmp(cmp), .rep(rep),
        .sensor(sensor), .moved(moved), .in_gate(in_gate),
        .spd_th(sth), .spd_hu(shu), .spd_te(ste), .spd_on(son)
    );

    always #10 clk = ~clk;

    task step;
        begin
            @(negedge clk);
            sample = 1;
            @(posedge clk);
            #1;
            sample = 0;
        end
    endtask

    task win;
        begin
            for (i = 0; i < 64; i = i + 1)
                step;
        end
    endtask

    initial begin
        fails = 0;
        @(posedge clk);

        pot = 16'd10813;
        mode = 2'd0;
        step;
        if (cmp != 0 || fwd || rev) begin
            $display("FAIL center cmp=%0d", cmp);
            fails = fails + 1;
        end

        pot = 16'd21626;
        step;
        if (cmp != 11'd488 || !fwd || rev) begin
            $display("FAIL full cmp=%0d fwd=%b", cmp, fwd);
            fails = fails + 1;
        end

        pot = 16'd14270;
        step;
        if (cmp != 11'd476 || !fwd) begin
            $display("FAIL thresh cmp=%0d", cmp);
            fails = fails + 1;
        end

        pot = 16'd0;
        step;
        if (cmp != 11'd488 || !rev || fwd) begin
            $display("FAIL rev full cmp=%0d", cmp);
            fails = fails + 1;
        end

        mode = 2'd1;
        auto_pwr = 10'sd100;
        pot = 16'd10813;
        step;
        if (cmp != 11'd488 || !fwd) begin
            $display("FAIL auto100 cmp=%0d", cmp);
            fails = fails + 1;
        end

        auto_pwr = 10'sd0;
        step;
        if (cmp != 0 || fwd || rev) begin
            $display("FAIL auto0");
            fails = fails + 1;
        end

        mode = 2'd2;
        step;
        if (!brake || cmp != 0) begin
            $display("FAIL brake");
            fails = fails + 1;
        end

        mode = 2'd3;
        ref_s = 12'd4095;
        gate_e = 6'd2;
        raw_a = 0;
        raw_b = 0;
        win;
        if (cmp != 11'd488 || !fwd || rev) begin
            $display("FAIL fine big cmp=%0d fwd=%b rev=%b", cmp, fwd, rev);
            fails = fails + 1;
        end

        ref_s = 12'd0;
        win;
        if (cmp != 0 || !in_gate) begin
            $display("FAIL fine match cmp=%0d gate=%b sens=%0d", cmp, in_gate, sensor);
            fails = fails + 1;
        end

        mode = 2'd3;
        ref_s = 12'd4095;
        raw_a = 16'd0;
        raw_b = 16'd0;
        step;
        raw_a = 16'd20000;
        raw_b = 16'd20000;
        win;
        if (cmp != 0) begin
            $display("FAIL illegal cmp=%0d", cmp);
            fails = fails + 1;
        end

        mode = 2'd0;
        pot = 16'd10813;
        raw_a = 16'd0;
        raw_b = 16'd0;
        for (i = 0; i < 96; i = i + 1) begin
            case (i[1:0])
                2'd0: begin raw_a = 16'd0;     raw_b = 16'd20000; end
                2'd1: begin raw_a = 16'd20000; raw_b = 16'd20000; end
                2'd2: begin raw_a = 16'd20000; raw_b = 16'd0;     end
                default: begin raw_a = 16'd0;  raw_b = 16'd0;     end
            endcase
            step;
        end
        if (sensor == 0) begin
            $display("FAIL rate sensor=%0d", sensor);
            fails = fails + 1;
        end

        if (fails == 0)
            $display("AXIS PASS");
        else
            $display("AXIS FAIL %0d", fails);
        $finish;
    end
endmodule
