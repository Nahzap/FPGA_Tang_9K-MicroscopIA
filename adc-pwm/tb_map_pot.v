// map_pot: 0 V = reverse 100 %, 1.65 V = 0 %, 3.3 V = forward 100 %.
// Run: iverilog -o tb_map.vvp map_pot.v tb_map_pot.v && vvp tb_map.vvp
`timescale 1ns/1ps
module tb_map_pot;
    reg         clk = 1'b0;
    reg         start = 1'b0;
    reg  [15:0] raw = 16'd0;
    wire        idle;
    wire        fwd, rev;
    wire [10:0] cmp;
    wire [6:0]  pct;
    wire [3:0]  hun, ten, one;
    integer     fail;
    integer     cyc;

    map_pot uut (
        .clk(clk), .start(start), .raw(raw),
        .idle(idle), .fwd(fwd), .rev(rev), .cmp(cmp), .pct(pct),
        .hun(hun), .ten(ten), .one(one)
    );

    always #5 clk = ~clk;

    task kick;
        input [15:0] r;
        begin
            raw   = r;
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            @(posedge clk);
            cyc = 0;
            while (!idle && cyc < 8000) begin
                @(posedge clk);
                cyc = cyc + 1;
            end
            if (!idle) begin
                $display("FAIL timeout raw=%0d cyc=%0d", r, cyc);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        fail = 0;
        repeat (4) @(posedge clk);

        kick(16'd0);
        if (!rev || fwd || cmp < 11'd1300 || pct < 7'd95) begin
            $display("FAIL 0V rev=%0d fwd=%0d cmp=%0d pct=%0d", rev, fwd, cmp, pct);
            fail = fail + 1;
        end else
            $display("PASS 0V reverse cmp=%0d pct=%0d", cmp, pct);

        kick(16'd10813);
        if (fwd || rev || cmp != 11'd0 || pct != 7'd0) begin
            $display("FAIL center fwd=%0d rev=%0d cmp=%0d pct=%0d", fwd, rev, cmp, pct);
            fail = fail + 1;
        end else
            $display("PASS center 0%%");

        kick(16'd21627);
        if (!fwd || rev || cmp < 11'd1300 || pct < 7'd95) begin
            $display("FAIL 3.3V fwd=%0d rev=%0d cmp=%0d pct=%0d", fwd, rev, cmp, pct);
            fail = fail + 1;
        end else
            $display("PASS 3.3V forward cmp=%0d pct=%0d", cmp, pct);

        kick(16'h8000);
        if (!rev || fwd || cmp < 11'd1300) begin
            $display("FAIL neg raw rev=%0d cmp=%0d", rev, cmp);
            fail = fail + 1;
        end else
            $display("PASS neg raw -> reverse");

        kick(16'd10950);
        if (cmp != 11'd0) begin
            $display("FAIL deadband cmp=%0d", cmp);
            fail = fail + 1;
        end else
            $display("PASS deadband");

        if (fail == 0)
            $display("ALL PASS");
        else
            $display("FAILURES %0d", fail);
        $finish;
    end
endmodule
