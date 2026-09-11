// Sole sequencer. One pot map + format_scan start together after ADC.
// PWM latches when the map finishes. LCD never gates a pin.
module orch #(
    parameter integer GAP = 27000
) (
    input  wire clk,
    input  wire paused,
    input  wire adc_idle,
    input  wire adc_done,
    input  wire map_idle,
    input  wire fmt_idle,
    output reg  adc_go,
    output reg  map_go,
    output reg  fmt_go,
    output reg  snap_pwm,
    output reg  snap_lcd,
    output wire pwm_en
);
    localparam [2:0] ST_ARM  = 3'd0;
    localparam [2:0] ST_GAP  = 3'd1;
    localparam [2:0] ST_ADC  = 3'd2;
    localparam [2:0] ST_KICK = 3'd3;
    localparam [2:0] ST_JOIN = 3'd4;

    localparam [15:0] LAST = GAP[15:0] - 16'd1;

    reg [2:0]  state   = ST_ARM;
    reg [15:0] cnt     = 16'd0;
    reg        mapped  = 1'b0;
    reg        saw_map = 1'b0;
    reg        saw_fmt = 1'b0;
    reg        got_pwm = 1'b0;
    reg        got_lcd = 1'b0;

    assign pwm_en = !paused && mapped;

    initial begin
        adc_go   = 1'b0;
        map_go   = 1'b0;
        fmt_go   = 1'b0;
        snap_pwm = 1'b0;
        snap_lcd = 1'b0;
    end

    always @(posedge clk) begin
        adc_go   <= 1'b0;
        map_go   <= 1'b0;
        fmt_go   <= 1'b0;
        snap_pwm <= 1'b0;
        snap_lcd <= 1'b0;

        case (state)
            ST_ARM: begin
                if (adc_idle && !paused) begin
                    adc_go <= 1'b1;
                    state  <= ST_ADC;
                end
            end

            ST_GAP: begin
                if (paused)
                    cnt <= 16'd0;
                else if (cnt == LAST && adc_idle && map_idle && fmt_idle) begin
                    cnt    <= 16'd0;
                    adc_go <= 1'b1;
                    state  <= ST_ADC;
                end else if (!paused)
                    cnt <= cnt + 16'd1;
            end

            ST_ADC: begin
                if (adc_done) begin
                    map_go  <= 1'b1;
                    fmt_go  <= 1'b1;
                    saw_map <= 1'b0;
                    saw_fmt <= 1'b0;
                    got_pwm <= 1'b0;
                    got_lcd <= 1'b0;
                    state   <= ST_KICK;
                end
            end

            ST_KICK: begin
                if (!map_idle)
                    saw_map <= 1'b1;
                else if (!saw_map)
                    map_go <= 1'b1;
                if (!fmt_idle)
                    saw_fmt <= 1'b1;
                else if (!saw_fmt)
                    fmt_go <= 1'b1;
                if ((saw_map || !map_idle) && (saw_fmt || !fmt_idle))
                    state <= ST_JOIN;
            end

            ST_JOIN: begin
                if (!map_idle)
                    saw_map <= 1'b1;
                if (!fmt_idle)
                    saw_fmt <= 1'b1;
                if (saw_map && map_idle && !got_pwm) begin
                    snap_pwm <= 1'b1;
                    got_pwm  <= 1'b1;
                    mapped   <= 1'b1;
                end
                if (saw_fmt && fmt_idle && !got_lcd) begin
                    snap_lcd <= 1'b1;
                    got_lcd  <= 1'b1;
                end
                if (got_pwm && got_lcd)
                    state <= ST_GAP;
            end

            default: state <= ST_ARM;
        endcase
    end
endmodule
