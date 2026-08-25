// MPU9250 / MPU9255 / MPU6500 on GY-91. I2C 0x68 then 0x69.
// Wake PWR_MGMT_1, WHO_AM_I, then 14-byte burst from ACCEL_XOUT_H (0x3B).
module imu_mpu #(
    parameter integer T_PWR  = 2700000,
    parameter integer T_WAKE = 270000,
    parameter integer HALF   = 135
) (
    input  wire        clk,
    input  wire        start,
    input  wire        paused,
    output wire        idle,
    output wire        ready,
    output reg         sample_done,
    output reg  [1:0]  status,
    output reg  [7:0]  whoami,
    output reg  [6:0]  dev_used,
    output reg  [15:0] ax,
    output reg  [15:0] ay,
    output reg  [15:0] az,
    output reg  [15:0] gx,
    output reg  [15:0] gy,
    output reg  [15:0] gz,
    output wire        scl_oe,
    output wire        sda_oe,
    input  wire        scl_i,
    input  wire        sda_i
);
    localparam [2:0] ST_PWR   = 3'd0;
    localparam [2:0] ST_WAKE  = 3'd1;
    localparam [2:0] ST_WAIT  = 3'd2;
    localparam [2:0] ST_WHO   = 3'd3;
    localparam [2:0] ST_IDLE  = 3'd4;
    localparam [2:0] ST_READ  = 3'd5;
    localparam [2:0] ST_RETRY = 3'd6;

    localparam [1:0] IMU_WAIT = 2'd0;
    localparam [1:0] IMU_OK   = 2'd1;
    localparam [1:0] IMU_NAK  = 2'd2;
    localparam [1:0] IMU_ID   = 2'd3;

    localparam [7:0] REG_PWR = 8'h6B;
    localparam [7:0] REG_WHO = 8'h75;
    localparam [7:0] REG_AX  = 8'h3B;

    reg [2:0]  state   = ST_PWR;
    reg [23:0] tcnt    = 24'd0;
    reg        i2c_go  = 1'b0;
    reg        cmd_rd  = 1'b0;
    reg [6:0]  dev     = 7'h68;
    reg [7:0]  regn    = 8'd0;
    reg [7:0]  wdata   = 8'd0;
    reg [3:0]  nread   = 4'd1;
    reg [7:0]  buf0, buf1, buf2, buf3, buf4, buf5, buf6, buf7;
    reg [7:0]  buf8, buf9, buf10, buf11, buf12, buf13;
    reg        tried69 = 1'b0;
    reg        inited  = 1'b0;

    wire        i2c_busy;
    wire        i2c_done;
    wire        i2c_err;
    wire [7:0]  rbyte;
    wire        rvalid;
    wire [3:0]  ridx;

    i2c_master #(
        .HALF    (HALF),
        .STRETCH (27000)
    ) u_i2c (
        .clk     (clk),
        .go      (i2c_go),
        .cmd_rd  (cmd_rd),
        .dev     (dev),
        .regn    (regn),
        .wdata   (wdata),
        .nread   (nread),
        .busy    (i2c_busy),
        .done    (i2c_done),
        .err     (i2c_err),
        .rbyte   (rbyte),
        .rvalid  (rvalid),
        .ridx    (ridx),
        .scl_oe  (scl_oe),
        .sda_oe  (sda_oe),
        .scl_i   (scl_i),
        .sda_i   (sda_i)
    );

    assign idle  = (state == ST_IDLE) && !i2c_busy;
    assign ready = inited;

    function [0:0] who_ok;
        input [7:0] w;
        begin
            who_ok = (w == 8'h71) || (w == 8'h73) || (w == 8'h70);
        end
    endfunction

    initial begin
        sample_done = 1'b0;
        status      = IMU_WAIT;
        whoami      = 8'd0;
        dev_used    = 7'h68;
        ax = 16'd0; ay = 16'd0; az = 16'd0;
        gx = 16'd0; gy = 16'd0; gz = 16'd0;
        buf0 = 8'd0; buf1 = 8'd0; buf2 = 8'd0; buf3 = 8'd0;
        buf4 = 8'd0; buf5 = 8'd0; buf6 = 8'd0; buf7 = 8'd0;
        buf8 = 8'd0; buf9 = 8'd0; buf10 = 8'd0; buf11 = 8'd0;
        buf12 = 8'd0; buf13 = 8'd0;
    end

    always @(posedge clk) begin
        i2c_go      <= 1'b0;
        sample_done <= 1'b0;

        if (rvalid) begin
            case (ridx)
                4'd0:  buf0  <= rbyte;
                4'd1:  buf1  <= rbyte;
                4'd2:  buf2  <= rbyte;
                4'd3:  buf3  <= rbyte;
                4'd4:  buf4  <= rbyte;
                4'd5:  buf5  <= rbyte;
                4'd6:  buf6  <= rbyte;
                4'd7:  buf7  <= rbyte;
                4'd8:  buf8  <= rbyte;
                4'd9:  buf9  <= rbyte;
                4'd10: buf10 <= rbyte;
                4'd11: buf11 <= rbyte;
                4'd12: buf12 <= rbyte;
                default: buf13 <= rbyte;
            endcase
        end

        case (state)
            ST_PWR: begin
                if (tcnt >= T_PWR) begin
                    tcnt   <= 24'd0;
                    cmd_rd <= 1'b0;
                    regn   <= REG_PWR;
                    wdata  <= 8'h00;
                    nread  <= 4'd1;
                    i2c_go <= 1'b1;
                    state  <= ST_WAKE;
                end else
                    tcnt <= tcnt + 24'd1;
            end

            ST_WAKE: begin
                if (i2c_done) begin
                    if (i2c_err) begin
                        if (!tried69) begin
                            tried69 <= 1'b1;
                            dev     <= 7'h69;
                            tcnt    <= 24'd0;
                            state   <= ST_RETRY;
                        end else begin
                            status  <= IMU_NAK;
                            tried69 <= 1'b0;
                            dev     <= 7'h68;
                            tcnt    <= 24'd0;
                            state   <= ST_PWR;
                        end
                    end else begin
                        tcnt  <= 24'd0;
                        state <= ST_WAIT;
                    end
                end
            end

            ST_RETRY: begin
                if (tcnt >= 24'd2048) begin
                    tcnt   <= 24'd0;
                    cmd_rd <= 1'b0;
                    regn   <= REG_PWR;
                    wdata  <= 8'h00;
                    i2c_go <= 1'b1;
                    state  <= ST_WAKE;
                end else
                    tcnt <= tcnt + 24'd1;
            end

            ST_WAIT: begin
                if (tcnt >= T_WAKE) begin
                    tcnt   <= 24'd0;
                    cmd_rd <= 1'b1;
                    regn   <= REG_WHO;
                    nread  <= 4'd1;
                    i2c_go <= 1'b1;
                    state  <= ST_WHO;
                end else
                    tcnt <= tcnt + 24'd1;
            end

            ST_WHO: begin
                if (i2c_done) begin
                    if (i2c_err) begin
                        if (!tried69 && (dev == 7'h68)) begin
                            tried69 <= 1'b1;
                            dev     <= 7'h69;
                            tcnt    <= 24'd0;
                            state   <= ST_RETRY;
                        end else begin
                            status  <= IMU_NAK;
                            tried69 <= 1'b0;
                            dev     <= 7'h68;
                            tcnt    <= 24'd0;
                            state   <= ST_PWR;
                        end
                    end else begin
                        whoami   <= buf0;
                        dev_used <= dev;
                        inited   <= 1'b1;
                        status   <= who_ok(buf0) ? IMU_OK : IMU_ID;
                        state    <= ST_IDLE;
                    end
                end
            end

            ST_IDLE: begin
                if (start && !paused && inited && !i2c_busy) begin
                    cmd_rd <= 1'b1;
                    regn   <= REG_AX;
                    nread  <= 4'd14;
                    i2c_go <= 1'b1;
                    state  <= ST_READ;
                end
            end

            ST_READ: begin
                if (i2c_done) begin
                    state <= ST_IDLE;
                    if (!i2c_err) begin
                        ax <= {buf0,  buf1};
                        ay <= {buf2,  buf3};
                        az <= {buf4,  buf5};
                        gx <= {buf8,  buf9};
                        gy <= {buf10, buf11};
                        gz <= {buf12, buf13};
                        sample_done <= 1'b1;
                    end else
                        status <= IMU_NAK;
                end
            end

            default: state <= ST_PWR;
        endcase
    end
endmodule
