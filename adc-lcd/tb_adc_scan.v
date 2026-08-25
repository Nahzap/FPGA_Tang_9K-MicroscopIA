// MSB-first unpack of 8 channels (same order as adc_master ST_SAMPLE).
// Run: iverilog -o tb_adc.vvp tb_adc_scan.v && vvp tb_adc.vvp
`timescale 1ns/1ps
module tb_adc_scan;
    integer i, b, fail;
    reg [15:0] words [0:7];
    reg [15:0] acc;
    reg [15:0] ch [0:7];

    initial begin
        fail = 0;
        words[0] = 16'h0000;
        words[1] = 16'h1234;
        words[2] = 16'h8000;
        words[3] = 16'h7FFF;
        words[4] = 16'h0001;
        words[5] = 16'hAAAA;
        words[6] = 16'h5555;
        words[7] = 16'hF00F;
        for (i = 0; i < 8; i = i + 1) begin
            acc = 16'd0;
            for (b = 15; b >= 0; b = b - 1)
                acc = {acc[14:0], words[i][b]};
            ch[i] = acc;
        end
        for (i = 0; i < 8; i = i + 1) begin
            if (ch[i] !== words[i]) begin
                $display("FAIL ch%0d got=%h exp=%h", i, ch[i], words[i]);
                fail = fail + 1;
            end else
                $display("PASS ch%0d %h", i, ch[i]);
        end
        if (fail == 0)
            $display("tb_adc_scan: ALL PASS");
        else
            $display("tb_adc_scan: %0d FAIL", fail);
        $finish;
    end
endmodule
