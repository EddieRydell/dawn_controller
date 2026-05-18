`timescale 1ns / 1ps

module axi_regs #(
    parameter int unsigned MAX_OUTPUTS = 16,
    parameter int unsigned MAX_PIXELS_PER_OUTPUT = 1024,
    parameter int unsigned ADDR_WIDTH = 12
) (
    input  logic                   s_axi_aclk,
    input  logic                   s_axi_aresetn,

    input  logic [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  logic [2:0]             s_axi_awprot,
    input  logic                   s_axi_awvalid,
    output logic                   s_axi_awready,

    input  logic [31:0]            s_axi_wdata,
    input  logic [3:0]             s_axi_wstrb,
    input  logic                   s_axi_wvalid,
    output logic                   s_axi_wready,

    output logic [1:0]             s_axi_bresp,
    output logic                   s_axi_bvalid,
    input  logic                   s_axi_bready,

    input  logic [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  logic [2:0]             s_axi_arprot,
    input  logic                   s_axi_arvalid,
    output logic                   s_axi_arready,

    output logic [31:0]            s_axi_rdata,
    output logic [1:0]             s_axi_rresp,
    output logic                   s_axi_rvalid,
    input  logic                   s_axi_rready,

    input  logic [31:0]            status_i,
    output logic [31:0]            control_o,
    output logic                   commit_frame_o,
    output logic [31:0]            active_bank_o,
    output logic [31:0]            write_bank_o,
    output logic [31:0]            frame_base_addr_o,
    output logic [31:0]            output_count_o,
    output logic [MAX_OUTPUTS*32-1:0] output_pixel_count_o,
    output logic [MAX_OUTPUTS*32-1:0] output_buffer_offset_o,
    output logic [MAX_OUTPUTS*32-1:0] output_flags_o,

    input  logic [31:0]            debug_reader_state_i,
    input  logic [31:0]            debug_reader_output_index_i,
    input  logic [31:0]            debug_reader_pixel_index_i,
    input  logic [31:0]            debug_axi_arvalid_cycles_i,
    input  logic [31:0]            debug_axi_ar_handshakes_i,
    input  logic [31:0]            debug_axi_r_handshakes_i,
    input  logic [31:0]            debug_axi_last_araddr_i,
    input  logic [31:0]            debug_axi_last_rresp_i,
    input  logic [31:0]            debug_pixel_accept_count_i,
    input  logic [31:0]            debug_ws_high_count_i
);

    logic reg_wr_en;
    logic [ADDR_WIDTH-1:0] reg_wr_addr;
    logic [31:0] reg_wr_data;
    logic [3:0] reg_wr_strb;
    logic reg_rd_en;
    logic [ADDR_WIDTH-1:0] reg_rd_addr;
    logic [31:0] reg_rd_data;

    axil_reg_if #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(ADDR_WIDTH),
        .TIMEOUT(16)
    ) axi (
        .clk(s_axi_aclk),
        .rst(!s_axi_aresetn),
        .s_axil_awaddr(s_axi_awaddr),
        .s_axil_awprot(s_axi_awprot),
        .s_axil_awvalid(s_axi_awvalid),
        .s_axil_awready(s_axi_awready),
        .s_axil_wdata(s_axi_wdata),
        .s_axil_wstrb(s_axi_wstrb),
        .s_axil_wvalid(s_axi_wvalid),
        .s_axil_wready(s_axi_wready),
        .s_axil_bresp(s_axi_bresp),
        .s_axil_bvalid(s_axi_bvalid),
        .s_axil_bready(s_axi_bready),
        .s_axil_araddr(s_axi_araddr),
        .s_axil_arprot(s_axi_arprot),
        .s_axil_arvalid(s_axi_arvalid),
        .s_axil_arready(s_axi_arready),
        .s_axil_rdata(s_axi_rdata),
        .s_axil_rresp(s_axi_rresp),
        .s_axil_rvalid(s_axi_rvalid),
        .s_axil_rready(s_axi_rready),
        .reg_wr_en(reg_wr_en),
        .reg_wr_addr(reg_wr_addr),
        .reg_wr_data(reg_wr_data),
        .reg_wr_strb(reg_wr_strb),
        .reg_wr_wait(1'b0),
        .reg_wr_ack(reg_wr_en),
        .reg_rd_addr(reg_rd_addr),
        .reg_rd_en(reg_rd_en),
        .reg_rd_data(reg_rd_data),
        .reg_rd_wait(1'b0),
        .reg_rd_ack(reg_rd_en)
    );

    controller_regs #(
        .MAX_OUTPUTS(MAX_OUTPUTS),
        .MAX_PIXELS_PER_OUTPUT(MAX_PIXELS_PER_OUTPUT),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) regs (
        .clk(s_axi_aclk),
        .rst_n(s_axi_aresetn),
        .reg_wr_en(reg_wr_en),
        .reg_wr_addr(reg_wr_addr),
        .reg_wr_data(reg_wr_data),
        .reg_wr_strb(reg_wr_strb),
        .reg_rd_en(reg_rd_en),
        .reg_rd_addr(reg_rd_addr),
        .reg_rd_data(reg_rd_data),
        .status_i(status_i),
        .control_o(control_o),
        .commit_frame_o(commit_frame_o),
        .active_bank_o(active_bank_o),
        .write_bank_o(write_bank_o),
        .frame_base_addr_o(frame_base_addr_o),
        .output_count_o(output_count_o),
        .output_pixel_count_o(output_pixel_count_o),
        .output_buffer_offset_o(output_buffer_offset_o),
        .output_flags_o(output_flags_o),
        .debug_reader_state_i(debug_reader_state_i),
        .debug_reader_output_index_i(debug_reader_output_index_i),
        .debug_reader_pixel_index_i(debug_reader_pixel_index_i),
        .debug_axi_arvalid_cycles_i(debug_axi_arvalid_cycles_i),
        .debug_axi_ar_handshakes_i(debug_axi_ar_handshakes_i),
        .debug_axi_r_handshakes_i(debug_axi_r_handshakes_i),
        .debug_axi_last_araddr_i(debug_axi_last_araddr_i),
        .debug_axi_last_rresp_i(debug_axi_last_rresp_i),
        .debug_pixel_accept_count_i(debug_pixel_accept_count_i),
        .debug_ws_high_count_i(debug_ws_high_count_i)
    );

endmodule
