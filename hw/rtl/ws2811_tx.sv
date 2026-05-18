`timescale 1ns / 1ps

module ws2811_tx #(
    parameter int unsigned CLK_HZ = 100_000_000,
    parameter int unsigned T0H_NS = 250,
    parameter int unsigned T0L_NS = 1_000,
    parameter int unsigned T1H_NS = 600,
    parameter int unsigned T1L_NS = 650,
    parameter int unsigned RESET_NS = 50_000
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        enable,
    input  logic        start,
    input  logic        end_frame,

    input  logic [23:0] pixel_rgb,
    input  logic        pixel_valid,
    output logic        pixel_ready,

    output logic        busy,
    output logic        done_pulse,
    output logic        underrun_pulse,
    output logic        dout
);

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_BIT_HIGH,
        STATE_BIT_LOW,
        STATE_WAIT_PIXEL,
        STATE_RESET
    } state_t;

    function automatic int unsigned ns_to_cycles(input int unsigned ns);
        longint unsigned product;
        begin
            product = longint'(ns) * longint'(CLK_HZ);
            return int'((product + 999_999_999) / 1_000_000_000);
        end
    endfunction

    localparam int unsigned T0H_CYCLES = ns_to_cycles(T0H_NS);
    localparam int unsigned T0L_CYCLES = ns_to_cycles(T0L_NS);
    localparam int unsigned T1H_CYCLES = ns_to_cycles(T1H_NS);
    localparam int unsigned T1L_CYCLES = ns_to_cycles(T1L_NS);
    localparam int unsigned RESET_CYCLES = ns_to_cycles(RESET_NS);

    state_t state;
    logic [23:0] shift_reg;
    logic [23:0] next_pixel;
    logic [4:0] bit_index;
    logic [31:0] cycles_remaining;
    logic current_bit;
    logic current_last;
    logic next_valid;
    logic next_last;
    logic end_seen;
    logic pixels_started;

    wire wants_pixel = enable
        && !next_valid
        && !end_seen
        && (
            (state == STATE_IDLE && start)
            || (state == STATE_WAIT_PIXEL)
            || (state == STATE_BIT_HIGH)
            || (state == STATE_BIT_LOW)
        );
    wire accept_pixel = wants_pixel && pixel_valid;

    assign pixel_ready = wants_pixel;

    function automatic logic [31:0] cycles_to_count(input int unsigned cycles);
        begin
            return (cycles == 0) ? 32'd0 : 32'(cycles - 1);
        end
    endfunction

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            shift_reg <= 24'h000000;
            next_pixel <= 24'h000000;
            bit_index <= 5'd0;
            cycles_remaining <= 32'd0;
            current_bit <= 1'b0;
            current_last <= 1'b0;
            next_valid <= 1'b0;
            next_last <= 1'b0;
            end_seen <= 1'b0;
            pixels_started <= 1'b0;
            busy <= 1'b0;
            done_pulse <= 1'b0;
            underrun_pulse <= 1'b0;
            dout <= 1'b0;
        end else begin
            done_pulse <= 1'b0;
            underrun_pulse <= 1'b0;

            if (accept_pixel) begin
                next_pixel <= pixel_rgb;
                next_valid <= 1'b1;
                next_last <= end_frame;
            end else if (wants_pixel && end_frame) begin
                end_seen <= 1'b1;
            end

            unique case (state)
            STATE_IDLE: begin
                busy <= 1'b0;
                dout <= 1'b0;
                cycles_remaining <= 32'd0;

                if (enable && start) begin
                    busy <= 1'b1;
                    end_seen <= 1'b0;
                    pixels_started <= 1'b0;
                    state <= STATE_WAIT_PIXEL;
                end
            end

            STATE_WAIT_PIXEL: begin
                busy <= 1'b1;
                dout <= 1'b0;

                if (!enable) begin
                    state <= STATE_RESET;
                    cycles_remaining <= cycles_to_count(RESET_CYCLES);
                end else if (accept_pixel) begin
                    shift_reg <= pixel_rgb;
                    bit_index <= 5'd23;
                    current_bit <= pixel_rgb[23];
                    current_last <= end_frame;
                    pixels_started <= 1'b1;
                    next_valid <= 1'b0;
                    dout <= 1'b1;
                    cycles_remaining <= cycles_to_count(pixel_rgb[23] ? T1H_CYCLES : T0H_CYCLES);
                    state <= STATE_BIT_HIGH;
                end else if (next_valid) begin
                    shift_reg <= next_pixel;
                    bit_index <= 5'd23;
                    current_bit <= next_pixel[23];
                    current_last <= next_last;
                    pixels_started <= 1'b1;
                    next_valid <= 1'b0;
                    dout <= 1'b1;
                    cycles_remaining <= cycles_to_count(next_pixel[23] ? T1H_CYCLES : T0H_CYCLES);
                    state <= STATE_BIT_HIGH;
                end else if (end_seen) begin
                    state <= STATE_RESET;
                    cycles_remaining <= cycles_to_count(RESET_CYCLES);
                end else begin
                    state <= STATE_WAIT_PIXEL;
                end
            end

            STATE_BIT_HIGH: begin
                busy <= 1'b1;
                dout <= 1'b1;

                if (!enable) begin
                    dout <= 1'b0;
                    state <= STATE_RESET;
                    cycles_remaining <= cycles_to_count(RESET_CYCLES);
                end else if (cycles_remaining == 32'd0) begin
                    dout <= 1'b0;
                    cycles_remaining <= cycles_to_count(current_bit ? T1L_CYCLES : T0L_CYCLES);
                    state <= STATE_BIT_LOW;
                end else begin
                    cycles_remaining <= cycles_remaining - 32'd1;
                end
            end

            STATE_BIT_LOW: begin
                busy <= 1'b1;
                dout <= 1'b0;

                if (!enable) begin
                    state <= STATE_RESET;
                    cycles_remaining <= cycles_to_count(RESET_CYCLES);
                end else if (cycles_remaining == 32'd0) begin
                    if (bit_index == 5'd0) begin
                        if (current_last || end_seen) begin
                            state <= STATE_RESET;
                            cycles_remaining <= cycles_to_count(RESET_CYCLES);
                        end else if (accept_pixel) begin
                            shift_reg <= pixel_rgb;
                            bit_index <= 5'd23;
                            current_bit <= pixel_rgb[23];
                            current_last <= end_frame;
                            next_valid <= 1'b0;
                            dout <= 1'b1;
                            cycles_remaining <= cycles_to_count(pixel_rgb[23] ? T1H_CYCLES : T0H_CYCLES);
                            state <= STATE_BIT_HIGH;
                        end else if (next_valid) begin
                            shift_reg <= next_pixel;
                            bit_index <= 5'd23;
                            current_bit <= next_pixel[23];
                            current_last <= next_last;
                            next_valid <= 1'b0;
                            dout <= 1'b1;
                            cycles_remaining <= cycles_to_count(next_pixel[23] ? T1H_CYCLES : T0H_CYCLES);
                            state <= STATE_BIT_HIGH;
                        end else begin
                            underrun_pulse <= pixels_started;
                            state <= STATE_RESET;
                            cycles_remaining <= cycles_to_count(RESET_CYCLES);
                        end
                    end else begin
                        bit_index <= bit_index - 5'd1;
                        current_bit <= shift_reg[bit_index - 5'd1];
                        dout <= 1'b1;
                        cycles_remaining <= cycles_to_count(shift_reg[bit_index - 5'd1] ? T1H_CYCLES : T0H_CYCLES);
                        state <= STATE_BIT_HIGH;
                    end
                end else begin
                    cycles_remaining <= cycles_remaining - 32'd1;
                end
            end

            STATE_RESET: begin
                busy <= 1'b1;
                dout <= 1'b0;
                next_valid <= 1'b0;

                if (cycles_remaining == 32'd0) begin
                    busy <= 1'b0;
                    done_pulse <= 1'b1;
                    end_seen <= 1'b0;
                    pixels_started <= 1'b0;
                    state <= STATE_IDLE;
                end else begin
                    cycles_remaining <= cycles_remaining - 32'd1;
                end
            end

            default: begin
                state <= STATE_IDLE;
                busy <= 1'b0;
                dout <= 1'b0;
            end
            endcase
        end
    end

endmodule
