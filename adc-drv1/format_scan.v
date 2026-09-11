// One millivolt/BCD datapath. Walks V1..V8 after each ADC burst.
// mV = |raw| * 625 / 4096  (= * 5000 / 32768), RAGE = GND -> +/-5 V.
// Digits by repeated subtract (max 9 loops per decade). No DSP, no 8-wide ALU.
module format_scan (
    input  wire        clk,
    input  wire        start,
    input  wire [15:0] ch0,
    input  wire [15:0] ch1,
    input  wire [15:0] ch2,
    input  wire [15:0] ch3,
    input  wire [15:0] ch4,
    input  wire [15:0] ch5,
    input  wire [15:0] ch6,
    input  wire [15:0] ch7,
    output wire        idle,
    output reg  [16:0] p0,
    output reg  [16:0] p1,
    output reg  [16:0] p2,
    output reg  [16:0] p3,
    output reg  [16:0] p4,
    output reg  [16:0] p5,
    output reg  [16:0] p6,
    output reg  [16:0] p7,
    output reg  [15:0] r0,
    output reg  [15:0] r1,
    output reg  [15:0] r2,
    output reg  [15:0] r3,
    output reg  [15:0] r4,
    output reg  [15:0] r5,
    output reg  [15:0] r6,
    output reg  [15:0] r7
);
    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_ABS  = 3'd1;
    localparam [2:0] ST_MUL  = 3'd2;
    localparam [2:0] ST_TH   = 3'd3;
    localparam [2:0] ST_H    = 3'd4;
    localparam [2:0] ST_T    = 3'd5;
    localparam [2:0] ST_O    = 3'd6;

    reg [2:0]  state = ST_IDLE;
    reg [2:0]  idx   = 3'd0;
    reg [15:0] raw   = 16'd0;
    reg        neg   = 1'b0;
    reg [15:0] mag   = 16'd0;
    reg [15:0] rest  = 16'd0;
    reg [3:0]  ip    = 4'd0;
    reg [3:0]  d1    = 4'd0;
    reg [3:0]  d2    = 4'd0;
    reg [3:0]  d3    = 4'd0;

    wire [15:0] ch_mux =
        (idx == 3'd0) ? ch0 :
        (idx == 3'd1) ? ch1 :
        (idx == 3'd2) ? ch2 :
        (idx == 3'd3) ? ch3 :
        (idx == 3'd4) ? ch4 :
        (idx == 3'd5) ? ch5 :
        (idx == 3'd6) ? ch6 : ch7;

    // 625 = 512+64+32+16+1. One adder tree, used 8 times in series.
    wire [31:0] mag32 = {16'd0, mag};
    wire [31:0] acc   = (mag32 << 9) + (mag32 << 6) + (mag32 << 5) +
                        (mag32 << 4) + mag32;
    wire [15:0] mv_w  = (acc[27:12] > 16'd9999) ? 16'd9999 : acc[27:12];

    assign idle = (state == ST_IDLE);

    initial begin
        p0 = 17'd0; p1 = 17'd0; p2 = 17'd0; p3 = 17'd0;
        p4 = 17'd0; p5 = 17'd0; p6 = 17'd0; p7 = 17'd0;
        r0 = 16'd0; r1 = 16'd0; r2 = 16'd0; r3 = 16'd0;
        r4 = 16'd0; r5 = 16'd0; r6 = 16'd0; r7 = 16'd0;
    end

    always @(posedge clk) begin
        case (state)
            ST_IDLE: begin
                if (start) begin
                    idx   <= 3'd0;
                    state <= ST_ABS;
                end
            end

            ST_ABS: begin
                raw <= ch_mux;
                neg <= ch_mux[15];
                mag <= ch_mux[15] ? (16'd0 - ch_mux) : ch_mux;
                ip  <= 4'd0;
                d1  <= 4'd0;
                d2  <= 4'd0;
                d3  <= 4'd0;
                state <= ST_MUL;
            end

            ST_MUL: begin
                rest  <= mv_w;
                state <= ST_TH;
            end

            ST_TH: begin
                if (rest >= 16'd1000) begin
                    rest <= rest - 16'd1000;
                    ip   <= ip + 4'd1;
                end else
                    state <= ST_H;
            end

            ST_H: begin
                if (rest >= 16'd100) begin
                    rest <= rest - 16'd100;
                    d1   <= d1 + 4'd1;
                end else
                    state <= ST_T;
            end

            ST_T: begin
                if (rest >= 16'd10) begin
                    rest <= rest - 16'd10;
                    d2   <= d2 + 4'd1;
                end else
                    state <= ST_O;
            end

            ST_O: begin
                d3 <= rest[3:0];
                case (idx)
                    3'd0: begin p0 <= {neg, ip, d1, d2, rest[3:0]}; r0 <= raw; end
                    3'd1: begin p1 <= {neg, ip, d1, d2, rest[3:0]}; r1 <= raw; end
                    3'd2: begin p2 <= {neg, ip, d1, d2, rest[3:0]}; r2 <= raw; end
                    3'd3: begin p3 <= {neg, ip, d1, d2, rest[3:0]}; r3 <= raw; end
                    3'd4: begin p4 <= {neg, ip, d1, d2, rest[3:0]}; r4 <= raw; end
                    3'd5: begin p5 <= {neg, ip, d1, d2, rest[3:0]}; r5 <= raw; end
                    3'd6: begin p6 <= {neg, ip, d1, d2, rest[3:0]}; r6 <= raw; end
                    default: begin p7 <= {neg, ip, d1, d2, rest[3:0]}; r7 <= raw; end
                endcase
                if (idx == 3'd7)
                    state <= ST_IDLE;
                else begin
                    idx   <= idx + 3'd1;
                    state <= ST_ABS;
                end
            end

            default: state <= ST_IDLE;
        endcase
    end
endmodule
