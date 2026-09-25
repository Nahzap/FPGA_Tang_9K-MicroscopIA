// dbg_uart: one X line and one Y line at a short DIV/GAP.
// Run: iverilog -o tb_dbg.vvp dbg_uart.v tb_dbg_uart.v && vvp tb_dbg.vvp
`timescale 1ns/1ps
module tb_dbg_uart;
    reg         clk = 1'b0;
    reg         paused = 1'b0;
    reg         x_fwd = 1'b1;
    reg         x_rev = 1'b0;
    reg         y_fwd = 1'b0;
    reg         y_rev = 1'b1;
    reg  [6:0]  x_pct = 7'd100;
    reg  [6:0]  y_pct = 7'd16;
    reg  [10:0] x_cmp = 11'd81;
    reg  [10:0] y_cmp = 11'd0;
    reg         x_eff = 1'b1;
    reg         y_eff = 1'b0;
    reg         x_moved = 1'b0;
    reg         y_moved = 1'b0;
    reg         x_skip = 1'b0;
    reg         y_skip = 1'b0;
    reg         x_lp = 1'b0;
    reg         x_ln = 1'b0;
    reg         y_lp = 1'b0;
    reg         y_ln = 1'b1;
    reg  [3:0]  x_sth = 4'd1;
    reg  [3:0]  x_shu = 4'd0;
    reg  [3:0]  x_ste = 4'd0;
    reg  [3:0]  x_son = 4'd0;
    reg  [3:0]  y_sth = 4'd0;
    reg  [3:0]  y_shu = 4'd0;
    reg  [3:0]  y_ste = 4'd0;
    reg  [3:0]  y_son = 4'd0;
    reg  [15:0] x_a = 16'h2A1F;
    reg  [15:0] x_b = 16'h0010;
    reg  [15:0] y_a = 16'h0000;
    reg  [15:0] y_b = 16'h55AA;
    wire        tx;
    integer     fail, nbits, i;
    reg [7:0]   ch;
    reg [8*80-1:0] line;

    dbg_uart #(.DIV(4), .GAP(30)) uut (
        .clk(clk), .paused(paused),
        .x_fwd(x_fwd), .x_rev(x_rev), .y_fwd(y_fwd), .y_rev(y_rev),
        .x_pct(x_pct), .y_pct(y_pct), .x_cmp(x_cmp), .y_cmp(y_cmp),
        .x_eff(x_eff), .y_eff(y_eff),
        .x_moved(x_moved), .y_moved(y_moved),
        .x_skip(x_skip), .y_skip(y_skip),
        .x_lp(x_lp), .x_ln(x_ln), .y_lp(y_lp), .y_ln(y_ln),
        .x_sth(x_sth), .x_shu(x_shu), .x_ste(x_ste), .x_son(x_son),
        .y_sth(y_sth), .y_shu(y_shu), .y_ste(y_ste), .y_son(y_son),
        .x_a(x_a), .x_b(x_b), .y_a(y_a), .y_b(y_b),
        .tx(tx)
    );

    always #5 clk = ~clk;

    task recv;
        begin
            nbits = 0;
            while (tx !== 1'b0 && nbits < 20000) begin
                @(posedge clk);
                nbits = nbits + 1;
            end
            if (tx !== 1'b0) begin
                $display("FAIL no start");
                fail = fail + 1;
                ch = 8'd0;
            end else begin
                repeat (6) @(posedge clk);
                ch = 8'd0;
                for (i = 0; i < 8; i = i + 1) begin
                    ch[i] = tx;
                    repeat (4) @(posedge clk);
                end
            end
        end
    endtask

    initial begin
        fail = 0;
        line = 0;
        repeat (4) @(posedge clk);
        x_moved = 1'b1;
        @(posedge clk);
        x_moved = 1'b0;

        recv;
        if (ch != "X") begin
            $display("FAIL first byte %0d", ch);
            fail = fail + 1;
        end else
            $display("PASS starts with X");

        line[7:0] = ch;
        begin : grab
            integer k;
            for (k = 1; k < 80; k = k + 1) begin
                recv;
                line = {line[8*79-1:0], ch};
                if (ch == 8'd10)
                    disable grab;
            end
        end
        $display("LINE %0s", line);
        if (ch != 8'd10) begin
            $display("FAIL no newline");
            fail = fail + 1;
        end else
            $display("PASS newline");

        recv;
        if (ch != "Y") begin
            $display("FAIL second axis %0d", ch);
            fail = fail + 1;
        end else
            $display("PASS second line Y");

        if (fail == 0)
            $display("ALL PASS");
        else
            $display("FAILURES %0d", fail);
        $finish;
    end
endmodule
