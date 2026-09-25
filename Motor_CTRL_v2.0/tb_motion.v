`timescale 1ns/1ps
`include "config.vh"
// Both axes on the shared datapath with a motor + Hall model that has
// inertia: it speeds up while driven and coasts after the pins let go.
// X is wired backwards (fwd pins lower the count) to check the learned
// polarity. Each Hall edge is STEP counts.
//   iverilog -DTB_BRAKE_MS=0 ...  runs without the anticipated stop.
`ifndef TB_BRAKE_MS
`define TB_BRAKE_MS 1
`endif
module tb_motion;
    localparam integer CMP_PWR  = `CFG_POWER * `CFG_PWM_PERIOD / 100;
    localparam integer CMP_AUTO = (`CFG_POWER * (`CFG_PWM_PERIOD * 1024 / 100)) >> 10;
    localparam integer PLO      = `CFG_POT_END;
    localparam integer PSPAN    = `CFG_POT_FULL - 2 * `CFG_POT_END;
    localparam [15:0]  P_HALF   = PLO + PSPAN / 2;
    localparam [15:0]  P_QUART  = PLO + PSPAN / 4;
    localparam integer STEP     = (2 * `CFG_HALL_TH) >> `CFG_HALL_SHIFT;
    localparam integer TOL      = `CFG_RESUME * STEP;

    reg clk = 0;
    always #10 clk = ~clk;

    reg conv = 0, tick = 0;
    reg [1:0] mode = 0;
    reg signed [9:0] pwr_a = 0, pwr_b = 0;
    reg x_zero = 0, x_final = 0, y_zero = 0, y_final = 0, clr = 0;
    reg [15:0] pot_x = 16'd10813, pot_y = 16'd10813;
    wire [15:0] xa, xb, ya, yb;
    wire x_fwd, x_rev, x_brake, y_fwd, y_rev, y_brake;
    wire [15:0] x_cmp, y_cmp;
    wire signed [9:0] x_rep, y_rep;
    wire [19:0] x_sens, y_sens, x_tgt, y_tgt;
    wire x_arm, y_arm, x_gate, y_gate;

    // conv every 50 clocks and 1 ms = 1000 clocks here: shorter filter and stall.
    motion #(.STALL_MS(20), .POT_FILT(6), .BRAKE_MS(`TB_BRAKE_MS)) dut (
        .clk(clk), .conv(conv), .tick(tick), .mode(mode),
        .pwr_a(pwr_a), .pwr_b(pwr_b), .inv_x(1'b0), .inv_y(1'b0),
        .x_zero(x_zero), .x_final(x_final), .y_zero(y_zero), .y_final(y_final),
        .clr(clr), .lock(1'b0), .pot_x(pot_x), .pot_y(pot_y),
        .xa(xa), .xb(xb), .ya(ya), .yb(yb),
        .x_fwd(x_fwd), .x_rev(x_rev), .x_brake(x_brake), .x_cmp(x_cmp),
        .x_rep(x_rep), .x_sens(x_sens), .x_tgt(x_tgt), .x_moved(),
        .x_gate(x_gate), .x_arm(x_arm), .x_hlo(), .x_hhi(),
        .y_fwd(y_fwd), .y_rev(y_rev), .y_brake(y_brake), .y_cmp(y_cmp),
        .y_rep(y_rep), .y_sens(y_sens), .y_tgt(y_tgt), .y_moved(),
        .y_gate(y_gate), .y_arm(y_arm), .y_hlo(), .y_hhi()
    );

    // Motor + guide, position in 1/U of a Hall edge, updated every 50 clocks.
    // A DC motor has one mechanical time constant: driven, the speed closes
    // 1/20 of the gap to VMAX (about 8 edges per ms) per update; braked
    // (winding shorted) it loses 1/20 per update, so it coasts about
    // speed * 1 ms. Free: 1/80. Friction takes the last bit. Ends at 0 and LIM.
    localparam integer U = 1024, VMAX = 400, VHAND = 342;
    localparam integer LIM_X = 250, LIM_Y = 133;
    localparam integer FX = LIM_X * STEP, FY = LIM_Y * STEP;
    integer ux = 0, uy = 0, vx = 0, vy = 0, dx, dy;
    integer hx = 0, hy = 0;       // hand motion, -1/0/+1
    integer cc = 0, sc = 0, tc = 0;
    wire [31:0] px = ux / U, py = uy / U;
    function [15:0] lvl;
        input b;
        lvl = b ? 16'd12600 : 16'd9000;
    endfunction
    // Gray phase 00, 01, 11, 10 as the position rises (a = bit1, b = bit0).
    assign xa = lvl((px % 4) == 2 || (px % 4) == 3);
    assign xb = lvl((px % 4) == 1 || (px % 4) == 2);
    assign ya = lvl((py % 4) == 2 || (py % 4) == 3);
    assign yb = lvl((py % 4) == 1 || (py % 4) == 2);

    function integer vnext;
        input integer v, dir, brk;
        integer a, d;
        begin
            if (dir != 0) begin
                v = v + (dir * VMAX - v) / 20;
            end else begin
                a = (v < 0) ? -v : v;
                d = brk ? a / 20 : a / 80;
                if (d < 4) d = 4;
                a = (a > d) ? a - d : 0;
                v = (v < 0) ? -a : a;
            end
            vnext = v;
        end
    endfunction

    // Pot noise: +-100 codes around pot_base on every conversion.
    reg        noisy = 0;
    reg [15:0] pot_base = 0;
    integer    nz;

    always @(posedge clk) begin
        conv <= 1'b0;
        tick <= 1'b0;
        cc = cc + 1;
        if (cc == 50) begin
            cc = 0;
            conv <= 1'b1;
            if (noisy) begin
                nz = $random % 101;
                pot_x <= pot_base + nz;
            end
        end
        tc = tc + 1;
        if (tc == 1000) begin
            tc = 0;
            tick <= 1'b1;
        end
        sc = sc + 1;
        if (sc == 50) begin
            sc = 0;
            dx = x_fwd ? -1 : (x_rev ? 1 : 0);
            dy = y_fwd ? 1 : (y_rev ? -1 : 0);
            vx = (hx != 0) ? hx * VHAND : vnext(vx, dx, x_brake);
            vy = (hy != 0) ? hy * VHAND : vnext(vy, dy, y_brake);
            ux = ux + vx;
            uy = uy + vy;
            if (ux < 0)          begin ux = 0;         vx = 0; end
            if (ux > LIM_X * U)  begin ux = LIM_X * U; vx = 0; end
            if (uy < 0)          begin uy = 0;         vy = 0; end
            if (uy > LIM_Y * U)  begin uy = LIM_Y * U; vy = 0; end
        end
    end

    // Power seen on X while seeking: only CFG_POWER, + or -.
    reg saw_pos = 0, saw_neg = 0, saw_odd = 0;
    always @(posedge clk)
        if (mode == 2'd0 && (x_fwd || x_rev)) begin
            if (x_cmp == CMP_PWR && x_rep == `CFG_POWER)
                saw_pos <= 1'b1;
            else if (x_cmp == CMP_PWR && x_rep == -`CFG_POWER)
                saw_neg <= 1'b1;
            else
                saw_odd <= 1'b1;
        end

    // Drive reversals on X: + then - (or - then +) is one. Hunting adds them.
    integer revs = 0;
    reg     had = 0, last_fwd = 0;
    always @(posedge clk)
        if (x_fwd || x_rev) begin
            if (had && (x_fwd != last_fwd))
                revs = revs + 1;
            had      = 1'b1;
            last_fwd = x_fwd;
        end
`ifdef TB_TRACE
    reg [2:0] pins_d = 0;
    always @(posedge clk) begin
        pins_d <= {x_fwd, x_rev, x_brake};
        if ({x_fwd, x_rev, x_brake} != pins_d)
            $display("  t=%0d fwd%b rev%b brk%b edge=%0d v=%0d sens=%0d tgt=%0d vel=%0d stop=%0d",
                     $time / 20, x_fwd, x_rev, x_brake, px, vx, x_sens, x_tgt,
                     dut.vel[0], dut.stop_r);
    end
`endif

    integer fails = 0;
    task wait_clk;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask
    task near;
        input [19:0] got;
        input integer want;
        input [8*16-1:0] what;
        begin
            if ((got > want + TOL) || (got + TOL < want)) begin
                $display("FAIL %0s got=%0d want=%0d", what, got, want);
                fails = fails + 1;
            end else
                $display("ok   %0s = %0d (want %0d)", what, got, want);
        end
    endtask
    // Move X with the pot, then: no reversal on the way, arrived, and still.
    task settle_x;
        input [15:0] pot;
        input integer want;
        input [8*16-1:0] what;
        integer k, moves;
        begin
            revs  = 0;
            had   = 1'b0;
            pot_x = pot;
            wait_clk(400000);
            near(x_sens, want, what);
            if (revs != 0) begin
                $display("FAIL %0s: %0d reversals (hunting)", what, revs);
                fails = fails + 1;
            end
            moves = 0;
            for (k = 0; k < 100000; k = k + 1) begin
                @(posedge clk);
                if (x_fwd || x_rev)
                    moves = moves + 1;
            end
            if (moves != 0) begin
                $display("FAIL %0s: still driving %0d clocks", what, moves);
                fails = fails + 1;
            end
        end
    endtask

    initial begin
        $display("     1 step = %0d counts, gate %0d, resume %0d, brake %0d ms",
                 STEP, `CFG_GATE * STEP, TOL, `TB_BRAKE_MS);
        wait_clk(2000);
        // Not calibrated: no drive, PotA shows the raw pot code.
        if (x_fwd || x_rev || y_fwd || y_rev) begin
            $display("FAIL drive before marks");
            fails = fails + 1;
        end
        near(x_tgt, 0, "PotA no max yet");

        // X: zero at the origin, hand to the far end, final.
        @(negedge clk) x_zero = 1'b1; @(negedge clk) x_zero = 1'b0;
        hx = 1;
        wait_clk(LIM_X * 150 + 2000);
        hx = 0;
        wait_clk(2000);
        near(x_sens, FX, "X at far end");
        near(x_tgt, FX / 2, "PotA max seen/2");
        @(negedge clk) x_final = 1'b1; @(negedge clk) x_final = 1'b0;
        wait_clk(200);
        if (y_fwd || y_rev) begin
            $display("FAIL Y moved on x_final");
            fails = fails + 1;
        end

        // Half pot. X is wired backwards; it must learn that on the way.
        pot_x = P_HALF;
        wait_clk(1200000);
        near(x_sens, FX / 2, "X half");
        if (x_fwd || x_rev) begin
            $display("FAIL X still driving at half");
            fails = fails + 1;
        end
        if (x_brake != (`CFG_STOP_BRAKE != 0)) begin
            $display("FAIL X stop brake=%b", x_brake);
            fails = fails + 1;
        end
        near(x_tgt, FX / 2, "PotA half");

        // Noisy pot at rest: no drive at all.
        pot_base = P_HALF;
        noisy = 1;
        wait_clk(100000);
        begin : quiet
            integer k, moves;
            moves = 0;
            for (k = 0; k < 400000; k = k + 1) begin
                @(posedge clk);
                if (x_fwd || x_rev)
                    moves = moves + 1;
            end
            if (moves != 0) begin
                $display("FAIL noisy pot drove X for %0d clocks", moves);
                fails = fails + 1;
            end else
                $display("ok   noisy pot +-100 codes, X quiet");
        end
        noisy = 0;

        // Long moves at full speed and short nudges: arrive without hunting.
        settle_x(`CFG_POT_FULL, FX, "X full");
        near(x_tgt, FX, "PotA full");
        pot_x = `CFG_POT_FULL - `CFG_POT_END / 2;
        wait_clk(100000);
        near(x_tgt, FX, "PotA top end");
        settle_x(P_QUART, FX / 4, "X quarter");
        settle_x(P_QUART + 4 * STEP, FX / 4 + 4 * STEP, "X nudge +4");
        settle_x(P_QUART + 1 * STEP, FX / 4 + 1 * STEP, "X nudge -3");
        settle_x(P_HALF, FX / 2, "X half again");
        settle_x(16'd0, 0, "X zero");
        $display("ok   no hunting on the X moves");

        // Y: its own marks, its own span.
        @(negedge clk) y_zero = 1'b1; @(negedge clk) y_zero = 1'b0;
        hy = 1;
        wait_clk(LIM_Y * 150 + 2000);
        hy = 0;
        wait_clk(2000);
        @(negedge clk) y_final = 1'b1; @(negedge clk) y_final = 1'b0;
        near(y_sens, FY, "Y at far end");
        pot_y = P_QUART;
        wait_clk(800000);
        near(y_sens, FY / 4, "Y quarter");
        near(x_sens, 0, "X stays");
        if (!saw_pos || !saw_neg || saw_odd) begin
            $display("FAIL power +%b -%b other=%b (want cmp %0d)",
                     saw_pos, saw_neg, saw_odd, CMP_PWR);
            fails = fails + 1;
        end else
            $display("ok   one power: +/-%0d %% = cmp %0d", `CFG_POWER, CMP_PWR);

        // AUTO and BRAKE still use the same port.
        mode = 2'd1;
        pwr_a = `CFG_POWER;
        wait_clk(200);
        if (x_cmp != CMP_AUTO || !x_fwd) begin
            $display("FAIL auto cmp=%0d fwd=%b", x_cmp, x_fwd);
            fails = fails + 1;
        end
        mode = 2'd2;
        wait_clk(200);
        if (!x_brake || x_cmp != 0) begin
            $display("FAIL brake");
            fails = fails + 1;
        end
        mode = 2'd0;
        pwr_a = 0;

        @(negedge clk) clr = 1'b1; @(negedge clk) clr = 1'b0;
        wait_clk(200);
        if (x_arm || y_arm || x_sens != 0 || y_sens != 0) begin
            $display("FAIL reset");
            fails = fails + 1;
        end

        if (fails == 0)
            $display("PASS");
        else
            $display("FAILS %0d", fails);
        $finish;
    end
endmodule
