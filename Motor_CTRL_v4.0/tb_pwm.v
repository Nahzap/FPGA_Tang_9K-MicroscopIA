`timescale 1ns/1ps
`include "config.vh"
// DRV8871 pulse rules of plan PWM v4 phase 1 (W1..W11), through drive:
// the same % orders, Q counter, I and pause that top uses. Counts clocks
// at the pins, not a motor. Everything is sampled on the falling edge:
// there the pins show the slot of the cnt value one clock before.
module tb_pwm;
    reg clk = 0;
    always #18.518 clk = ~clk;   // 27 MHz

    localparam integer PER = `CFG_PWM_PERIOD;
    localparam integer MIN = `CFG_PWM_MIN;
    localparam integer TK  = 100;   // clocks per fake ms tick
    localparam [1:0]   M_PWM = 2'd1;

    reg              halt = 0;
    reg              rst = 1;            // boots in RESET, as top
    reg signed [9:0] pa = 0, pb = 0;
    reg              inv_x = 0;
    reg              q_go = 0;
    reg signed [9:0] q_pot = 0;
    reg [15:0]       q_n = 0;
    reg              ord_p = 0, clr_err = 0;
    reg              edge_x = 0;
    wire             x1, x2, y1, y2, q_busy, x_stl, y_stl, err;
    wire signed [9:0] rep_a, rep_b;

    drive #(.TICK(TK)) u_drv (
        .clk(clk), .paused(halt), .mode(M_PWM), .in_reset(rst),
        .pwr_a(pa), .pwr_b(pb), .inv_x(inv_x), .inv_y(1'b0),
        .man_a(10'sd0), .man_b(10'sd0),
        .q_go_x(q_go), .q_go_y(1'b0), .q_pot(q_pot), .q_n(q_n),
        .ord_p(ord_p), .rst_p(clr_err), .x_moved(edge_x), .y_moved(edge_x),
        .x_in1(x1), .x_in2(x2), .y_in1(y1), .y_in2(y2),
        .rep_a(rep_a), .rep_b(rep_b), .q_busy(q_busy),
        .x_stl(x_stl), .y_stl(y_stl), .err(err), .ms_tick()
    );
    wire [9:0] cnt_x = u_drv.cnt_x;

    integer tc = 0;
    always @(posedge clk) tc = tc + 1;

    // Hall edges every 2000 clocks while edge_on (the guard stays quiet).
    reg     edge_on = 1;
    integer ec = 0;
    always @(posedge clk) begin
        ec = edge_on ? ec + 1 : 0;
        edge_x <= edge_on && ((ec % 2000) < 80);
    end

    integer fails = 0;
    task check;
        input ok;
        input [8*48-1:0] what;
        begin
            if (ok) $display("ok   %0s", what);
            else begin
                $display("FAIL %0s", what);
                fails = fails + 1;
            end
        end
    endtask

    task pulse_ord;
        begin
            ord_p = 1; @(negedge clk); ord_p = 0;
        end
    endtask

    // ---- W2 and W4 at every clock: shortest segment, direct reversal ----
    localparam integer BIG = 1000000;
    reg     seg_chk = 1;
    reg     px1 = 0, px2 = 0, py1 = 0, py2 = 0;
    integer lx1 = BIG, lx2 = BIG, ly1 = BIG, ly2 = BIG;
    integer short_n = 0, short_min = BIG, flip_n = 0;
    task seg;
        input         now;
        input         was;
        inout integer len;
        begin
            if (!seg_chk)
                len = BIG;
            else if (now != was) begin
                if (len < MIN) begin
                    short_n = short_n + 1;
                    if (len < short_min) short_min = len;
                end
                len = 1;
            end else if (len < BIG)
                len = len + 1;
        end
    endtask
    always @(negedge clk) begin
        seg(x1, px1, lx1);
        seg(x2, px2, lx2);
        seg(y1, py1, ly1);
        seg(y2, py2, ly2);
        if (({px1, px2} == 2'b10 && {x1, x2} == 2'b01) ||
            ({px1, px2} == 2'b01 && {x1, x2} == 2'b10) ||
            ({py1, py2} == 2'b10 && {y1, y2} == 2'b01) ||
            ({py1, py2} == 2'b01 && {y1, y2} == 2'b10))
            flip_n = flip_n + 1;
        px1 = x1; px2 = x2; py1 = y1; py2 = y2;
    end

    // One whole X period at the pins, from its first slot. At slot 999 the
    // next % and RESET are set; the boundary that follows takes them.
    integer c10, c01, c11, c00;
    task period_x;
        input integer nxt;
        input         nxt_rst;
        input integer mid_slot;
        input integer mid_val;
        integer k;
        begin
            while (cnt_x != 10'd1) @(negedge clk);
            c10 = 0; c01 = 0; c11 = 0; c00 = 0;
            for (k = 0; k < PER; k = k + 1) begin
                case ({x1, x2})
                    2'b10: c10 = c10 + 1;
                    2'b01: c01 = c01 + 1;
                    2'b11: c11 = c11 + 1;
                    default: c00 = c00 + 1;
                endcase
                if (k == mid_slot) pa = mid_val;
                if (k == PER - 1) begin
                    pa  = nxt;
                    rst = nxt_rst;
                end
                @(negedge clk);
            end
        end
    endtask

    function integer legal;
        input integer d;
        begin
            if (d == 0) legal = 0;
            else if (d < MIN) legal = MIN;
            else if (d > PER - MIN) legal = PER;
            else legal = d;
        end
    endfunction

    integer d, n, bad, nq, nb, no, t0, tx, ty, i, ni;
    integer qns [0:2];
    initial begin
        qns[0] = 1; qns[1] = 27; qns[2] = 1000;
        @(negedge clk);
        bad = 0;
        repeat (3 * PER) begin
            @(negedge clk);
            if ({x1, x2, y1, y2} != 4'b0000) bad = bad + 1;
        end
        check(bad == 0, "power-up in RESET: 00 on both bridges");

        // Out of RESET into brake (two wake periods), then hold 0.
        period_x(0, 0, -1, 0);
        period_x(0, 0, -1, 0);
        period_x(0, 0, -1, 0);
        period_x(0, 0, -1, 0);
        check(c11 == PER, "settled in brake 11");

        // ---- W1: every % the serial can give, 0..100, both senses ----
        bad = 0;
        for (d = 0; d <= 100; d = d + 1) begin
            period_x((d == 100) ? 0 : d + 1, 0, -1, 0);
            if ((c10 != legal(10 * d)) || (c01 != 0) || (c00 != 0) ||
                (c11 != PER - legal(10 * d))) begin
                if (bad < 5)
                    $display("     fwd %0d %%: 10=%0d 01=%0d 11=%0d 00=%0d", d, c10, c01, c11, c00);
                bad = bad + 1;
            end
        end
        check(bad == 0, "W1 forward 0..100 % = legal clocks");
        period_x(0, 0, -1, 0);   // the 0 set at the end of 100 %: brake
        bad = 0;
        for (d = 0; d <= 100; d = d + 1) begin
            period_x((d == 100) ? -100 : -(d + 1), 0, -1, 0);
            if ((c01 != legal(10 * d)) || (c10 != 0) || (c00 != 0) ||
                (c11 != PER - legal(10 * d))) begin
                if (bad < 5)
                    $display("     rev %0d %%: 10=%0d 01=%0d 11=%0d 00=%0d", d, c10, c01, c11, c00);
                bad = bad + 1;
            end
        end
        check(bad == 0, "W1 reverse 0..100 % = legal clocks");
        $display("     1 %% -> %0d, 2 %% -> %0d, 98 %% -> %0d clocks",
                 legal(10), legal(20), legal(980));

        // ---- W2: every high and low so far ----
        check(short_n == 0, "W2 no segment under 22 clocks");
        if (short_n != 0) $display("     %0d short, min %0d", short_n, short_min);

        // ---- W3: change in the middle of a period ----
        period_x(-100, 0, -1, 0);
        period_x(0, 0, -1, 0);          // -100 -> 0: brake
        period_x(40, 0, -1, 0);         // brake, 40 set at its end
        period_x(70, 0, 500, 70);       // 40 % period, 70 set at slot 500
        check(c10 == 400, "W3 period in course keeps 40 %");
        period_x(70, 0, -1, 0);
        check(c10 == 700, "W3 next period takes 70 %");

        // ---- W4: forward -> reverse -> forward ----
        flip_n = 0;
        period_x(30, 0, -1, 0);
        period_x(-30, 0, -1, 0);
        check(c10 == 300, "W4 forward 30 %");
        period_x(-30, 0, -1, 0);
        check(c11 == PER, "W4 reversal: one whole period of 11");
        period_x(30, 0, -1, 0);
        check(c01 == 300, "W4 reverse 30 %");
        period_x(30, 0, -1, 0);
        check(c11 == PER, "W4 back: one whole period of 11");
        period_x(30, 0, -1, 0);
        check(c10 == 300, "W4 forward 30 % again");
        check(flip_n == 0, "W4 no direct 10 <-> 01");

        // ---- W5: 1.2 ms of 00 (RESET, nothing to drive), then 30 % ----
        period_x(0, 1, -1, 0);
        bad = 0;
        for (i = 0; i < 33; i = i + 1) begin   // 33 periods = 1.22 ms
            period_x((i == 32) ? 30 : 0, (i == 32) ? 0 : 1, -1, 0);
            if (c00 != PER) bad = bad + 1;
        end
        check(bad == 0, "W5 1.2 ms of 00");
        period_x(30, 0, -1, 0);
        nb = (c11 == PER);
        period_x(30, 0, -1, 0);
        nb = nb + (c11 == PER);
        check(nb == 2, "W5 two whole periods of 11 to wake");
        period_x(30, 0, -1, 0);
        check(c10 == 300 && c11 == PER - 300, "W5 first chopped period = 300");

        // ---- W6: brake 10 ms ----
        period_x(0, 0, -1, 0);
        bad = 0;
        for (i = 0; i < 270; i = i + 1) begin
            period_x(0, 0, -1, 0);
            if (c11 != PER) bad = bad + 1;
        end
        check(bad == 0, "W6 brake 10 ms: 11 all the time, never 00");

        // ---- W6b: pause cuts to 00 at once, then wakes ----
        period_x(30, 0, -1, 0);
        period_x(30, 0, -1, 0);
        while (cnt_x != 10'd200) @(negedge clk);
        seg_chk = 0;
        halt = 1;
        @(negedge clk);
        @(negedge clk);
        check({x1, x2, y1, y2} == 4'b0000 && rep_a == 0, "W6b pause: 00 one clock later, PotenciaA 0");
        repeat (3 * PER) @(negedge clk);
        halt = 0;
        period_x(30, 0, -1, 0);
        nb = (c11 == PER);
        seg_chk = 1;
        period_x(30, 0, -1, 0);
        nb = nb + (c11 == PER);
        period_x(30, 0, -1, 0);
        check(nb == 2 && c10 == 300, "W6b after pause: 2 x 11, then 300");

        // ---- W7: X and Y at the same command ----
        pb = 30;
        repeat (4 * PER) @(negedge clk);
        while (!(x1 && x2)) @(negedge clk);
        while (x2) @(negedge clk);       // X starts a drive
        tx = tc;
        while (!(y1 && y2)) @(negedge clk);
        while (y2) @(negedge clk);       // Y starts a drive
        ty = tc;
        check((ty - tx) == PER / 2, "W7 Y boundary 500 clocks after X");
        $display("     X -> Y %0d clocks", ty - tx);
        pb = 0;

        // ---- W8: stall guard ----
        period_x(30, 0, -1, 0);
        check(c10 == 300, "W8 driving 30 % before the guard");
        edge_on = 0;
        pulse_ord;
        t0 = tc;
        while (!x_stl && (tc - t0 < 2 * `CFG_STALL_MS * TK)) @(negedge clk);
        n = tc - t0;
        check(x_stl && (n >= (`CFG_STALL_MS - 1) * TK) && (n <= (`CFG_STALL_MS + 1) * TK),
              "W8 no edges: stall at CFG_STALL_MS");
        $display("     stall after %0d ticks", n / TK);
        period_x(30, 0, -1, 0);
        period_x(30, 0, -1, 0);
        check(c11 == PER && rep_a == 0, "W8 stalled: brake 11, PotenciaA 0");
        edge_on = 1;
        pulse_ord;
        bad = 0;
        for (i = 0; i < 200; i = i + 1) begin
            period_x(30, 0, -1, 0);
            if ((i > 2) && (c10 != 300)) bad = bad + 1;
        end
        check(!x_stl && bad == 0 && rep_a == 30, "W8 with edges: keeps driving 200 periods");

        // ---- W9: Q with n = 1, 27, 1000 from brake ----
        period_x(0, 0, -1, 0);
        period_x(0, 0, -1, 0);
        for (ni = 0; ni < 3; ni = ni + 1) begin
            n = qns[ni];
            period_x(0, 0, -1, 0);
            while (cnt_x != 10'd700) @(negedge clk);
            q_pot = 40; q_n = n; q_go = 1; ord_p = 1;   // as com_ctrl: both at once
            @(negedge clk);
            q_go = 0; ord_p = 0;
            nq = 0; nb = 0; no = 0;
            for (i = 0; i < n + 3; i = i + 1) begin
                period_x(0, 0, -1, 0);
                if (c10 == 400 && c11 == PER - 400) nq = nq + 1;
                else if (c11 == PER) nb = nb + 1;
                else no = no + 1;
            end
            check(nq == n && nb == 3 && no == 0 && !q_busy, "W9 Q: exactly n periods, then 11");
            $display("     n=%0d: %0d periods of 400, %0d of 11, %0d other", n, nq, nb, no);
        end

        // ---- W9b: another order ends a running Q ----
        period_x(0, 0, -1, 0);
        while (cnt_x != 10'd700) @(negedge clk);
        q_pot = -40; q_n = 1000; q_go = 1; ord_p = 1;
        @(negedge clk);
        q_go = 0; ord_p = 0;
        nq = 0;
        for (i = 0; i < 12; i = i + 1) begin
            period_x(0, 0, -1, 0);
            if (c01 == 400) nq = nq + 1;
            if (i == 3) check(q_busy && rep_a == -40, "W9b during Q: busy, PotenciaA -40");
            if (i == 8) pulse_ord;
        end
        check(!q_busy && nq >= 9 && nq <= 11 && c11 == PER, "W9b order mid-Q: Q ends, brake");
        $display("     %0d periods of Q before the order", nq);

        // ---- W11: I flips the sense ----
        inv_x = 1;
        period_x(30, 0, -1, 0);
        period_x(30, 0, -1, 0);
        period_x(30, 0, -1, 0);
        check(c01 == 300 && c10 == 0, "W11 I: +30 % drives reverse");
        inv_x = 0;
        period_x(0, 0, -1, 0);

        // ---- W10: meter ----
        check(!err, "W10 meter: 0 warnings in W1..W11");
        check(short_n == 0 && flip_n == 0, "W2/W4 hold to the end");
        period_x(0, 0, -1, 0);
        seg_chk = 0;
        while (cnt_x != 10'd300) @(negedge clk);
        force u_drv.u_px.in2 = 1'b0;
        repeat (5) @(negedge clk);
        release u_drv.u_px.in2;
        repeat (2 * PER) @(negedge clk);
        check(err, "W10 forced 5 clocks of 10 in brake: warning on");
        clr_err = 1; @(negedge clk); clr_err = 0;
        repeat (3 * PER) @(negedge clk);
        check(!err, "W10 reset clears it, stays off");

        if (fails == 0) $display("PASS");
        else $display("FAILS %0d", fails);
        $finish;
    end
endmodule
