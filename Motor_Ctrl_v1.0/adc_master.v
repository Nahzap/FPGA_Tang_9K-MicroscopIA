// AD7606 serial master (HW-AD7606-F4, R1=10k SPI).
// CONVST stays high through tCONV. SCLK idle high; sample on falling.
// FPGA RST pin matches Analog: pulse high, idle low.
// probe_busy  = BUSY seen during last CONVST window
// probe_dout  = DOUTA MSB with CS low, before the first SCLK fall
module adc_master (
    input  wire        clk,
    input  wire        start,
    input  wire        paused,
    input  wire        adc_busy,
    input  wire        adc_dout,
    output reg         adc_convst,
    output reg         adc_reset,
    output reg         adc_cs,
    output reg         adc_sclk,
    output wire        idle,
    output wire        regs_valid,
    output reg         sample_done,
    output reg  [2:0]  status,
    output wire        busy_s,
    output wire        dout_s,
    output reg         probe_busy,
    output reg         probe_dout,
    output reg  [15:0] conv_cnt,
    output reg  [15:0] ch0,
    output reg  [15:0] ch1,
    output reg  [15:0] ch2,
    output reg  [15:0] ch3,
    output reg  [15:0] ch4,
    output reg  [15:0] ch5,
    output reg  [15:0] ch6,
    output reg  [15:0] ch7
);
    localparam [3:0] ST_RST_H   = 4'd0;
    localparam [3:0] ST_RST_L   = 4'd1;
    localparam [3:0] ST_IDLE    = 4'd2;
    localparam [3:0] ST_CONVST  = 4'd3;
    localparam [3:0] ST_WAIT_BH = 4'd4;
    localparam [3:0] ST_WAIT_BL = 4'd5;
    localparam [3:0] ST_T4      = 4'd6;
    localparam [3:0] ST_CS_WAIT = 4'd7;
    localparam [3:0] ST_SCLK_L  = 4'd8;
    localparam [3:0] ST_SCLK_H  = 4'd9;
    localparam [3:0] ST_CS_END  = 4'd10;
    localparam [3:0] ST_LATCH   = 4'd11;

    localparam [15:0] N_RST_H  = 16'd27000;
    localparam [15:0] N_RST_L  = 16'd27000;
    localparam [15:0] N_CONVST = 16'd135;
    localparam [15:0] N_TCONV  = 16'd540;
    localparam [15:0] N_TOUT   = 16'd54000;
    localparam [15:0] N_T4     = 16'd8;
    localparam [15:0] N_HALF   = 16'd8;

    localparam [2:0] STU_RST  = 3'd0;
    localparam [2:0] STU_WAIT = 3'd1;
    localparam [2:0] STU_BUSY = 3'd2;
    localparam [2:0] STU_OK   = 3'd3;
    localparam [2:0] STU_NBUS = 3'd4;
    localparam [2:0] STU_STUK = 3'd5;

    reg [3:0]  state      = ST_RST_H;
    reg [15:0] cnt        = 16'd0;
    reg [2:0]  ch_i       = 3'd0;
    reg [3:0]  b_i        = 4'd0;
    reg [7:0]  nbit       = 8'd0;
    reg [15:0] bitacc     = 16'd0;
    reg        valid_r    = 1'b0;
    reg        saw_busy   = 1'b0;
    reg        stuck_busy = 1'b0;
    reg [1:0]  busy_ff    = 2'b00;
    reg [1:0]  dout_ff    = 2'b00;

    initial begin
        adc_convst  = 1'b0;
        adc_reset   = 1'b1;
        adc_cs      = 1'b1;
        adc_sclk    = 1'b1;
        sample_done = 1'b0;
        status      = STU_RST;
        probe_busy  = 1'b0;
        probe_dout  = 1'b1;
        conv_cnt    = 16'd0;
        ch0 = 16'd0;
        ch1 = 16'd0;
        ch2 = 16'd0;
        ch3 = 16'd0;
        ch4 = 16'd0;
        ch5 = 16'd0;
        ch6 = 16'd0;
        ch7 = 16'd0;
    end

    always @(posedge clk) begin
        busy_ff <= {busy_ff[0], adc_busy};
        dout_ff <= {dout_ff[0], adc_dout};
    end

    assign busy_s = busy_ff[1];
    assign dout_s = dout_ff[1];
    wire [15:0] word = {bitacc[14:0], dout_s};

    assign idle       = (state == ST_IDLE);
    assign regs_valid = valid_r;

    always @(posedge clk) begin
        sample_done <= 1'b0;

        case (state)
            ST_RST_H: begin
                adc_reset  <= 1'b1;
                adc_convst <= 1'b0;
                adc_cs     <= 1'b1;
                adc_sclk   <= 1'b1;
                status     <= STU_RST;
                valid_r    <= 1'b0;
                if (cnt == (N_RST_H - 16'd1)) begin
                    cnt   <= 16'd0;
                    state <= ST_RST_L;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_RST_L: begin
                adc_reset <= 1'b0;
                status  <= STU_RST;
                if (cnt == (N_RST_L - 16'd1)) begin
                    cnt   <= 16'd0;
                    state <= ST_IDLE;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_IDLE: begin
                adc_reset  <= 1'b0;
                adc_sclk   <= 1'b1;
                adc_convst <= paused;
                adc_cs     <= paused ? 1'b0 : 1'b1;
                if (status != STU_OK && status != STU_NBUS && status != STU_STUK)
                    status <= STU_WAIT;
                if (start && !paused) begin
                    cnt        <= 16'd0;
                    saw_busy   <= 1'b0;
                    stuck_busy <= 1'b0;
                    state      <= ST_CONVST;
                end
            end

            ST_CONVST: begin
                adc_convst <= 1'b1;
                adc_sclk   <= 1'b1;
                status     <= STU_BUSY;
                if (busy_s)
                    saw_busy <= 1'b1;
                if (cnt == (N_CONVST - 16'd1)) begin
                    cnt   <= 16'd0;
                    state <= ST_WAIT_BH;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_WAIT_BH: begin
                adc_convst <= 1'b1;
                status     <= STU_BUSY;
                if (busy_s)
                    saw_busy <= 1'b1;
                if (cnt == (N_TCONV - 16'd1)) begin
                    adc_convst <= 1'b0;
                    cnt        <= 16'd0;
                    if (busy_s)
                        state <= ST_WAIT_BL;
                    else
                        state <= ST_T4;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_WAIT_BL: begin
                adc_convst <= 1'b0;
                status     <= STU_BUSY;
                if (!busy_s) begin
                    cnt   <= 16'd0;
                    state <= ST_T4;
                end else if (cnt == (N_TOUT - 16'd1)) begin
                    stuck_busy <= 1'b1;
                    cnt        <= 16'd0;
                    state      <= ST_T4;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_T4: begin
                adc_convst <= 1'b0;
                adc_cs     <= 1'b1;
                adc_sclk   <= 1'b1;
                if (cnt == (N_T4 - 16'd1)) begin
                    adc_cs <= 1'b0;
                    ch_i   <= 3'd0;
                    b_i    <= 4'd0;
                    nbit   <= 8'd0;
                    bitacc <= 16'd0;
                    cnt    <= 16'd0;
                    state  <= ST_CS_WAIT;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_CS_WAIT: begin
                adc_cs   <= 1'b0;
                adc_sclk <= 1'b1;
                if (cnt == (N_T4 - 16'd1)) begin
                    probe_dout <= dout_s;
                    cnt        <= 16'd0;
                    state      <= ST_SCLK_L;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_SCLK_L: begin
                adc_cs   <= 1'b0;
                adc_sclk <= 1'b0;
                if (cnt == (N_HALF - 16'd1)) begin
                    if (b_i == 4'd15) begin
                        case (ch_i)
                            3'd0: ch0 <= word;
                            3'd1: ch1 <= word;
                            3'd2: ch2 <= word;
                            3'd3: ch3 <= word;
                            3'd4: ch4 <= word;
                            3'd5: ch5 <= word;
                            3'd6: ch6 <= word;
                            default: ch7 <= word;
                        endcase
                        bitacc <= 16'd0;
                        b_i    <= 4'd0;
                        ch_i   <= ch_i + 3'd1;
                    end else begin
                        bitacc <= word;
                        b_i    <= b_i + 4'd1;
                    end
                    nbit  <= nbit + 8'd1;
                    cnt   <= 16'd0;
                    state <= ST_SCLK_H;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_SCLK_H: begin
                adc_cs   <= 1'b0;
                adc_sclk <= 1'b1;
                if (cnt == (N_HALF - 16'd1)) begin
                    cnt <= 16'd0;
                    if (nbit == 8'd128)
                        state <= ST_CS_END;
                    else
                        state <= ST_SCLK_L;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_CS_END: begin
                adc_cs   <= 1'b1;
                adc_sclk <= 1'b1;
                if (cnt == (N_HALF - 16'd1)) begin
                    cnt   <= 16'd0;
                    state <= ST_LATCH;
                end else
                    cnt <= cnt + 16'd1;
            end

            ST_LATCH: begin
                valid_r     <= 1'b1;
                sample_done <= 1'b1;
                probe_busy  <= saw_busy;
                conv_cnt    <= conv_cnt + 16'd1;
                if (stuck_busy)
                    status <= STU_STUK;
                else if (!saw_busy)
                    status <= STU_NBUS;
                else
                    status <= STU_OK;
                state <= ST_IDLE;
            end

            default: begin
                state      <= ST_RST_H;
                cnt        <= 16'd0;
                adc_reset  <= 1'b1;
                adc_convst <= 1'b0;
                adc_cs     <= 1'b1;
                adc_sclk   <= 1'b1;
            end
        endcase
    end
endmodule
