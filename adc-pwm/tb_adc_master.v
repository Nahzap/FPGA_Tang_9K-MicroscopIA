// Cycle-accurate scan: 8 words, 2FF, SCLK idle-high (CPOL=1), sample on fall.
// Run: iverilog -o tb_m.vvp adc_master.v tb_adc_master.v && vvp tb_m.vvp
`timescale 1ns/1ps
module tb_adc_master;
    reg         clk = 1'b0;
    reg         start = 1'b0;
    reg         adc_busy = 1'b0;
    wire        adc_dout;
    wire        adc_convst, adc_reset, adc_cs, adc_sclk;
    wire        idle, regs_valid, sample_done;
    wire [2:0]  status;
    wire        busy_s, dout_s, probe_busy, probe_dout;
    wire [15:0] conv_cnt;
    wire [15:0] ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7;

    reg         sclk_d = 1'b0;
    reg         cs_d   = 1'b1;
    reg [127:0] shifter;
    integer     i, fail, cyc, busy_cnt;
    reg         saw_convst;

    localparam [15:0] W0 = 16'h0000;
    localparam [15:0] W1 = 16'h1234;
    localparam [15:0] W2 = 16'h8000;
    localparam [15:0] W3 = 16'h7FFF;
    localparam [15:0] W4 = 16'h0001;
    localparam [15:0] W5 = 16'hAAAA;
    localparam [15:0] W6 = 16'h5555;
    localparam [15:0] W7 = 16'hF00F;

    adc_master uut (
        .clk(clk), .start(start), .paused(1'b0),
        .adc_busy(adc_busy), .adc_dout(adc_dout),
        .adc_convst(adc_convst), .adc_reset(adc_reset),
        .adc_cs(adc_cs), .adc_sclk(adc_sclk),
        .idle(idle), .regs_valid(regs_valid), .sample_done(sample_done),
        .status(status), .busy_s(busy_s), .dout_s(dout_s),
        .probe_busy(probe_busy), .probe_dout(probe_dout),
        .conv_cnt(conv_cnt),
        .ch0(ch0), .ch1(ch1), .ch2(ch2), .ch3(ch3),
        .ch4(ch4), .ch5(ch5), .ch6(ch6), .ch7(ch7)
    );

    assign adc_dout = shifter[127];

    always #5 clk = ~clk;

    always @(posedge clk) begin
        sclk_d <= adc_sclk;
        cs_d   <= adc_cs;
        if (!adc_cs && adc_sclk && !sclk_d)
            shifter <= {shifter[126:0], 1'b0};
        if (adc_convst)
            saw_convst <= 1'b1;
        if (adc_convst) begin
            adc_busy <= 1'b1;
            busy_cnt <= 0;
        end else if (adc_busy) begin
            if (busy_cnt == 40)
                adc_busy <= 1'b0;
            else
                busy_cnt <= busy_cnt + 1;
        end
    end

    initial begin
        fail = 0;
        saw_convst = 0;
        busy_cnt = 0;
        shifter = {W0, W1, W2, W3, W4, W5, W6, W7};
        cyc = 0;
        while (!idle && cyc < 80000) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        if (!idle) begin
            $display("FAIL reset never reached idle (%0d cyc)", cyc);
            $finish;
        end
        $display("reset to idle in %0d cycles (expect ~54000) sclk=%b", cyc, adc_sclk);
        if (adc_sclk !== 1'b1) begin
            $display("FAIL idle SCLK must be 1 (CPOL=1)");
            fail = fail + 1;
        end
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;
        cyc = 0;
        while (!sample_done && cyc < 40000) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        @(posedge clk);
        $display("sample_done after %0d cycles status=%0d", cyc, status);
        if (ch0 !== W0) begin $display("FAIL ch0 %h", ch0); fail = fail + 1; end
        else $display("PASS ch0 %h", ch0);
        if (ch1 !== W1) begin $display("FAIL ch1 %h", ch1); fail = fail + 1; end
        else $display("PASS ch1 %h", ch1);
        if (ch2 !== W2) begin $display("FAIL ch2 %h", ch2); fail = fail + 1; end
        else $display("PASS ch2 %h", ch2);
        if (ch3 !== W3) begin $display("FAIL ch3 %h", ch3); fail = fail + 1; end
        else $display("PASS ch3 %h", ch3);
        if (ch4 !== W4) begin $display("FAIL ch4 %h", ch4); fail = fail + 1; end
        else $display("PASS ch4 %h", ch4);
        if (ch5 !== W5) begin $display("FAIL ch5 %h", ch5); fail = fail + 1; end
        else $display("PASS ch5 %h", ch5);
        if (ch6 !== W6) begin $display("FAIL ch6 %h", ch6); fail = fail + 1; end
        else $display("PASS ch6 %h", ch6);
        if (ch7 !== W7) begin $display("FAIL ch7 %h", ch7); fail = fail + 1; end
        else $display("PASS ch7 %h", ch7);
        if (!regs_valid) begin $display("FAIL regs_valid"); fail = fail + 1; end
        if (!saw_convst) begin $display("FAIL no CONVST"); fail = fail + 1; end
        if (status != 3'd3) begin $display("FAIL status %0d want OK=3", status); fail = fail + 1; end
        if (conv_cnt !== 16'd1) begin $display("FAIL conv_cnt %h", conv_cnt); fail = fail + 1; end
        if (probe_busy !== 1'b1) begin $display("FAIL probe_busy"); fail = fail + 1; end
        if (fail == 0)
            $display("tb_adc_master: ALL PASS");
        else
            $display("tb_adc_master: %0d FAIL", fail);
        $finish;
    end
endmodule
