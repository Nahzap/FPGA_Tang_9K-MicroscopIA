// enc_pos: live ±100 %, stretch, stall lock. STALL=8 for a short bench.
// Run: iverilog -o tb_enc.vvp enc_pos.v tb_enc_pos.v && vvp tb_enc.vvp
`timescale 1ns/1ps
module tb_enc_pos;
    localparam [15:0] HI = 16'd20000;
    localparam [15:0] LO = 16'd0;

    reg         clk = 1'b0;
    reg         sample = 1'b0;
    reg  [15:0] raw_a = LO;
    reg  [15:0] raw_b = LO;
    reg         cmd_fwd = 1'b0;
    reg         cmd_rev = 1'b0;
    reg         cmd_on  = 1'b0;
    wire        moved, lock_p, lock_n, pos_neg;
    wire [6:0]  pct;
    wire [3:0]  hun, ten, one;
    integer     fail;
    integer     i;

    enc_pos #(.STALL(8)) uut (
        .clk(clk), .sample(sample),
        .raw_a(raw_a), .raw_b(raw_b),
        .cmd_fwd(cmd_fwd), .cmd_rev(cmd_rev), .cmd_on(cmd_on),
        .moved(moved), .lock_p(lock_p), .lock_n(lock_n),
        .pos_neg(pos_neg), .pct(pct),
        .hun(hun), .ten(ten), .one(one)
    );

    always #5 clk = ~clk;

    task set_ab;
        input a;
        input b;
        begin
            raw_a = a ? HI : LO;
            raw_b = b ? HI : LO;
        end
    endtask

    task beat;
        begin
            @(negedge clk);
            sample = 1'b1;
            @(posedge clk);
            @(negedge clk);
            sample = 1'b0;
            repeat (10) @(posedge clk);
            #1;
        end
    endtask

    task step_plus;
        begin
            set_ab(1'b0, 1'b1); beat;
            set_ab(1'b1, 1'b1); beat;
            set_ab(1'b1, 1'b0); beat;
            set_ab(1'b0, 1'b0); beat;
        end
    endtask

    task step_minus;
        begin
            set_ab(1'b1, 1'b0); beat;
            set_ab(1'b1, 1'b1); beat;
            set_ab(1'b0, 1'b1); beat;
            set_ab(1'b0, 1'b0); beat;
        end
    endtask

    initial begin
        fail = 0;
        repeat (4) @(posedge clk);

        set_ab(1'b0, 1'b0);
        beat;
        if (pct != 7'd0 || hun != 4'd0 || ten != 4'd0 || one != 4'd0 || pos_neg || lock_p || lock_n) begin
            $display("FAIL reset pct=%0d %0d%0d%0d neg=%0d lp=%0d ln=%0d",
                     pct, hun, ten, one, pos_neg, lock_p, lock_n);
            fail = fail + 1;
        end else
            $display("PASS reset +000");

        step_plus;
        if (pct != 7'd100 || hun != 4'd1 || pos_neg || !moved) begin
            $display("FAIL first + pct=%0d hun=%0d neg=%0d mv=%0d", pct, hun, pos_neg, moved);
            fail = fail + 1;
        end else
            $display("PASS first + -> +100");

        step_plus;
        if (pct != 7'd100 || pos_neg) begin
            $display("FAIL stretch + pct=%0d", pct);
            fail = fail + 1;
        end else
            $display("PASS stretch stays +100");

        step_minus;
        if (pct != 7'd50 || pos_neg) begin
            $display("FAIL mid+ pct=%0d neg=%0d (want 50)", pct, pos_neg);
            fail = fail + 1;
        end else
            $display("PASS back to +050");

        step_minus;
        if (pct != 7'd0 || pos_neg) begin
            $display("FAIL center pct=%0d neg=%0d", pct, pos_neg);
            fail = fail + 1;
        end else
            $display("PASS center +000");

        step_minus;
        if (pct != 7'd100 || !pos_neg) begin
            $display("FAIL first - pct=%0d neg=%0d", pct, pos_neg);
            fail = fail + 1;
        end else
            $display("PASS first - -> -100");

        cmd_fwd = 1'b1;
        cmd_on  = 1'b1;
        cmd_rev = 1'b0;
        set_ab(1'b0, 1'b0);
        for (i = 0; i < 10; i = i + 1)
            beat;
        if (!lock_p) begin
            $display("FAIL stall lock_p=%0d lock_n=%0d", lock_p, lock_n);
            fail = fail + 1;
        end else
            $display("PASS stall lock_p");

        cmd_fwd = 1'b0;
        cmd_rev = 1'b1;
        cmd_on  = 1'b1;
        for (i = 0; i < 10; i = i + 1)
            beat;
        if (!lock_n) begin
            $display("FAIL stall lock_n=%0d", lock_n);
            fail = fail + 1;
        end else
            $display("PASS stall lock_n");

        cmd_on  = 1'b0;
        cmd_rev = 1'b0;
        step_plus;
        if (!moved) begin
            $display("FAIL edge should set moved");
            fail = fail + 1;
        end else
            $display("PASS edge after stall still moves");

        if (fail == 0)
            $display("ALL PASS");
        else
            $display("FAILURES %0d", fail);
        $finish;
    end
endmodule
