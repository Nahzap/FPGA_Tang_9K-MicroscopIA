// Open-drain I2C master. SCL/SDA: oe=1 drives 0, oe=0 releases (pull-up).
// Sequential PHY. Clock stretch: wait for SCL to rise after we release it.
// cmd 0 = write one data byte to a register; cmd 1 = read nread bytes from a register.
module i2c_master #(
    parameter integer HALF     = 135,
    parameter integer STRETCH  = 27000
) (
    input  wire        clk,
    input  wire        go,
    input  wire        cmd_rd,
    input  wire [6:0]  dev,
    input  wire [7:0]  regn,
    input  wire [7:0]  wdata,
    input  wire [3:0]  nread,
    output reg         busy,
    output reg         done,
    output reg         err,
    output reg  [7:0]  rbyte,
    output reg         rvalid,
    output reg  [3:0]  ridx,
    output reg         scl_oe,
    output reg         sda_oe,
    input  wire        scl_i,
    input  wire        sda_i
);
    localparam [4:0] ST_IDLE    = 5'd0;
    localparam [4:0] ST_STA0    = 5'd1;
    localparam [4:0] ST_STA1    = 5'd2;
    localparam [4:0] ST_STA2    = 5'd3;
    localparam [4:0] ST_TX_SDA  = 5'd4;
    localparam [4:0] ST_TX_H    = 5'd5;
    localparam [4:0] ST_TX_L    = 5'd6;
    localparam [4:0] ST_ACK_SDA = 5'd7;
    localparam [4:0] ST_ACK_H   = 5'd8;
    localparam [4:0] ST_ACK_L   = 5'd9;
    localparam [4:0] ST_RS0     = 5'd10;
    localparam [4:0] ST_RS1     = 5'd11;
    localparam [4:0] ST_RS2     = 5'd12;
    localparam [4:0] ST_RS3     = 5'd13;
    localparam [4:0] ST_RX_SDA  = 5'd14;
    localparam [4:0] ST_RX_H    = 5'd15;
    localparam [4:0] ST_RX_L    = 5'd16;
    localparam [4:0] ST_MK_SDA  = 5'd17;
    localparam [4:0] ST_MK_H    = 5'd18;
    localparam [4:0] ST_MK_L    = 5'd19;
    localparam [4:0] ST_SP0     = 5'd20;
    localparam [4:0] ST_SP1     = 5'd21;
    localparam [4:0] ST_SP2     = 5'd22;
    localparam [4:0] ST_SP3     = 5'd23;
    localparam [4:0] ST_NEXT    = 5'd24;

    // After an ACK: 0=addrW 1=reg 2=wdata 3=addrR
    localparam [1:0] PH_ADDRW = 2'd0;
    localparam [1:0] PH_REG   = 2'd1;
    localparam [1:0] PH_DATA  = 2'd2;
    localparam [1:0] PH_ADDRR = 2'd3;

    reg [4:0]  state    = ST_IDLE;
    reg [15:0] cnt      = 16'd0;
    reg [15:0] stretch  = 16'd0;
    reg [7:0]  shift    = 8'd0;
    reg [2:0]  bitn     = 3'd0;
    reg [1:0]  phase    = 2'd0;
    reg        rd_mode  = 1'b0;
    reg [3:0]  nleft    = 4'd0;
    reg [1:0]  scl_ff   = 2'b11;
    reg [1:0]  sda_ff   = 2'b11;
    reg        ack_bit  = 1'b0;
    reg [7:0]  rxacc    = 8'd0;

    wire scl_s = scl_ff[1];
    wire sda_s = sda_ff[1];

    wire [15:0] half_m1 = HALF[15:0] - 16'd1;
    wire        half_done = (cnt == half_m1);
    wire        scl_up    = scl_s;
    wire        stretch_to = (stretch == STRETCH[15:0]);

    initial begin
        busy   = 1'b0;
        done   = 1'b0;
        err    = 1'b0;
        rbyte  = 8'd0;
        rvalid = 1'b0;
        ridx   = 4'd0;
        scl_oe = 1'b0;
        sda_oe = 1'b0;
    end

    always @(posedge clk) begin
        scl_ff <= {scl_ff[0], scl_i};
        sda_ff <= {sda_ff[0], sda_i};
        done   <= 1'b0;
        rvalid <= 1'b0;

        case (state)
            ST_IDLE: begin
                scl_oe <= 1'b0;
                sda_oe <= 1'b0;
                busy   <= 1'b0;
                if (go) begin
                    busy    <= 1'b1;
                    err     <= 1'b0;
                    rd_mode <= cmd_rd;
                    nleft   <= (nread == 4'd0) ? 4'd1 : nread;
                    ridx    <= 4'd0;
                    cnt     <= 16'd0;
                    stretch <= 16'd0;
                    state   <= ST_STA0;
                end
            end

            ST_STA0: begin
                scl_oe <= 1'b0;
                sda_oe <= 1'b0;
                if (half_done) begin
                    cnt   <= 16'd0;
                    sda_oe <= 1'b1;
                    state  <= ST_STA1;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_STA1: begin
                if (half_done) begin
                    cnt    <= 16'd0;
                    scl_oe <= 1'b1;
                    state  <= ST_STA2;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_STA2: begin
                if (half_done) begin
                    cnt   <= 16'd0;
                    shift <= {dev, 1'b0};
                    bitn  <= 3'd7;
                    phase <= PH_ADDRW;
                    state <= ST_TX_SDA;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_TX_SDA: begin
                sda_oe <= ~shift[7];
                if (half_done) begin
                    cnt     <= 16'd0;
                    stretch <= 16'd0;
                    scl_oe  <= 1'b0;
                    state   <= ST_TX_H;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_TX_H: begin
                if (!scl_up) begin
                    if (stretch_to) begin
                        err   <= 1'b1;
                        cnt   <= 16'd0;
                        sda_oe <= 1'b1;
                        state <= ST_SP0;
                    end else
                        stretch <= stretch + 16'd1;
                end else if (half_done) begin
                    cnt    <= 16'd0;
                    scl_oe <= 1'b1;
                    state  <= ST_TX_L;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_TX_L: begin
                if (half_done) begin
                    cnt   <= 16'd0;
                    shift <= {shift[6:0], 1'b0};
                    if (bitn == 3'd0)
                        state <= ST_ACK_SDA;
                    else begin
                        bitn  <= bitn - 3'd1;
                        state <= ST_TX_SDA;
                    end
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_ACK_SDA: begin
                sda_oe <= 1'b0;
                if (half_done) begin
                    cnt     <= 16'd0;
                    stretch <= 16'd0;
                    scl_oe  <= 1'b0;
                    state   <= ST_ACK_H;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_ACK_H: begin
                if (!scl_up) begin
                    if (stretch_to) begin
                        err    <= 1'b1;
                        cnt    <= 16'd0;
                        sda_oe <= 1'b1;
                        state  <= ST_SP0;
                    end else
                        stretch <= stretch + 16'd1;
                end else if (half_done) begin
                    ack_bit <= sda_s;
                    cnt     <= 16'd0;
                    scl_oe  <= 1'b1;
                    state   <= ST_ACK_L;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_ACK_L: begin
                if (half_done) begin
                    cnt <= 16'd0;
                    if (ack_bit) begin
                        err    <= 1'b1;
                        sda_oe <= 1'b1;
                        state  <= ST_SP0;
                    end else begin
                        case (phase)
                            PH_ADDRW: begin
                                shift <= regn;
                                bitn  <= 3'd7;
                                phase <= PH_REG;
                                state <= ST_TX_SDA;
                            end
                            PH_REG: begin
                                if (rd_mode)
                                    state <= ST_RS0;
                                else begin
                                    shift <= wdata;
                                    bitn  <= 3'd7;
                                    phase <= PH_DATA;
                                    state <= ST_TX_SDA;
                                end
                            end
                            PH_DATA: begin
                                sda_oe <= 1'b1;
                                state  <= ST_SP0;
                            end
                            default: begin
                                bitn  <= 3'd7;
                                rxacc <= 8'd0;
                                state <= ST_RX_SDA;
                            end
                        endcase
                    end
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_RS0: begin
                sda_oe <= 1'b0;
                if (half_done) begin
                    cnt     <= 16'd0;
                    stretch <= 16'd0;
                    scl_oe  <= 1'b0;
                    state   <= ST_RS1;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_RS1: begin
                if (!scl_up) begin
                    if (stretch_to) begin
                        err    <= 1'b1;
                        cnt    <= 16'd0;
                        sda_oe <= 1'b1;
                        state  <= ST_SP0;
                    end else
                        stretch <= stretch + 16'd1;
                end else if (half_done) begin
                    cnt    <= 16'd0;
                    sda_oe <= 1'b1;
                    state  <= ST_RS2;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_RS2: begin
                if (half_done) begin
                    cnt    <= 16'd0;
                    scl_oe <= 1'b1;
                    state  <= ST_RS3;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_RS3: begin
                if (half_done) begin
                    cnt   <= 16'd0;
                    shift <= {dev, 1'b1};
                    bitn  <= 3'd7;
                    phase <= PH_ADDRR;
                    state <= ST_TX_SDA;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_RX_SDA: begin
                sda_oe <= 1'b0;
                if (half_done) begin
                    cnt     <= 16'd0;
                    stretch <= 16'd0;
                    scl_oe  <= 1'b0;
                    state   <= ST_RX_H;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_RX_H: begin
                if (!scl_up) begin
                    if (stretch_to) begin
                        err    <= 1'b1;
                        cnt    <= 16'd0;
                        sda_oe <= 1'b1;
                        state  <= ST_SP0;
                    end else
                        stretch <= stretch + 16'd1;
                end else if (half_done) begin
                    rxacc  <= {rxacc[6:0], sda_s};
                    cnt    <= 16'd0;
                    scl_oe <= 1'b1;
                    state  <= ST_RX_L;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_RX_L: begin
                if (half_done) begin
                    cnt <= 16'd0;
                    if (bitn == 3'd0)
                        state <= ST_MK_SDA;
                    else begin
                        bitn  <= bitn - 3'd1;
                        state <= ST_RX_SDA;
                    end
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_MK_SDA: begin
                // ACK (drive 0) if more bytes remain; NACK (release) on last.
                sda_oe <= (nleft > 4'd1);
                if (half_done) begin
                    cnt     <= 16'd0;
                    stretch <= 16'd0;
                    scl_oe  <= 1'b0;
                    state   <= ST_MK_H;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_MK_H: begin
                if (!scl_up) begin
                    if (stretch_to) begin
                        err    <= 1'b1;
                        cnt    <= 16'd0;
                        sda_oe <= 1'b1;
                        state  <= ST_SP0;
                    end else
                        stretch <= stretch + 16'd1;
                end else if (half_done) begin
                    cnt    <= 16'd0;
                    scl_oe <= 1'b1;
                    state  <= ST_MK_L;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_MK_L: begin
                if (half_done) begin
                    cnt    <= 16'd0;
                    rbyte  <= rxacc;
                    rvalid <= 1'b1;
                    if (nleft == 4'd1) begin
                        sda_oe <= 1'b1;
                        state  <= ST_SP0;
                    end else begin
                        nleft <= nleft - 4'd1;
                        state <= ST_NEXT;
                    end
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_NEXT: begin
                ridx  <= ridx + 4'd1;
                bitn  <= 3'd7;
                rxacc <= 8'd0;
                state <= ST_RX_SDA;
            end

            ST_SP0: begin
                sda_oe <= 1'b1;
                scl_oe <= 1'b1;
                if (half_done) begin
                    cnt     <= 16'd0;
                    stretch <= 16'd0;
                    scl_oe  <= 1'b0;
                    state   <= ST_SP1;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_SP1: begin
                if (!scl_up) begin
                    if (stretch_to) begin
                        cnt    <= 16'd0;
                        sda_oe <= 1'b0;
                        state  <= ST_SP2;
                    end else
                        stretch <= stretch + 16'd1;
                end else if (half_done) begin
                    cnt    <= 16'd0;
                    sda_oe <= 1'b0;
                    state  <= ST_SP2;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_SP2: begin
                if (half_done) begin
                    cnt   <= 16'd0;
                    state <= ST_SP3;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_SP3: begin
                scl_oe <= 1'b0;
                sda_oe <= 1'b0;
                if (half_done) begin
                    cnt   <= 16'd0;
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end else
                    cnt <= cnt + 16'd1;
            end

            default: state <= ST_IDLE;
        endcase
    end
endmodule
