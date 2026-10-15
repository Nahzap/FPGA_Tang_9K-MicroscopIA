`timescale 1ns/1ps
`include "config.vh"
// v4.0: Hall count and pot target on the shared datapath, no drive.
// Pots read the 5 V regulator rail on the AD7606 at +-5 V (FULL codes).
// Hall levels are 9000 / 12600 codes around CFG_HALL_TH; each edge is STEP.
module tb_motion;
    localparam integer STEP   = (2 * `CFG_HALL_TH) >> `CFG_HALL_SHIFT;
    localparam integer FULL   = `CFG_POT_FULL;
    localparam integer PLO    = `CFG_POT_END;
    localparam integer PSPAN  = FULL - 2 * `CFG_POT_END;
    localparam integer HYST   = `CFG_POT_HYST;
    localparam integer CONV   = 100;   // clocks between ADC results
    localparam integer SETTLE = 12 * (1 << `CFG_POT_FILT) * CONV;
    // Travel of the guides: X 385 edges (32340 counts), Y 1039 (87276).
    localparam integer NX = 385, NY = 1039;
    localparam integer FX = NX * STEP, FY = NY * STEP;

    reg clk = 0;
    always #10 clk = ~clk;

    reg conv = 0;
    reg [1:0] mode = 0;
    reg [19:0] tgt_x = 0, tgt_y = 0;
    reg x_zero = 0, x_final = 0, y_zero = 0, y_final = 0, clr = 0, lock = 0;
    reg [15:0] pot_x = 0, pot_y = 0;
    wire [15:0] xa, xb, ya, yb;
    wire [19:0] x_sens, y_sens, x_tgt, y_tgt;
    wire x_arm, y_arm;
    wire signed [9:0] x_cmd, y_cmd;
    reg tick = 0;
    integer tck = 0;
    always @(posedge clk) begin
        tck = tck + 1;
        tick <= (tck % 80) == 0;
    end

    motion dut (
        .clk(clk), .conv(conv), .tick(tick), .mode(mode),
        .tgt_x(tgt_x), .tgt_y(tgt_y),
        .x_zero(x_zero), .x_final(x_final), .y_zero(y_zero), .y_final(y_final),
        .clr(clr), .lock(lock), .pot_x(pot_x), .pot_y(pot_y),
        .xa(xa), .xb(xb), .ya(ya), .yb(yb),
        .x_sens(x_sens), .x_tgt(x_tgt), .x_moved(), .x_arm(x_arm), .x_cmd(x_cmd),
        .y_sens(y_sens), .y_tgt(y_tgt), .y_moved(), .y_arm(y_arm), .y_cmd(y_cmd)
    );

    // Gray phase 00, 01, 11, 10 as the position rises (a = bit1, b = bit0).
    // Starts at 4000 so a step below the low end keeps a positive phase.
    integer px = 4000, py = 4000;
    function [15:0] lvl;
        input b;
        lvl = b ? 16'd12600 : 16'd9000;
    endfunction
    assign xa = lvl((px % 4) == 2 || (px % 4) == 3);
    assign xb = lvl((px % 4) == 1 || (px % 4) == 2);
    assign ya = lvl((py % 4) == 2 || (py % 4) == 3);
    assign yb = lvl((py % 4) == 1 || (py % 4) == 2);

    // ADC results every CONV clocks. noisy: pot_x = pot_base +- 100 codes.
    reg        noisy = 0;
    reg [15:0] pot_base = 0;
    integer    cc = 0, nz;
    always @(posedge clk) begin
        conv <= 1'b0;
        cc = cc + 1;
        if (cc == CONV) begin
            cc = 0;
            conv <= 1'b1;
            if (noisy) begin
                nz = $random % 101;
                pot_x <= pot_base + nz;
            end
        end
    end

    // Changes and span of the X target while watched.
    reg        watch = 0;
    reg [19:0] last_x = 0;
    integer    x_changes = 0, x_lo = 0, x_hi = 0;
    always @(posedge clk) begin
        if (watch) begin
            if (x_tgt != last_x)
                x_changes = x_changes + 1;
            if (x_tgt < x_lo) x_lo = x_tgt;
            if (x_tgt > x_hi) x_hi = x_tgt;
        end
        last_x <= x_tgt;
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

    // 0 x_zero, 1 x_final, 2 y_zero, 3 y_final, 4 reset, 5 lock (M).
    task mark;
        input integer which;
        begin
            @(negedge clk);
            case (which)
                0: x_zero  = 1'b1;
                1: x_final = 1'b1;
                2: y_zero  = 1'b1;
                3: y_final = 1'b1;
                4: clr     = 1'b1;
                default: lock = 1'b1;
            endcase
            @(negedge clk);
            x_zero = 0; x_final = 0; y_zero = 0; y_final = 0; clr = 0; lock = 0;
            repeat (3 * CONV) @(posedge clk);
        end
    endtask

    task step_x;
        input integer n, dir;
        integer i;
        for (i = 0; i < n; i = i + 1) begin
            px = px + dir;
            repeat (3 * CONV) @(posedge clk);
        end
    endtask
    task step_y;
        input integer n, dir;
        integer i;
        for (i = 0; i < n; i = i + 1) begin
            py = py + dir;
            repeat (3 * CONV) @(posedge clk);
        end
    endtask

    task set_pots;
        input integer vx, vy;
        begin
            pot_x = vx;
            pot_y = vy;
            repeat (SETTLE) @(posedge clk);
        end
    endtask

    // Exact target for a pot code: dead ends, then a straight line.
    function integer want;
        input integer p, mx;
        begin
            if (p <= PLO)
                want = 0;
            else if ((p - PLO) >= PSPAN)
                want = mx;
            else
                want = $rtoi((p - PLO) * 1.0 * mx / PSPAN);
        end
    endfunction
    // The held pot value may sit up to HYST codes off the input.
    function integer tol;
        input integer mx;
        tol = $rtoi((HYST + 1) * 1.0 * mx / PSPAN) + 2;
    endfunction
    function integer iabs;
        input integer v;
        iabs = (v < 0) ? -v : v;
    endfunction

    integer k, p, q, wx, wy, worst_x, worst_y;

    initial begin
        $display("     FULL %0d (%0d mV)  END %0d  SPAN %0d  STEP %0d",
                 FULL, `CFG_POT_MV, PLO, PSPAN, STEP);
        repeat (1000) @(posedge clk);

        // ---- Hall count ----
        step_x(NX, 1);
        step_y(NY, 1);
        check(x_sens == FX && y_sens == FY, "H1 count up: X 385 and Y 1039 edges");
        check(dut.fmax[0] == FX && dut.fmax[1] == FY, "H2 no final: max follows the count");
        step_x(10, -1);
        check(x_sens == FX - 10 * STEP, "H3 X down 10 edges");
        step_x(10, 1);
        check(x_sens == FX, "H3 X up 10 edges");

        mark(1);
        mark(3);
        check(x_arm && y_arm && dut.fmax[0] == FX && dut.fmax[1] == FY,
              "K1 finals: max = count, both armed");
        step_x(5, 1);
        check(x_sens == FX, "H4 past the max: X stays at max");
        step_x(NX + 5, -1);
        check(x_sens == 0, "H5 past the low end: X floors at 0");
        step_x(3, 1);
        px = px + 2;   // both channels change in one conversion
        repeat (3 * CONV) @(posedge clk);
        check(x_sens == 5 * STEP, "H6 double edge: 2 edges, last direction");
        step_x(5, -1);
        check(x_sens == 0, "H6 back to 0");

        // ---- Pots on the 5 V rail, MANUAL ----
        set_pots(0, 0);
        check(x_tgt == 0 && y_tgt == 0, "P1 pot 0 V: target 0");
        set_pots(FULL, FULL);
        check(x_tgt == FX && y_tgt == FY, "P1 pot at CFG_POT_MV: target = max");
        set_pots(32767, 32767);
        check(x_tgt == FX && y_tgt == FY, "P2 ADC saturated (32767): max");
        set_pots(FULL - PLO + HYST, FULL - PLO + HYST);
        check(x_tgt == FX && y_tgt == FY, "P3 rail ~50 mV low: still max");
        set_pots(16'hFF00, 16'hFF00);
        check(x_tgt == 0 && y_tgt == 0, "P4 negative reading: 0");
        set_pots(PLO - HYST - 1, PLO - HYST - 1);
        check(x_tgt == 0 && y_tgt == 0, "P4 inside the low dead end: 0");

        // Straight line, X rising and Y falling at the same time.
        worst_x = 0;
        worst_y = 0;
        for (k = 1; k <= 9; k = k + 1) begin
            p = PLO + (PSPAN * k) / 10;
            q = PLO + (PSPAN * (10 - k)) / 10;
            set_pots(p, q);
            wx = iabs(x_tgt - want(p, FX));
            wy = iabs(y_tgt - want(q, FY));
            if (wx > worst_x) worst_x = wx;
            if (wy > worst_y) worst_y = wy;
            $display("     %0d/10: X %0d (want %0d)  Y %0d (want %0d)",
                     k, x_tgt, want(p, FX), y_tgt, want(q, FY));
        end
        check(worst_x <= tol(FX) && worst_y <= tol(FY), "P5 line: X and Y within the hysteresis");
        $display("     worst X %0d (tol %0d)  worst Y %0d (tol %0d) counts",
                 worst_x, tol(FX), worst_y, tol(FY));

        // Noise of +-100 codes (+-15 mV) on the X pot at mid travel. The
        // target may step within the hysteresis, far below one edge (STEP).
        pot_base = PLO + PSPAN / 2;
        noisy = 1;
        repeat (SETTLE) @(posedge clk);
        x_changes = 0;
        x_lo = x_tgt;
        x_hi = x_tgt;
        watch = 1;
        repeat (2 * SETTLE) @(posedge clk);
        watch = 0;
        check((x_hi - x_lo) <= tol(FX) && tol(FX) < STEP,
              "P6 noise +-100 codes: X within the hysteresis");
        check(iabs(x_tgt - FX / 2) <= tol(FX), "P6 noise: X target at max/2");
        $display("     X target %0d..%0d, %0d changes in %0d conversions", x_lo, x_hi,
                 x_changes, (2 * SETTLE) / CONV);
        noisy = 0;

        // ---- AUTO: target from the PC, capped at the max ----
        set_pots(PLO + PSPAN / 4, PLO + PSPAN / 4);
        mode  = 2'd3;
        tgt_x = 20'd1000;
        tgt_y = 20'd999999;
        repeat (3 * CONV) @(posedge clk);
        check(x_tgt == 1000 && y_tgt == FY, "A1 T 1000 / 999999: 1000 and max Y");
        pot_x = 0;
        repeat (SETTLE) @(posedge clk);
        check(x_tgt == 1000, "A2 in AUTO the pot does not move the target");
        mode = 2'd0;
        repeat (3 * CONV) @(posedge clk);
        check(x_tgt == 0 && iabs(y_tgt - want(PLO + PSPAN / 4, FY)) <= tol(FY),
              "A3 MANUAL: the pots command again");

        // ---- Marks ----
        set_pots(FULL, FULL);
        step_x(20, 1);
        mark(0);
        check(x_sens == 0 && dut.fmax[0] == FX && x_arm, "K2 x_zero after final: count 0, max kept");
        mark(4);
        check(x_sens == 0 && y_sens == 0 && !x_arm && !y_arm &&
              dut.fmax[0] == 0 && dut.fmax[1] == 0, "K3 reset: counts, max and finals cleared");
        step_x(20, 1);
        repeat (6 * CONV) @(posedge clk);
        check(x_tgt == 20 * STEP && !x_arm, "K4 no final: pot at top asks the max reached");
        mark(5);
        check(x_arm && !y_arm, "K5 M: X armed with its max, Y (max 0) not");

        // Position loop. X sits on its max, pot at the top: already there.
        repeat (8 * CONV) @(posedge clk);
        check(x_cmd == 0 && y_cmd == 0, "M1 at the target, and Y not armed: brake");
        set_pots(0, 0);
        repeat (8 * CONV) @(posedge clk);
        check(x_cmd == (dut.pol[0] ? `CFG_MAN_X_PCT : -`CFG_MAN_X_PCT),
              "M2 pot to 0: X drives back at MAN_X_PCT");
        step_x(20, -1);
        repeat (8 * CONV) @(posedge clk);
        check(x_sens == 0 && x_cmd == 0, "M3 back on the target: brake");
        set_pots(FULL, 0);
        repeat (8 * CONV) @(posedge clk);
        check(x_cmd == (dut.pol[0] ? -`CFG_MAN_X_PCT : `CFG_MAN_X_PCT) && y_cmd == 0,
              "M4 pot to the top: X drives forward, Y stays");

        if (fails == 0) $display("PASS");
        else $display("FAILS %0d", fails);
        $finish;
    end
endmodule
