`timescale 1ns / 1ps

module ws281x_controller_core #(
    parameter AXIL_ADDR_WIDTH = 12,
    parameter FRAME_WORDS = 8192,
    parameter FRAME_ADDR_WIDTH = 15,
    parameter OUTPUT_COUNT = 4,
    parameter PIXELS_PER_OUTPUT = 1024,
    parameter CLK_HZ = 100000000,
    parameter WS281X_BIT_RATE = 800000
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK", X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET aresetn" *)
    input  wire                       aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST", X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                       aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR", X_INTERFACE_MODE = "Slave" *)
    input  wire [AXIL_ADDR_WIDTH-1:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  wire [2:0]                 s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire                       s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire                       s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0]                s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]                 s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire                       s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire                       s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]                 s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire                       s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire                       s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [AXIL_ADDR_WIDTH-1:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0]                 s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire                       s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire                       s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [31:0]                s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]                 s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire                       s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire                       s_axi_rready,
    output wire [OUTPUT_COUNT-1:0]    ws281x_data,
    output wire [FRAME_ADDR_WIDTH-1:0] m_frame_araddr,
    output wire                       m_frame_arvalid,
    input  wire                       m_frame_arready,
    input  wire [31:0]                m_frame_rdata,
    input  wire [1:0]                 m_frame_rresp,
    input  wire                       m_frame_rvalid,
    output wire                       m_frame_rready
);

    wire consumer_enable;
    wire consumer_reset_pulse;
    wire consumer_busy;
    wire consumer_reset_low;
    wire consumer_error_pulse;
    wire [31:0] active_bank;
    wire [31:0] committed_words;
    wire [31:0] frame_sequence;
    wire [31:0] consumer_sequence;
    wire [31:0] consumer_frame_count;
    wire [31:0] consumer_error_count;
    wire [31:0] consumer_active_bank;
    wire [31:0] consumer_debug;
    wire [31:0] runtime_active_output_count;
    wire [31:0] runtime_strand0_pixel_count;
    wire [31:0] runtime_strand1_pixel_count;
    wire [31:0] runtime_strand2_pixel_count;
    wire [31:0] runtime_strand3_pixel_count;
    wire [OUTPUT_COUNT-1:0] runtime_output_invert_mask;

    pl_frame_control #(
        .AXIL_ADDR_WIDTH(AXIL_ADDR_WIDTH),
        .FRAME_WORDS(FRAME_WORDS),
        .OUTPUT_COUNT(OUTPUT_COUNT),
        .PIXELS_PER_OUTPUT(PIXELS_PER_OUTPUT)
    ) frame_control (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .consumer_enable(consumer_enable),
        .consumer_reset_pulse(consumer_reset_pulse),
        .consumer_busy(consumer_busy),
        .consumer_reset_low(consumer_reset_low),
        .consumer_error_pulse(consumer_error_pulse),
        .consumer_sequence(consumer_sequence),
        .consumer_frame_count(consumer_frame_count),
        .consumer_error_count(consumer_error_count),
        .consumer_debug(consumer_debug),
        .consumer_active_bank(consumer_active_bank),
        .active_bank(active_bank),
        .committed_words(committed_words),
        .frame_sequence(frame_sequence),
        .runtime_active_output_count(runtime_active_output_count),
        .runtime_strand0_pixel_count(runtime_strand0_pixel_count),
        .runtime_strand1_pixel_count(runtime_strand1_pixel_count),
        .runtime_strand2_pixel_count(runtime_strand2_pixel_count),
        .runtime_strand3_pixel_count(runtime_strand3_pixel_count),
        .runtime_output_invert_mask(runtime_output_invert_mask)
    );

    ws281x_frame_consumer #(
        .FRAME_WORDS(FRAME_WORDS),
        .FRAME_ADDR_WIDTH(FRAME_ADDR_WIDTH),
        .OUTPUT_COUNT(OUTPUT_COUNT),
        .PIXELS_PER_OUTPUT(PIXELS_PER_OUTPUT),
        .CLK_HZ(CLK_HZ),
        .WS281X_BIT_RATE(WS281X_BIT_RATE)
    ) consumer (
        .aclk(aclk),
        .aresetn(aresetn),
        .enable(consumer_enable),
        .reset_pulse(consumer_reset_pulse),
        .active_bank(active_bank),
        .committed_words(committed_words),
        .frame_sequence(frame_sequence),
        .runtime_active_output_count(runtime_active_output_count),
        .runtime_strand0_pixel_count(runtime_strand0_pixel_count),
        .runtime_strand1_pixel_count(runtime_strand1_pixel_count),
        .runtime_strand2_pixel_count(runtime_strand2_pixel_count),
        .runtime_strand3_pixel_count(runtime_strand3_pixel_count),
        .runtime_output_invert_mask(runtime_output_invert_mask),
        .busy(consumer_busy),
        .reset_low(consumer_reset_low),
        .error_pulse(consumer_error_pulse),
        .consumer_sequence(consumer_sequence),
        .consumer_frame_count(consumer_frame_count),
        .consumer_error_count(consumer_error_count),
        .consumer_active_bank(consumer_active_bank),
        .consumer_debug(consumer_debug),
        .ws281x_data(ws281x_data),
        .m_frame_araddr(m_frame_araddr),
        .m_frame_arvalid(m_frame_arvalid),
        .m_frame_arready(m_frame_arready),
        .m_frame_rdata(m_frame_rdata),
        .m_frame_rresp(m_frame_rresp),
        .m_frame_rvalid(m_frame_rvalid),
        .m_frame_rready(m_frame_rready)
    );

endmodule
