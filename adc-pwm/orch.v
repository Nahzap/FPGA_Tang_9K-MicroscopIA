// Three independent tracks. Workers never wait on each other.
// ADC pacer never looks at format or LCD. Maps never look at format.
// PWM enable is not a function of the display.
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
    localparam [15:0] LAST = GAP[15:0] - 16'd1;

    reg [15:0] gap      = 16'd0;
    reg        armed    = 1'b0;
    reg        mapped   = 1'b0;
    reg        map_hold = 1'b0;
    reg        fmt_hold = 1'b0;
    reg        saw_map  = 1'b0;
    reg        saw_fmt  = 1'b0;

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

        if (!armed) begin
            if (adc_idle && !paused) begin
                adc_go <= 1'b1;
                armed  <= 1'b1;
                gap    <= 16'd0;
            end
        end else if (paused)
            gap <= 16'd0;
        else if (!adc_idle)
            gap <= 16'd0;
        else if (gap != LAST)
            gap <= gap + 16'd1;
        else if (map_idle) begin
            adc_go <= 1'b1;
            gap    <= 16'd0;
        end

        if (map_hold) begin
            if (!map_idle)
                saw_map <= 1'b1;
            else if (!saw_map)
                map_go <= 1'b1;
            if (saw_map && map_idle) begin
                saw_map  <= 1'b0;
                snap_pwm <= 1'b1;
                mapped   <= 1'b1;
                if (!adc_done)
                    map_hold <= 1'b0;
            end
        end

        if (fmt_hold) begin
            if (!fmt_idle)
                saw_fmt <= 1'b1;
            else if (!saw_fmt)
                fmt_go <= 1'b1;
            if (saw_fmt && fmt_idle) begin
                saw_fmt  <= 1'b0;
                snap_lcd <= 1'b1;
                if (!adc_done)
                    fmt_hold <= 1'b0;
            end
        end

        if (adc_done) begin
            map_hold <= 1'b1;
            fmt_hold <= 1'b1;
            saw_map  <= 1'b0;
            saw_fmt  <= 1'b0;
        end
    end
endmodule
