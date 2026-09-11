// pwr_lim: explore passes; locked taper and cut; opposite sense free.
// Run: iverilog -o tb_lim.vvp pwr_lim.v tb_pwr_lim.v && vvp tb_lim.vvp
`timescale 1ns/1ps
module tb_pwr_lim;
    reg         fwd_i, rev_i, pos_neg, lock_p, lock_n;
    reg  [10:0] cmp_i;
    reg  [6:0]  pct;
    wire        fwd_o, rev_o;
    wire [10:0] cmp_o;
    integer     fail;

    pwr_lim uut (
        .fwd_i(fwd_i), .rev_i(rev_i), .cmp_i(cmp_i),
        .pct(pct), .pos_neg(pos_neg),
        .lock_p(lock_p), .lock_n(lock_n),
        .fwd_o(fwd_o), .rev_o(rev_o), .cmp_o(cmp_o)
    );

    initial begin
        fail = 0;
        fwd_i = 1'b1; rev_i = 1'b0; cmp_i = 11'd1000;
        pct = 7'd100; pos_neg = 1'b0;
        lock_p = 1'b0; lock_n = 1'b0;
        #1;
        if (!fwd_o || rev_o || cmp_o != 11'd1000) begin
            $display("FAIL explore +100 cmp=%0d fwd=%0d", cmp_o, fwd_o);
            fail = fail + 1;
        end else
            $display("PASS explore +100 pot intact");

        lock_p = 1'b1;
        pct = 7'd100;
        #1;
        if (fwd_o || rev_o || cmp_o != 11'd0) begin
            $display("FAIL lock +100 fwd cmp=%0d fwd=%0d rev=%0d", cmp_o, fwd_o, rev_o);
            fail = fail + 1;
        end else
            $display("PASS lock +100 cuts fwd");

        pct = 7'd90;
        #1;
        if (!fwd_o || rev_o || cmp_o != 11'd500) begin
            $display("FAIL lock +90 taper cmp=%0d (want 500)", cmp_o);
            fail = fail + 1;
        end else
            $display("PASS lock +90 taper half");

        fwd_i = 1'b0; rev_i = 1'b1; cmp_i = 11'd1000;
        pct = 7'd100; pos_neg = 1'b0; lock_p = 1'b1;
        #1;
        if (fwd_o || !rev_o || cmp_o != 11'd1000) begin
            $display("FAIL leave +end rev cmp=%0d rev=%0d", cmp_o, rev_o);
            fail = fail + 1;
        end else
            $display("PASS leave +end reverse intact");

        fwd_i = 1'b0; rev_i = 1'b1; cmp_i = 11'd800;
        pct = 7'd100; pos_neg = 1'b1;
        lock_p = 1'b0; lock_n = 1'b1;
        #1;
        if (fwd_o || rev_o || cmp_o != 11'd0) begin
            $display("FAIL lock -100 rev cmp=%0d", cmp_o);
            fail = fail + 1;
        end else
            $display("PASS lock -100 cuts rev");

        pct = 7'd90;
        #1;
        if (fwd_o || !rev_o || cmp_o != 11'd400) begin
            $display("FAIL lock -90 taper cmp=%0d (want 400)", cmp_o);
            fail = fail + 1;
        end else
            $display("PASS lock -90 taper half");

        fwd_i = 1'b1; rev_i = 1'b0; cmp_i = 11'd800;
        pct = 7'd100; pos_neg = 1'b1; lock_n = 1'b1;
        #1;
        if (!fwd_o || rev_o || cmp_o != 11'd800) begin
            $display("FAIL leave -end fwd cmp=%0d", cmp_o);
            fail = fail + 1;
        end else
            $display("PASS leave -end forward intact");

        if (fail == 0)
            $display("ALL PASS");
        else
            $display("FAILURES %0d", fail);
        $finish;
    end
endmodule
