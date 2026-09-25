`timescale 1ns/1ps
module tb_com_ctrl;
    localparam DIV = 4;
    reg clk = 0;
    reg rx = 1;
    wire tx;
    reg signed [9:0] rep_a = 0;
    reg signed [9:0] rep_b = 0;
    reg [11:0] sensor1 = 0;
    reg [11:0] sensor2 = 0;
    reg in_gate_a = 0;
    reg in_gate_b = 0;
    wire [1:0] mode;
    wire signed [9:0] pwr_a, pwr_b;
    wire [11:0] ref_x, ref_y;
    wire [5:0] gate_e;
    wire inv_x, inv_y;
    integer fails;
    integer ncap;
    reg [7:0] cap [0:79];
    integer k;

    com_ctrl #(.DIV(DIV), .GAP(200), .TICK(4)) dut (
        .clk(clk), .rx(rx), .tx(tx),
        .rep_a(rep_a), .rep_b(rep_b),
        .sensor1(sensor1), .sensor2(sensor2),
        .in_gate_a(in_gate_a), .in_gate_b(in_gate_b),
        .mode(mode), .pwr_a(pwr_a), .pwr_b(pwr_b),
        .ref_x(ref_x), .ref_y(ref_y), .gate_e(gate_e),
        .inv_x(inv_x), .inv_y(inv_y)
    );

    always #10 clk = ~clk;

    task sendb;
        input [7:0] ch;
        integer bi;
        begin
            @(negedge clk);
            rx = 1'b0;
            repeat (DIV) @(posedge clk);
            for (bi = 0; bi < 8; bi = bi + 1) begin
                @(negedge clk);
                rx = ch[bi];
                repeat (DIV) @(posedge clk);
            end
            @(negedge clk);
            rx = 1'b1;
            repeat (DIV) @(posedge clk);
        end
    endtask

    task sendline;
        input [8*24-1:0] s;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                sendb(s[(n - 1 - i) * 8 +: 8]);
            sendb("\n");
            repeat (80) @(posedge clk);
        end
    endtask

    task grab;
        integer bi;
        reg [7:0] ch;
        begin
            @(negedge tx);
            #(120);
            ch = 8'd0;
            for (bi = 0; bi < 8; bi = bi + 1) begin
                ch[bi] = tx;
                #(80);
            end
            if (ncap < 80) begin
                cap[ncap] = ch;
                ncap = ncap + 1;
            end
        end
    endtask

    initial begin
        fails = 0;
        ncap = 0;

        fork
            begin
                repeat (60) grab;
            end
            begin
                repeat (30) @(posedge clk);
                sendline("M", 1);
                if (mode != 2'd0) begin
                    $display("FAIL M mode=%0d", mode);
                    fails = fails + 1;
                end
                sendline("A,10,-3", 7);
                if (mode != 2'd1 || pwr_a != 10'sd10 || pwr_b != -10'sd3) begin
                    $display("FAIL A mode=%0d pa=%0d pb=%0d", mode, pwr_a, pwr_b);
                    fails = fails + 1;
                end
                sendline("B", 1);
                if (mode != 2'd2) begin
                    $display("FAIL B mode=%0d", mode);
                    fails = fails + 1;
                end
                sendline("F,100,200,4", 11);
                if (mode != 2'd3 || ref_x != 12'd100 || ref_y != 12'd200 || gate_e != 6'd4) begin
                    $display("FAIL F mode=%0d rx=%0d ry=%0d g=%0d", mode, ref_x, ref_y, gate_e);
                    fails = fails + 1;
                end
                sendline("I,1,0", 5);
                if (!inv_x || inv_y || mode != 2'd3) begin
                    $display("FAIL I ix=%b iy=%b mode=%0d", inv_x, inv_y, mode);
                    fails = fails + 1;
                end
                sendline("N", 1);
                if (mode != 2'd1 || pwr_a != 0 || pwr_b != 0) begin
                    $display("FAIL N");
                    fails = fails + 1;
                end
                sendline("P,X,1,0", 7);
                if (pwr_a != 10'sd92 || pwr_b != 0) begin
                    $display("FAIL P pa=%0d pb=%0d", pwr_a, pwr_b);
                    fails = fails + 1;
                end
            end
        join

        if (ncap < 10 || cap[0] != "P" || cap[1] != "o" || cap[2] != "t") begin
            $display("FAIL header n=%0d c0=%02h c1=%02h c2=%02h c3=%02h", ncap, cap[0], cap[1], cap[2], cap[3]);
            fails = fails + 1;
        end else begin
            $write("header: ");
            for (k = 0; k < 52 && k < ncap; k = k + 1)
                $write("%s", cap[k]);
            $write("\n");
        end

        if (ncap > 55 && (cap[52] != "+" || cap[53] != "0" || cap[54] != "0" || cap[55] != "0")) begin
            $display("FAIL digits %02h %02h %02h %02h", cap[52], cap[53], cap[54], cap[55]);
            fails = fails + 1;
        end

        if (fails == 0)
            $display("COM PASS");
        else
            $display("COM FAIL %0d", fails);
        $finish;
    end
endmodule
