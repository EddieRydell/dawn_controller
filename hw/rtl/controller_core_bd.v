`timescale 1ns / 1ps

module controller_core_bd #(
    parameter MAX_OUTPUTS = 16,
    parameter MAX_PIXELS_PER_OUTPUT = 1024,
    parameter AXIL_ADDR_WIDTH = 12,
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 64,
    parameter CLK_HZ = 100000000
) (
    input  wire                         aclk,
    input  wire                         aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR", X_INTERFACE_MODE = "Slave" *)
    input  wire [AXIL_ADDR_WIDTH-1:0]   s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  wire [2:0]                   s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire                         s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire                         s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0]                  s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]                   s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire                         s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire                         s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]                   s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire                         s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire                         s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [AXIL_ADDR_WIDTH-1:0]   s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0]                   s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire                         s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire                         s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [31:0]                  s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]                   s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire                         s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire                         s_axi_rready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWADDR", X_INTERFACE_MODE = "Master" *)
    output wire [AXI_ADDR_WIDTH-1:0]    m_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLEN" *)
    output wire [7:0]                   m_axi_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWSIZE" *)
    output wire [2:0]                   m_axi_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWBURST" *)
    output wire [1:0]                   m_axi_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWVALID" *)
    output wire                         m_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWREADY" *)
    input  wire                         m_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WDATA" *)
    output wire [AXI_DATA_WIDTH-1:0]    m_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WSTRB" *)
    output wire [AXI_DATA_WIDTH/8-1:0]  m_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WLAST" *)
    output wire                         m_axi_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WVALID" *)
    output wire                         m_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WREADY" *)
    input  wire                         m_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BRESP" *)
    input  wire [1:0]                   m_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BVALID" *)
    input  wire                         m_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BREADY" *)
    output wire                         m_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *)
    output wire [AXI_ADDR_WIDTH-1:0]    m_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *)
    output wire [7:0]                   m_axi_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *)
    output wire [2:0]                   m_axi_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *)
    output wire [1:0]                   m_axi_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *)
    output wire                         m_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *)
    input  wire                         m_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *)
    input  wire [AXI_DATA_WIDTH-1:0]    m_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *)
    input  wire [1:0]                   m_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *)
    input  wire                         m_axi_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *)
    input  wire                         m_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *)
    output wire                         m_axi_rready,

    output wire [MAX_OUTPUTS-1:0]       ws2811_data,
    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq INTERRUPT", X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *)
    output wire                         irq
);

    wire [31:0] control;
    wire commit_frame;
    wire [31:0] active_bank;
    wire [31:0] write_bank;
    wire [31:0] frame_base_addr;
    wire [31:0] output_count;
    wire [MAX_OUTPUTS*32-1:0] output_pixel_count_flat;
    wire [MAX_OUTPUTS*32-1:0] output_buffer_offset_flat;
    wire [MAX_OUTPUTS*32-1:0] output_flags_flat;
    wire busy;
    wire frame_pending;
    wire underrun;
    wire config_error;
    wire frame_done_pulse;
    wire [31:0] status;
    wire [MAX_OUTPUTS-1:0] pl_ws2811_data;
    wire [31:0] debug_reader_state;
    wire [31:0] debug_reader_output_index;
    wire [31:0] debug_reader_pixel_index;
    wire [31:0] debug_pixel_accept_count;
    wire [31:0] debug_ws_high_count;
    reg [31:0] debug_axi_arvalid_cycles;
    reg [31:0] debug_axi_ar_handshakes;
    reg [31:0] debug_axi_r_handshakes;
    reg [31:0] debug_axi_last_araddr;
    reg [31:0] debug_axi_last_rresp;
    reg [31:0] debug_pin_counter;
    wire [MAX_OUTPUTS-1:0] debug_pin_data;

    localparam [31:0] PL_ENABLE = 32'h00000001;
    localparam [31:0] PL_PIN_TEST = 32'h00000100;
    localparam [31:0] PL_BUSY = 32'h00000001;
    localparam [31:0] PL_FRAME_PENDING = 32'h00000002;
    localparam [31:0] PL_UNDERRUN = 32'h00000004;
    localparam [31:0] PL_CONFIG_ERROR = 32'h00000008;

    assign status = (busy ? PL_BUSY : 32'h00000000)
        | (frame_pending ? PL_FRAME_PENDING : 32'h00000000)
        | (underrun ? PL_UNDERRUN : 32'h00000000)
        | (config_error ? PL_CONFIG_ERROR : 32'h00000000);

    assign ws2811_data = ((control & PL_PIN_TEST) != 32'h0)
        ? debug_pin_data
        : pl_ws2811_data;

    assign m_axi_awaddr = {AXI_ADDR_WIDTH{1'b0}};
    assign m_axi_awlen = 8'h00;
    assign m_axi_awsize = 3'd3;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awvalid = 1'b0;
    assign m_axi_wdata = {AXI_DATA_WIDTH{1'b0}};
    assign m_axi_wstrb = {(AXI_DATA_WIDTH/8){1'b0}};
    assign m_axi_wlast = 1'b0;
    assign m_axi_wvalid = 1'b0;
    assign m_axi_bready = 1'b1;

    axi_regs #(
        .MAX_OUTPUTS(MAX_OUTPUTS),
        .MAX_PIXELS_PER_OUTPUT(MAX_PIXELS_PER_OUTPUT),
        .ADDR_WIDTH(AXIL_ADDR_WIDTH)
    ) regs (
        .s_axi_aclk(aclk),
        .s_axi_aresetn(aresetn),
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
        .status_i(status),
        .control_o(control),
        .commit_frame_o(commit_frame),
        .active_bank_o(active_bank),
        .write_bank_o(write_bank),
        .frame_base_addr_o(frame_base_addr),
        .output_count_o(output_count),
        .output_pixel_count_o(output_pixel_count_flat),
        .output_buffer_offset_o(output_buffer_offset_flat),
        .output_flags_o(output_flags_flat),
        .frame_done_pulse_i(frame_done_pulse),
        .irq_o(irq),
        .debug_reader_state_i(debug_reader_state),
        .debug_reader_output_index_i(debug_reader_output_index),
        .debug_reader_pixel_index_i(debug_reader_pixel_index),
        .debug_axi_arvalid_cycles_i(debug_axi_arvalid_cycles),
        .debug_axi_ar_handshakes_i(debug_axi_ar_handshakes),
        .debug_axi_r_handshakes_i(debug_axi_r_handshakes),
        .debug_axi_last_araddr_i(debug_axi_last_araddr),
        .debug_axi_last_rresp_i(debug_axi_last_rresp),
        .debug_pixel_accept_count_i(debug_pixel_accept_count),
        .debug_ws_high_count_i(debug_ws_high_count)
    );

    pl_top #(
        .MAX_OUTPUTS(MAX_OUTPUTS),
        .MAX_PIXELS_PER_OUTPUT(MAX_PIXELS_PER_OUTPUT),
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH),
        .CLK_HZ(CLK_HZ)
    ) pl (
        .clk(aclk),
        .rst_n(aresetn),
        .enable((control & PL_ENABLE) != 32'h0),
        .commit_frame(commit_frame),
        .active_bank(active_bank[1:0]),
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
        .ws2811_out(pl_ws2811_data),
        .busy(busy),
        .frame_pending(frame_pending),
        .underrun(underrun),
        .config_error(config_error),
        .frame_done_pulse(frame_done_pulse),
        .debug_reader_state(debug_reader_state),
        .debug_reader_output_index(debug_reader_output_index),
        .debug_reader_pixel_index(debug_reader_pixel_index),
        .debug_pixel_accept_count(debug_pixel_accept_count),
        .debug_ws_high_count(debug_ws_high_count)
    );

    always @(posedge aclk) begin
        if (!aresetn) begin
            debug_axi_arvalid_cycles <= 32'h00000000;
            debug_axi_ar_handshakes <= 32'h00000000;
            debug_axi_r_handshakes <= 32'h00000000;
            debug_axi_last_araddr <= 32'h00000000;
            debug_axi_last_rresp <= 32'h00000000;
        end else begin
            if (m_axi_arvalid) begin
                debug_axi_arvalid_cycles <= debug_axi_arvalid_cycles + 32'd1;
            end
            if (m_axi_arvalid && m_axi_arready) begin
                debug_axi_ar_handshakes <= debug_axi_ar_handshakes + 32'd1;
                debug_axi_last_araddr <= m_axi_araddr;
            end
            if (m_axi_rvalid && m_axi_rready) begin
                debug_axi_r_handshakes <= debug_axi_r_handshakes + 32'd1;
                debug_axi_last_rresp <= {30'd0, m_axi_rresp};
            end
        end
    end

    for (genvar debug_pin_index = 0; debug_pin_index < MAX_OUTPUTS; debug_pin_index = debug_pin_index + 1) begin : gen_debug_pin_data
        assign debug_pin_data[debug_pin_index] = debug_pin_counter[26 - (debug_pin_index % 4)];
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            debug_pin_counter <= 32'h00000000;
        end else begin
            debug_pin_counter <= debug_pin_counter + 32'd1;
        end
    end

endmodule
