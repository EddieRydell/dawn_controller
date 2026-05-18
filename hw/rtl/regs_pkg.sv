`timescale 1ns / 1ps

// Generated from memory_map.yaml. Do not edit by hand.
package regs_pkg;

    localparam int unsigned PL_REG_CONTROL = 32'h000;
    localparam logic [31:0] PL_ENABLE = 32'h00000001;
    localparam logic [31:0] PL_COMMIT_FRAME = 32'h00000002;

    localparam int unsigned PL_REG_STATUS = 32'h004;
    localparam logic [31:0] PL_BUSY = 32'h00000001;
    localparam logic [31:0] PL_FRAME_PENDING = 32'h00000002;
    localparam logic [31:0] PL_UNDERRUN = 32'h00000004;
    localparam logic [31:0] PL_CONFIG_ERROR = 32'h00000008;

    localparam int unsigned PL_REG_ACTIVE_BANK = 32'h008;

    localparam int unsigned PL_REG_WRITE_BANK = 32'h00c;

    localparam int unsigned PL_REG_FRAME_COUNTER = 32'h010;

    localparam int unsigned PL_REG_DROPPED_FRAME_COUNTER = 32'h014;

    localparam int unsigned PL_REG_LATE_COMMIT_COUNTER = 32'h018;

    localparam int unsigned PL_REG_OUTPUT_COUNT = 32'h020;

    localparam int unsigned PL_REG_MAX_PIXELS_PER_OUTPUT = 32'h024;

    localparam int unsigned PL_REG_FRAME_BASE_ADDR = 32'h028;

    localparam int unsigned PL_REG_OUTPUT_PIXEL_COUNT = 32'h100;
    localparam int unsigned PL_REG_OUTPUT_PIXEL_COUNT_STRIDE = 32'h010;

    localparam int unsigned PL_REG_OUTPUT_BUFFER_OFFSET = 32'h104;
    localparam int unsigned PL_REG_OUTPUT_BUFFER_OFFSET_STRIDE = 32'h010;

    localparam int unsigned PL_REG_OUTPUT_FLAGS = 32'h108;
    localparam int unsigned PL_REG_OUTPUT_FLAGS_STRIDE = 32'h010;
    localparam logic [31:0] PL_OUTPUT_ENABLE = 32'h00000001;
    localparam logic [31:0] PL_OUTPUT_REVERSED = 32'h00000002;
    localparam logic [31:0] PL_OUTPUT_COLOR_ORDER_LSB_MASK = 32'h00000300;
    localparam int unsigned PL_OUTPUT_COLOR_ORDER_LSB_SHIFT = 8;

    localparam int unsigned PL_REG_OUTPUT_BASE = 32'h100;
    localparam int unsigned PL_REG_OUTPUT_STRIDE = 32'h010;

endpackage
