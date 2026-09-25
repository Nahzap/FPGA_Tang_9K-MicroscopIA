// spd_ctl: pot raises PWM, fast edges cut it, a lock stops that sense.
// Run: iverilog -o tb_spd.vvp spd_ctl.v tb_spd_ctl.v && vvp tb_spd.vvp
`timescale 1ns/1ps
module tb_spd_ctl;
    reg        clk = 1'b0;
    reg        sample = 1'b0;
    reg        pot_fwd = 1'b0;
    reg        pot_rev = 1'b0;
    reg  [6:0] pot_pct = 7'd0;
    reg        moved = 1'b0;
    reg        skip = 1'b0;
    reg        lock_p = 1'b0;
    reg        lock_n = 1'b0;
    wire       fwd, rev, effort;
    wire [10:0] cmp;
    wire [3:0] th, hu, te, on;
    integer    fail, i, peak;

    spd_ctl uut (
        .clk(clk), .sample(sample),
        .pot_fwd(pot_fwd), .pot_rev(pot_rev), .pot_pct(pot_pct),
        .moved(moved), .skip(skip),
        .lock_p(lock_p), .lock_n(lock_n),
        .fwd(fwd), .rev(rev), .cmp(cmp), .effort(effort),
        .spd_th(th), .spd_hu(hu), .spd_te(te), .spd_on(on)
    );

    always #5 clk = ~clk;

    task beat;
        begin
            @(negedge clk);
            sample = 1'b1;
            @(posedge clk);
            @(negedge clk);
            sample = 1'b0;
        end
    endtask

    initial begin
        fail = 0;
        repeat (2) @(posedge clk);

        pot_fwd = 1'b0;
        pot_rev = 1'b0;
        pot_pct = 7'd0;
        beat;
        if (cmp != 11'd0 || fwd || rev) begin
            $display("FAIL center cmp=%0d", cmp);
            fail = fail + 1;
        end else
            $display("PASS center stop");

        pot_fwd = 1'b1;
        pot_pct = 7'd100;
        peak = 0;
        for (i = 0; i < 80; i = i + 1) begin
            moved = 1'b0;
            beat;
            if (cmp > peak)
                peak = cmp;
        end
        if (peak < 200 || peak > 270 || !fwd) begin
            $display("FAIL pot PWM peak=%0d fwd=%0d (want 200..270)", peak, fwd);
            fail = fail + 1;
        end else
            $display("PASS pot raises PWM peak=%0d", peak);

        for (i = 0; i < 80; i = i + 1) begin
            moved = 1'b1;
            beat;
        end
        if (cmp > 11'd200) begin
            $display("FAIL fast edges left cmp=%0d", cmp);
            fail = fail + 1;
        end else
            $display("PASS fast edges cut PWM cmp=%0d", cmp);

        moved = 1'b0;
        lock_p = 1'b1;
        beat;
        if (cmp != 11'd0 || fwd || rev) begin
            $display("FAIL lock_p cmp=%0d fwd=%0d", cmp, fwd);
            fail = fail + 1;
        end else
            $display("PASS end-stop cuts forward");

        lock_p = 1'b0;
        pot_fwd = 1'b0;
        pot_rev = 1'b1;
        for (i = 0; i < 40; i = i + 1)
            beat;
        lock_n = 1'b1;
        beat;
        if (cmp != 11'd0 || fwd || rev) begin
            $display("FAIL lock_n cmp=%0d rev=%0d", cmp, rev);
            fail = fail + 1;
        end else
            $display("PASS end-stop cuts reverse");

        if (fail == 0)
            $display("ALL PASS");
        else
            $display("FAILURES %0d", fail);
        $finish;
    end
endmodule
