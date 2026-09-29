`timescale 1ns/1ps
`include "config.vh"
// Serial orders through the real UART into com_ctrl, marks into motion.
// The TX line is decoded back: Estado, Settled, PotA, PotB and PotenciaA
// of the last line are what the PC reads.
module tb_com;
    reg clk = 0;
    always #18.518 clk = ~clk;   // 27 MHz

    localparam integer BIT = `CFG_UART_DIV;
    localparam integer GAP = 20000;   // shorter pause between lines

    reg rx = 1'b1;
    wire tx;
    wire [1:0] mode;
    wire signed [9:0] pwr_a, pwr_b, x_rep, y_rep;
    wire [19:0] pc_x, pc_y;
    wire inv_x, inv_y, xz, yz, xf, yf, rst_p;
    wire [19:0] x_sens, y_sens, x_tgt, y_tgt;
    wire x_arm, y_arm, lock_p;
    wire [15:0] xa, xb, ya, yb;
    reg  conv = 0;

    com_ctrl #(.GAP(GAP)) u_com (
        .clk(clk), .rx(rx), .tx(tx),
        .rep_a(x_rep), .rep_b(y_rep),
        .sensor1(x_sens), .sensor2(y_sens), .pot_a(x_tgt), .pot_b(y_tgt),
        .x_dig(), .y_dig(), .in_gate_a(1'b1), .in_gate_b(1'b1),
        .x_arm(x_arm), .y_arm(y_arm), .mode(mode),
        .pwr_a(pwr_a), .pwr_b(pwr_b), .tgt_x(pc_x), .tgt_y(pc_y),
        .inv_x(inv_x), .inv_y(inv_y),
        .x_zero_p(xz), .y_zero_p(yz), .x_final_p(xf), .y_final_p(yf),
        .rst_p(rst_p), .lock_p(lock_p)
    );

    motion u_mot (
        .clk(clk), .conv(conv), .tick(1'b0), .mode(mode),
        .pwr_a(pwr_a), .pwr_b(pwr_b), .tgt_x(pc_x), .tgt_y(pc_y),
        .inv_x(inv_x), .inv_y(inv_y),
        .x_zero(xz), .x_final(xf), .y_zero(yz), .y_final(yf), .clr(rst_p),
        .lock(lock_p), .pot_x(16'd10813), .pot_y(16'd10813),
        .xa(xa), .xb(xb), .ya(ya), .yb(yb),
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
        input [8*32-1:0] s;
        input [15:0] eol;   // up to two end bytes, 0 = none
        integer i;
        reg [7:0] c;
        begin
            for (i = 31; i >= 0; i = i - 1) begin
                c = s[i*8 +: 8];
                if (c != 8'd0)
                    send_byte(c);
            end
            if (eol[15:8] != 8'd0) send_byte(eol[15:8]);
            if (eol[7:0]  != 8'd0) send_byte(eol[7:0]);
            repeat (200) @(posedge clk);
        end
    endtask

    // ADC conversions, and X/Y Halls that can be stepped by hand.
    integer cc = 0;
    always @(posedge clk) begin
        conv <= 1'b0;
        cc = cc + 1;
        if (cc == 700) begin
            cc = 0;
            conv <= 1'b1;
        end
    end
    integer px = 0, py = 0;
    assign xa = (((px % 4) == 2) || ((px % 4) == 3)) ? 16'd12600 : 16'd9000;
    assign xb = (((px % 4) == 1) || ((px % 4) == 2)) ? 16'd12600 : 16'd9000;
    assign ya = (((py % 4) == 2) || ((py % 4) == 3)) ? 16'd12600 : 16'd9000;
    assign yb = (((py % 4) == 1) || ((py % 4) == 2)) ? 16'd12600 : 16'd9000;
    task step_x;
        input integer n;
        integer i;
        for (i = 0; i < n; i = i + 1) begin
            px = px + 1;
            repeat (3000) @(posedge clk);
        end
    endtask
    task step_y;
        input integer n;
        integer i;
        for (i = 0; i < n; i = i + 1) begin
            py = py + 1;
            repeat (3000) @(posedge clk);
        end
    endtask

    // TX decoder: one line into its fields.
    integer    lines = 0;
    reg [63:0] l_state = 0;
    reg [7:0]  l_set = 0;
    integer    l_pa = 0, l_pb = 0, l_pwa = 0, l_len = 0;
    reg [63:0] w_state;
    reg [7:0]  w_set;
    integer    w_pa, w_pb, w_pwa, w_mag, w_fld, w_len;
    reg        w_neg, w_hdr;
    reg [7:0]  rb;
    integer    ri;
    initial begin
        w_state = 0; w_set = 0; w_pa = 0; w_pb = 0; w_pwa = 0; w_mag = 0;
        w_fld = 0; w_len = 0; w_neg = 0; w_hdr = 0;
        forever begin
            @(negedge tx);
            repeat (BIT / 2) @(posedge clk);
            if (tx == 1'b0) begin
                for (ri = 0; ri < 8; ri = ri + 1) begin
                    repeat (BIT) @(posedge clk);
                    rb[ri] = tx;
                end
                repeat (BIT) @(posedge clk);
                if (rb == 8'h0A) begin
                    if (!w_hdr) begin
                        l_state = w_state;
                        l_set   = w_set;
                        l_pa    = w_pa;
                        l_pb    = w_pb;
                        l_pwa   = w_pwa;
                        l_len   = w_len + 1;
                        lines   = lines + 1;
                    end
                    w_state = 0; w_set = 0; w_pa = 0; w_pb = 0; w_pwa = 0;
                    w_mag = 0; w_fld = 0; w_len = 0; w_neg = 0; w_hdr = 0;
                end else begin
                    w_len = w_len + 1;
                    if ((w_len == 1) && (rb == "P"))
                        w_hdr = 1'b1;
                    if (rb == ",") begin
                        if (w_fld == 0)
                            w_pwa = w_neg ? -w_mag : w_mag;
                        w_fld = w_fld + 1;
                        w_mag = 0;
                    end else if (rb != 8'h0D) begin
                        if (w_fld == 0) begin
                            if (rb == "-") w_neg = 1'b1;
                            else if (rb != "+") w_mag = w_mag * 10 + (rb - "0");
                        end else if (w_fld == 2)
                            w_pa = w_pa * 10 + (rb - "0");
                        else if (w_fld == 3)
                            w_pb = w_pb * 10 + (rb - "0");
                        else if (w_fld == 6)
                            w_state = {w_state[55:0], rb};
                        else if (w_fld == 7)
                            w_set = rb;
                    end
                end
            end
        end
    end
    // Two new lines: the second one was built after the order.
    task wait_lines;
        input integer n;
        integer l0;
        begin
            l0 = lines;
            wait (lines >= l0 + n);
        end
    endtask

    integer fails = 0;
    task check;
        input ok;
        input [8*32-1:0] what;
        begin
            if (ok) $display("ok   %0s", what);
            else begin
                $display("FAIL %0s", what);
                fails = fails + 1;
            end
        end
    endtask
    // Order, two lines, then the Estado text must match.
    task order_state;
        input [8*32-1:0] s;
        input [63:0] want;
        input [8*32-1:0] what;
        begin
            send_line(s, {8'h0D, 8'h0A});
            wait_lines(2);
            check(l_state == want, what);
            if (l_state != want)
                $display("     Estado %0s", l_state);
        end
    endtask

    localparam integer STEP = (2 * `CFG_HALL_TH) >> `CFG_HALL_SHIFT;
    localparam integer FXC = 30 * STEP, FYC = 40 * STEP;

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

        // ---- v3.0: order T, AUTO and the PWM_* names ----
        // Both axes with a span: X 30 edges, Y 40 edges.
        send_line("reset", {8'h0D, 8'h0A});
        send_line("x_zero", {8'h0D, 8'h0A});
        send_line("y_zero", {8'h0D, 8'h0A});
        step_x(30);
        step_y(40);
        send_line("x_final", {8'h0D, 8'h0A});
        send_line("y_final", {8'h0D, 8'h0A});
        wait_lines(2);
        check(u_mot.fmax[0] == FXC && u_mot.fmax[1] == FYC && l_state == "MANUAL",
              "spans X 30, Y 40 edges, MANUAL");

        // C1: counts inside and past the max of each axis.
        order_state("T,1000,99999,40,40", "AUTO", "C1 T: Estado AUTO");
        check(mode == 2'd3 && pc_x == 20'd1000 && pc_y == 20'd99999, "C1 T: mode 3, both counts");
        check(l_pa == 1000 && l_pb == FYC, "C1 PotA = 1000, PotB = max Y");
        check(l_len == 46, "C1 AUTO line 46 bytes");
        check(l_pwa == 40 || l_pwa == -40, "C1 PotenciaA = +-40");
        $display("     PotA %0d PotB %0d PotenciaA %0d", l_pa, l_pb, l_pwa);

        // C2: a negative count reads as 0.
        order_state("T,-500,2000,40,40", "AUTO", "C2 T negative: AUTO");
        check(pc_x == 20'd0 && l_pa == 0 && l_pb == 2000, "C2 negative count = 0");

        // C3: power 40, 120 and -10 give 40, 80 and 0.
        order_state("T,1000,1000,40,120", "AUTO", "C3 T 40,120: AUTO");
        check(pwr_a == 10'sd40 && pwr_b == `CFG_POWER, "C3 power 40 and 120 -> 40, 80");
        order_state("T,1000,1000,-10,40", "AUTO", "C3 T -10,40: AUTO");
        check(pwr_a == 10'sd0 && pwr_b == 10'sd40, "C3 power -10 -> 0");
        order_state("T,9999999,1000,40,40", "AUTO", "C3 T 7 digits: AUTO");
        check(pc_x == 20'd999999 && l_pa == FXC, "C3 7 digits cap at 999999");

        // C4: names of free power.
        order_state("A,30,0", "PWM_X", "C4 A,30,0 -> PWM_X");
        check(mode == 2'd1, "C4 PWM_X mode 1");
        order_state("A,0,-30", "PWM_Y", "C4 A,0,-30 -> PWM_Y");
        order_state("A,30,30", "PWM_XY", "C4 A,30,30 -> PWM_XY");
        check(l_len == 48, "C4 PWM_XY line 48 bytes");
        order_state("N", "PWM_0", "C4 N -> PWM_0");
        check(l_set == "1", "C4 PWM_0 Settled 1");

        // C5: each order leaves AUTO for its own mode.
        order_state("T,1000,1000,40,40", "AUTO", "C5 T");
        order_state("M", "MANUAL", "C5 M -> MANUAL");
        check(mode == 2'd0, "C5 MANUAL mode 0");
        order_state("T,1000,1000,40,40", "AUTO", "C5 T");
        order_state("A,20,0", "PWM_X", "C5 A -> PWM_X");
        order_state("T,1000,1000,40,40", "AUTO", "C5 T");
        order_state("N", "PWM_0", "C5 N -> PWM_0");
        order_state("T,1000,1000,40,40", "AUTO", "C5 T");
        order_state("B", "BRAKE", "C5 B -> BRAKE");
        check(mode == 2'd2 && l_set == "1", "C5 BRAKE mode 2, Settled 1");
        order_state("T,1000,1000,40,40", "AUTO", "C5 T");
        order_state("P,A,1,0", "PULSE", "C5 P -> PULSE");
        repeat (27000 * 25) @(posedge clk);
        wait_lines(2);
        check(l_state == "PWM_0" && mode == 2'd1, "C5 after the pulse: PWM_0");

        // C6: reset and each mark in AUTO leave PWM_0.
        order_state("T,1000,1000,40,40", "AUTO", "C6 T");
        order_state("x_zero", "PWM_0", "C6 x_zero -> PWM_0");
        order_state("T,1000,1000,40,40", "AUTO", "C6 T");
        order_state("y_zero", "PWM_0", "C6 y_zero -> PWM_0");
        order_state("T,1000,1000,40,40", "AUTO", "C6 T");
        order_state("x_final", "PWM_0", "C6 x_final -> PWM_0");
        order_state("T,1000,1000,40,40", "AUTO", "C6 T");
        order_state("y_final", "PWM_0", "C6 y_final -> PWM_0");
        order_state("T,1000,1000,40,40", "AUTO", "C6 T");
        order_state("reset", "RESET", "C6 reset -> RESET");
        check(u_com.mode_q == 2'd1 && pwr_a == 10'sd0 && pwr_b == 10'sd0,
              "C6 reset in AUTO: mode PWM_0");

        // C7: T in RESET is ignored.
        order_state("T,500,600,40,40", "RESET", "C7 T in RESET: still RESET");
        check(u_com.mode_q == 2'd1 && pc_x == 20'd1000 && pc_y == 20'd1000 &&
              pwr_a == 10'sd0 && pwr_b == 10'sd0, "C7 T in RESET changes nothing");

        if (fails == 0) $display("PASS");
        else $display("FAILS %0d", fails);
        $finish;
    end
endmodule
