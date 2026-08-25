// MPU9250 I2C slave (0x68) + imu_mpu with short waits.
`timescale 1ns/1ps
module tb_i2c_mpu;
    reg         clk = 1'b0;
    reg         start = 1'b0;
    wire        idle, ready, sample_done;
    wire [1:0]  status;
    wire [7:0]  whoami;
    wire [6:0]  dev_used;
    wire [15:0] ax, ay, az, gx, gy, gz;
    wire        scl_oe, sda_oe;
    wire        slv_oe;
    integer     fail, cyc;

    wire scl = scl_oe ? 1'b0 : 1'b1;
    wire sda = (sda_oe | slv_oe) ? 1'b0 : 1'b1;

    imu_mpu #(
        .T_PWR  (80),
        .T_WAKE (40),
        .HALF   (8)
    ) uut (
        .clk(clk), .start(start), .paused(1'b0),
        .idle(idle), .ready(ready), .sample_done(sample_done),
        .status(status), .whoami(whoami), .dev_used(dev_used),
        .ax(ax), .ay(ay), .az(az), .gx(gx), .gy(gy), .gz(gz),
        .scl_oe(scl_oe), .sda_oe(sda_oe),
        .scl_i(scl), .sda_i(sda)
    );

    mpu_i2c_slave slv (
        .clk(clk),
        .scl(scl),
        .sda_in(sda),
        .sda_oe(slv_oe)
    );

    always #5 clk = ~clk;

    initial begin
        fail = 0;
        cyc = 0;
        while (!ready && cyc < 400000) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        $display("ready=%b whoami=%h status=%0d cycles=%0d idle=%b",
            ready, whoami, status, cyc, idle);
        if (!ready || whoami !== 8'h71 || status !== 2'd1) begin
            $display("FAIL WHO_AM_I");
            fail = fail + 1;
        end
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;
        cyc = 0;
        while (!sample_done && cyc < 400000) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        $display("sample_done=%b ax=%h ay=%h az=%h gx=%h gy=%h gz=%h cyc=%0d",
            sample_done, ax, ay, az, gx, gy, gz, cyc);
        if (!sample_done) begin
            $display("FAIL no sample");
            fail = fail + 1;
        end
        if (ax !== 16'h4000) begin $display("FAIL ax %h", ax); fail = fail + 1; end
        if (ay !== 16'h0000) begin $display("FAIL ay %h", ay); fail = fail + 1; end
        if (az !== 16'hC000) begin $display("FAIL az %h", az); fail = fail + 1; end
        if (gx !== 16'h0083) begin $display("FAIL gx %h", gx); fail = fail + 1; end
        if (gy !== 16'h0000) begin $display("FAIL gy %h", gy); fail = fail + 1; end
        if (gz !== 16'hFF7D) begin $display("FAIL gz %h", gz); fail = fail + 1; end
        if (fail == 0)
            $display("ALL PASS");
        else
            $display("%0d FAIL", fail);
        $finish;
    end
endmodule

module mpu_i2c_slave (
    input  wire clk,
    input  wire scl,
    input  wire sda_in,
    output reg  sda_oe
);
    localparam [3:0] ST_IDLE = 4'd0;
    localparam [3:0] ST_RX   = 4'd1;
    localparam [3:0] ST_AF   = 4'd2;
    localparam [3:0] ST_AH   = 4'd3;
    localparam [3:0] ST_AR   = 4'd4;
    localparam [3:0] ST_TX   = 4'd5;
    localparam [3:0] ST_MH   = 4'd6;
    localparam [3:0] ST_MR   = 4'd7;

    localparam [1:0] ROL_ADDR = 2'd0;
    localparam [1:0] ROL_PTR  = 2'd1;
    localparam [1:0] ROL_DATA = 2'd2;

    reg        scl_d = 1'b1;
    reg        sda_d = 1'b1;
    reg [3:0]  st    = ST_IDLE;
    reg [2:0]  biti  = 3'd0;
    reg [7:0]  sh    = 8'd0;
    reg [7:0]  tx    = 8'd0;
    reg [1:0]  role  = ROL_ADDR;
    reg        rw    = 1'b0;
    reg        mack  = 1'b1;
    reg [7:0]  ptr   = 8'd0;
    reg [7:0]  mem [0:255];
    integer    i;

    wire scl_rise = scl & ~scl_d;
    wire scl_fall = ~scl & scl_d;
    wire sta      = scl & sda_d & ~sda_in;
    wire sto      = scl & ~sda_d & sda_in;

    initial begin
        sda_oe = 1'b0;
        for (i = 0; i < 256; i = i + 1)
            mem[i] = 8'd0;
        mem[8'h75] = 8'h71;
        mem[8'h3B] = 8'h40;
        mem[8'h3C] = 8'h00;
        mem[8'h3D] = 8'h00;
        mem[8'h3E] = 8'h00;
        mem[8'h3F] = 8'hC0;
        mem[8'h40] = 8'h00;
        mem[8'h43] = 8'h00;
        mem[8'h44] = 8'h83;
        mem[8'h45] = 8'h00;
        mem[8'h46] = 8'h00;
        mem[8'h47] = 8'hFF;
        mem[8'h48] = 8'h7D;
    end

    always @(posedge clk) begin
        scl_d <= scl;
        sda_d <= sda_in;

        if (sta) begin
            st     <= ST_RX;
            biti   <= 3'd0;
            role   <= ROL_ADDR;
            sda_oe <= 1'b0;
        end else if (sto) begin
            st     <= ST_IDLE;
            sda_oe <= 1'b0;
        end else begin
            case (st)
                ST_RX: begin
                    if (scl_rise) begin
                        sh <= {sh[6:0], sda_in};
                        if (biti == 3'd7)
                            st <= ST_AF;
                        else
                            biti <= biti + 3'd1;
                    end
                end
                ST_AF: begin
                    if (scl_fall) begin
                        if (role == ROL_ADDR) begin
                            if (sh[7:1] == 7'h68) begin
                                rw     <= sh[0];
                                sda_oe <= 1'b1;
                                st     <= ST_AH;
                            end else begin
                                sda_oe <= 1'b0;
                                st     <= ST_IDLE;
                            end
                        end else begin
                            sda_oe <= 1'b1;
                            st     <= ST_AH;
                            if (role == ROL_PTR)
                                ptr <= sh;
                            else begin
                                mem[ptr] <= sh;
                                ptr      <= ptr + 8'd1;
                            end
                        end
                    end
                end
                ST_AH: begin
                    if (scl_rise)
                        st <= ST_AR;
                end
                ST_AR: begin
                    if (scl_fall) begin
                        if (role == ROL_ADDR && rw) begin
                            tx     <= mem[ptr];
                            sda_oe <= ~mem[ptr][7];
                            ptr    <= ptr + 8'd1;
                            biti   <= 3'd0;
                            st     <= ST_TX;
                        end else begin
                            sda_oe <= 1'b0;
                            biti   <= 3'd0;
                            st     <= ST_RX;
                            if (role == ROL_ADDR)
                                role <= ROL_PTR;
                            else if (role == ROL_PTR)
                                role <= ROL_DATA;
                        end
                    end
                end
                ST_TX: begin
                    if (scl_fall) begin
                        if (biti == 3'd7) begin
                            sda_oe <= 1'b0;
                            st     <= ST_MH;
                        end else begin
                            sda_oe <= ~tx[6];
                            tx     <= {tx[6:0], 1'b0};
                            biti   <= biti + 3'd1;
                        end
                    end
                end
                ST_MH: begin
                    if (scl_rise)
                        mack <= sda_in;
                    if (scl_fall) begin
                        if (!mack) begin
                            tx     <= mem[ptr];
                            sda_oe <= ~mem[ptr][7];
                            ptr    <= ptr + 8'd1;
                            biti   <= 3'd0;
                            st     <= ST_TX;
                        end else begin
                            sda_oe <= 1'b0;
                            st     <= ST_IDLE;
                        end
                    end
                end
                default: st <= ST_IDLE;
            endcase
        end
    end
endmodule
