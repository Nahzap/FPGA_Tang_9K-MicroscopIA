`timescale 1ns/1ps
`include "config.vh"
// Serial orders through the real UART into com_ctrl, marks into motion.
module tb_com;
    reg clk = 0;
    always #18.518 clk = ~clk;   // 27 MHz

    localparam integer BIT = `CFG_UART_DIV;

    reg rx = 1'b1;
    wire tx;
    wire [1:0] mode;
    wire signed [9:0] pwr_a, pwr_b, x_rep, y_rep;
    wire inv_x, inv_y, xz, yz, xf, yf, rst_p;
    wire [19:0] x_sens, y_sens, x_tgt, y_tgt;
    wire x_arm, y_arm, lock_p;
    wire [15:0] ya, yb;
    reg  conv = 0;

    com_ctrl u_com (
        .clk(clk), .rx(rx), .tx(tx),
        .rep_a(x_rep), .rep_b(y_rep),
        .sensor1(x_sens), .sensor2(y_sens), .pot_a(x_tgt), .pot_b(y_tgt),
        .x_dig(), .y_dig(), .in_gate_a(1'b1), .in_gate_b(1'b1),
        .x_arm(x_arm), .y_arm(y_arm), .mode(mode),
        .pwr_a(pwr_a), .pwr_b(pwr_b), .inv_x(inv_x), .inv_y(inv_y),
        .x_zero_p(xz), .y_zero_p(yz), .x_final_p(xf), .y_final_p(yf),
        .rst_p(rst_p), .lock_p(lock_p)
    );

    motion u_mot (
        .clk(clk), .conv(conv), .tick(1'b0), .mode(mode),
        .pwr_a(pwr_a), .pwr_b(pwr_b), .inv_x(inv_x), .inv_y(inv_y),
        .x_zero(xz), .x_final(xf), .y_zero(yz), .y_final(yf), .clr(rst_p),
        .lock(lock_p), .pot_x(16'd10813), .pot_y(16'd10813),
        .xa(16'd9000), .xb(16'd9000), .ya(ya), .yb(yb),
        .x_fwd(), .x_rev(), .x_brake(), .x_cmp(), .x_rep(x_rep),
        .x_sens(x_sens), .x_tgt(x_tgt), .x_moved(), .x_gate(), .x_arm(x_arm),
        .x_hlo(), .x_hhi(),
        .y_fwd(), .y_rev(), .y_brake(), .y_cmp(), .y_rep(y_rep),
        .y_sens(y_sens), .y_tgt(y_tgt), .y_moved(), .y_gate(), .y_arm(y_arm),
        .y_hlo(), .y_hhi()
    );

    task send_byte;
        input [7:0] b;
        integer i;
        begin
            rx = 1'b0;
            repeat (BIT) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i];
                repeat (BIT) @(posedge clk);
            end
            rx = 1'b1;
            repeat (BIT * 2) @(posedge clk);
        end
    endtask

    task send_line;
        input [8*16-1:0] s;
        input [15:0] eol;   // up to two end bytes, 0 = none
        integer i;
        reg [7:0] c;
        begin
            for (i = 15; i >= 0; i = i - 1) begin
                c = s[i*8 +: 8];
                if (c != 8'd0)
                    send_byte(c);
            end
            if (eol[15:8] != 8'd0) send_byte(eol[15:8]);
            if (eol[7:0]  != 8'd0) send_byte(eol[7:0]);
            repeat (200) @(posedge clk);
        end
    endtask

    // ADC conversions, and a Y Hall that can be stepped by hand.
    integer cc = 0;
    always @(posedge clk) begin
        conv <= 1'b0;
        cc = cc + 1;
        if (cc == 700) begin
            cc = 0;
            conv <= 1'b1;
        end
    end
    integer py = 0;
    assign ya = (((py % 4) == 2) || ((py % 4) == 3)) ? 16'd12600 : 16'd9000;
    assign yb = (((py % 4) == 1) || ((py % 4) == 2)) ? 16'd12600 : 16'd9000;
    task step_y;
        input integer n;
        integer i;
        for (i = 0; i < n; i = i + 1) begin
            py = py + 1;
            repeat (3000) @(posedge clk);
        end
    endtask

    integer fails = 0;
    task check;
        input ok;
        input [8*24-1:0] what;
        begin
            if (ok) $display("ok   %0s", what);
            else begin
                $display("FAIL %0s", what);
                fails = fails + 1;
            end
        end
    endtask

    initial begin
        repeat (1000) @(posedge clk);
        check(u_com.rst_q == 1'b1, "boots in RESET");

        // Finals alone calibrate: the count starts at 0.
        send_line("x_final", {8'h0D, 8'h0A});
        send_line("y_final", {8'h0D, 8'h0A});
        check(x_arm && y_arm, "CRLF finals: both armed");
        check(u_com.rst_q == 1'b0, "CRLF finals: MANUAL");

        send_line("reset", {8'h0D, 8'h0A});
        check(!x_arm && !y_arm && u_com.rst_q, "reset clears");

        send_line("x_zero",  {8'h00, 8'h0D});
        send_line("y_zero",  {8'h00, 8'h0D});
        send_line("x_final", {8'h00, 8'h0D});
        send_line("y_final", {8'h00, 8'h0D});
        check(x_arm && y_arm, "CR only: both armed");
        check(u_com.rst_q == 1'b0, "CR only: left RESET");

        // Y reaches some count but gets no final; MANUAL keeps that max.
        send_line("reset", {8'h00, 8'h0A});
        step_y(40);
        send_line("x_zero",  {8'h00, 8'h0A});
        send_line("x_final", {8'h00, 8'h0A});
        check(x_arm && !y_arm && u_com.rst_q, "LF: X only, still RESET");
        check(y_sens != 0 && y_sens == u_mot.fmax[1], "Y max follows count");
        send_line("MANUAL", {8'h0D, 8'h0A});
        check(u_com.rst_q == 1'b0 && mode == 2'd0, "MANUAL leaves RESET");
        check(y_arm && u_mot.fmax[1] == y_sens, "MANUAL locks Y max");
        $display("     Y max = %0d", u_mot.fmax[1]);

        if (fails == 0) $display("PASS");
        else $display("FAILS %0d", fails);
        $finish;
    end
endmodule
