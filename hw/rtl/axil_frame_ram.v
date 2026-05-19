`timescale 1ns / 1ps

module axil_frame_ram #(
    parameter AXIL_ADDR_WIDTH = 15
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
    input  wire                       s_axi_rready
);

    axil_ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(AXIL_ADDR_WIDTH),
        .STRB_WIDTH(4),
        .PIPELINE_OUTPUT(1)
    ) frame_ram (
        .clk(aclk),
        .rst(!aresetn),
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
        .s_axil_rready(s_axi_rready)
    );

endmodule
