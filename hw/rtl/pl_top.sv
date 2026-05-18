`timescale 1ns / 1ps

module pl_top #(
    parameter int unsigned MAX_OUTPUTS = 16,
    parameter int unsigned MAX_PIXELS_PER_OUTPUT = 1024,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 64,
    parameter int unsigned CLK_HZ = 100_000_000,
    parameter int unsigned WS2811_T0H_NS = 250,
    parameter int unsigned WS2811_T0L_NS = 1_000,
    parameter int unsigned WS2811_T1H_NS = 600,
    parameter int unsigned WS2811_T1L_NS = 650,
    parameter int unsigned WS2811_RESET_NS = 50_000
) (
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         enable,
    input  logic                         commit_frame,
    input  logic [1:0]                   active_bank,
    input  logic [ADDR_WIDTH-1:0]        frame_base_addr,

    input  logic [31:0]                  output_count,
    input  logic [MAX_OUTPUTS*32-1:0]    output_pixel_count_flat,
    input  logic [MAX_OUTPUTS*32-1:0]    output_buffer_offset_flat,
    input  logic [MAX_OUTPUTS*32-1:0]    output_flags_flat,

    output logic [ADDR_WIDTH-1:0]        m_axi_araddr,
    output logic [7:0]                   m_axi_arlen,
    output logic [2:0]                   m_axi_arsize,
    output logic [1:0]                   m_axi_arburst,
    output logic                         m_axi_arvalid,
    input  logic                         m_axi_arready,

    input  logic [DATA_WIDTH-1:0]        m_axi_rdata,
    input  logic [1:0]                   m_axi_rresp,
    input  logic                         m_axi_rlast,
    input  logic                         m_axi_rvalid,
    output logic                         m_axi_rready,

    output logic [MAX_OUTPUTS-1:0]       ws2811_out,

    output logic                         busy,
    output logic                         frame_pending,
    output logic                         underrun,
    output logic                         config_error,
    output logic                         frame_done_pulse,
    output logic [31:0]                  debug_reader_state,
    output logic [31:0]                  debug_reader_output_index,
    output logic [31:0]                  debug_reader_pixel_index,
    output logic [31:0]                  debug_pixel_accept_count,
    output logic [31:0]                  debug_ws_high_count
);

    logic [MAX_OUTPUTS*24-1:0] pixel_rgb_flat;
    logic [MAX_OUTPUTS-1:0] pixel_valid;
    logic [MAX_OUTPUTS-1:0] pixel_ready;
    logic [MAX_OUTPUTS-1:0] output_end_frame;
    logic [MAX_OUTPUTS-1:0] output_enable;
    logic [MAX_OUTPUTS-1:0] output_busy;
    logic [MAX_OUTPUTS-1:0] output_done_pulse;
    logic [MAX_OUTPUTS-1:0] output_underrun_pulse;
    logic reader_busy;
    logic reader_done_pulse;
    logic reader_config_error;
    logic [2:0] reader_state;
    logic [31:0] reader_output_index;
    logic [31:0] reader_pixel_index;
    logic [31:0] pixel_accept_count;
    logic [31:0] ws_high_count;

    for (genvar i = 0; i < MAX_OUTPUTS; i++) begin : gen_output_enable
        assign output_enable[i] = output_flags_flat[i*32];
    end

    frame_reader #(
        .MAX_OUTPUTS(MAX_OUTPUTS),
        .MAX_PIXELS_PER_OUTPUT(MAX_PIXELS_PER_OUTPUT),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) frame_reader (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .start_frame(commit_frame),
        .active_bank(active_bank),
        .frame_base_addr(frame_base_addr),
        .output_count(output_count),
        .output_pixel_count_flat(output_pixel_count_flat),
        .output_buffer_offset_flat(output_buffer_offset_flat),
        .output_flags_flat(output_flags_flat),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .pixel_rgb_flat(pixel_rgb_flat),
        .pixel_valid(pixel_valid),
        .pixel_ready(pixel_ready),
        .output_end_frame(output_end_frame),
        .busy(reader_busy),
        .done_pulse(reader_done_pulse),
        .config_error(reader_config_error),
        .debug_state(reader_state),
        .debug_output_index(reader_output_index),
        .debug_pixel_index(reader_pixel_index)
    );

    output_bank #(
        .MAX_OUTPUTS(MAX_OUTPUTS),
        .CLK_HZ(CLK_HZ),
        .T0H_NS(WS2811_T0H_NS),
        .T0L_NS(WS2811_T0L_NS),
        .T1H_NS(WS2811_T1H_NS),
        .T1L_NS(WS2811_T1L_NS),
        .RESET_NS(WS2811_RESET_NS)
    ) output_bank (
        .clk(clk),
        .rst_n(rst_n),
        .global_enable(enable && !reader_config_error),
        .start_frame(commit_frame),
        .output_enable(output_enable),
        .pixel_rgb_flat(pixel_rgb_flat),
        .pixel_valid(pixel_valid),
        .pixel_ready(pixel_ready),
        .output_end_frame(output_end_frame),
        .output_busy(output_busy),
        .output_done_pulse(output_done_pulse),
        .output_underrun_pulse(output_underrun_pulse),
        .ws2811_out(ws2811_out)
    );

    assign busy = reader_busy || (|output_busy);
    assign frame_pending = 1'b0;
    assign underrun = |output_underrun_pulse;
    assign config_error = reader_config_error;
    assign frame_done_pulse = reader_done_pulse || (|output_done_pulse);
    assign debug_reader_state = {29'd0, reader_state};
    assign debug_reader_output_index = reader_output_index;
    assign debug_reader_pixel_index = reader_pixel_index;
    assign debug_pixel_accept_count = pixel_accept_count;
    assign debug_ws_high_count = ws_high_count;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pixel_accept_count <= 32'd0;
            ws_high_count <= 32'd0;
        end else begin
            if (|(pixel_valid & pixel_ready)) begin
                pixel_accept_count <= pixel_accept_count + 32'd1;
            end
            if (|ws2811_out) begin
                ws_high_count <= ws_high_count + 32'd1;
            end
        end
    end

endmodule
