`timescale 1ns / 1ps
package pl_config_pkg;
    localparam int OUTPUT_COUNT = 30;
    localparam int PIN_OUTPUT_COUNT = 30;
    localparam int PIXELS_PER_OUTPUT = 1024;
    localparam int DEFAULT_ACTIVE_OUTPUT_COUNT = 30;
    localparam int DEFAULT_STRAND_PIXEL_COUNT = 50;
    localparam int DEFAULT_OUTPUT_INVERT_MASK = 1073741823;
    localparam int WS281X_BIT_RATE = 800000;
    localparam int FRAME_BANKS = 2;
    localparam int FRAME_WORDS_PER_BANK = 30720;
    localparam int FRAME_WORDS = 61440;
    localparam int FRAME_BYTES = 245760;
    localparam int FRAME_ADDR_WIDTH = 18;
    localparam int FRAME_RANGE_BYTES = 262144;
    localparam int MASK_WORD_COUNT = 1;
    localparam int OUTPUT_INDEX_WIDTH = 5;
    localparam int ACTIVE_OUTPUT_WIDTH = 5;
    localparam int PIXEL_COUNT_WIDTH = 11;
endpackage
