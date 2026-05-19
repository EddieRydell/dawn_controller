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
    input  wire                       s_axi_rready,

    input  wire [AXIL_ADDR_WIDTH-1:0] rd_araddr,
    input  wire                       rd_arvalid,
    output wire                       rd_arready,
    output wire [31:0]                rd_rdata,
    output wire [1:0]                 rd_rresp,
    output wire                       rd_rvalid,
    input  wire                       rd_rready
);

    localparam VALID_ADDR_WIDTH = AXIL_ADDR_WIDTH - 2;

    (* ram_style = "block" *)
    reg [31:0] mem[(2**VALID_ADDR_WIDTH)-1:0];

    reg [AXIL_ADDR_WIDTH-1:0] awaddr_reg;
    reg [31:0] wdata_reg;
    reg [3:0] wstrb_reg;
    reg aw_seen_reg;
    reg w_seen_reg;
    reg s_axi_awready_reg;
    reg s_axi_wready_reg;
    reg s_axi_bvalid_reg;
    reg s_axi_arready_reg;
    reg [31:0] s_axi_rdata_reg;
    reg s_axi_rvalid_reg;
    reg rd_arready_reg;
    reg [31:0] rd_rdata_reg;
    reg rd_rvalid_reg;

    reg [AXIL_ADDR_WIDTH-1:0] write_addr;
    reg [31:0] write_data;
    reg [3:0] write_strb;
    integer i;

    assign s_axi_awready = s_axi_awready_reg;
    assign s_axi_wready = s_axi_wready_reg;
    assign s_axi_bresp = 2'b00;
    assign s_axi_bvalid = s_axi_bvalid_reg;
    assign s_axi_arready = s_axi_arready_reg;
    assign s_axi_rdata = s_axi_rdata_reg;
    assign s_axi_rresp = 2'b00;
    assign s_axi_rvalid = s_axi_rvalid_reg;
    assign rd_arready = rd_arready_reg;
    assign rd_rdata = rd_rdata_reg;
    assign rd_rresp = 2'b00;
    assign rd_rvalid = rd_rvalid_reg;

    always @(posedge aclk) begin
        if (!aresetn) begin
            awaddr_reg <= {AXIL_ADDR_WIDTH{1'b0}};
            wdata_reg <= 32'h0000_0000;
            wstrb_reg <= 4'h0;
            aw_seen_reg <= 1'b0;
            w_seen_reg <= 1'b0;
            s_axi_awready_reg <= 1'b0;
            s_axi_wready_reg <= 1'b0;
            s_axi_bvalid_reg <= 1'b0;
            s_axi_arready_reg <= 1'b0;
            s_axi_rdata_reg <= 32'h0000_0000;
            s_axi_rvalid_reg <= 1'b0;
            rd_arready_reg <= 1'b0;
            rd_rdata_reg <= 32'h0000_0000;
            rd_rvalid_reg <= 1'b0;
        end else begin
            s_axi_awready_reg <= 1'b0;
            s_axi_wready_reg <= 1'b0;
            s_axi_arready_reg <= 1'b0;
            rd_arready_reg <= 1'b0;

            if (!aw_seen_reg && !s_axi_bvalid_reg && s_axi_awvalid) begin
                awaddr_reg <= s_axi_awaddr;
                aw_seen_reg <= 1'b1;
                s_axi_awready_reg <= 1'b1;
            end

            if (!w_seen_reg && !s_axi_bvalid_reg && s_axi_wvalid) begin
                wdata_reg <= s_axi_wdata;
                wstrb_reg <= s_axi_wstrb;
                w_seen_reg <= 1'b1;
                s_axi_wready_reg <= 1'b1;
            end

            if (!s_axi_bvalid_reg
                && ((aw_seen_reg && w_seen_reg)
                    || (aw_seen_reg && s_axi_wvalid)
                    || (w_seen_reg && s_axi_awvalid)
                    || (s_axi_awvalid && s_axi_wvalid))) begin
                write_addr = aw_seen_reg ? awaddr_reg : s_axi_awaddr;
                write_data = w_seen_reg ? wdata_reg : s_axi_wdata;
                write_strb = w_seen_reg ? wstrb_reg : s_axi_wstrb;

                for (i = 0; i < 4; i = i + 1) begin
                    if (write_strb[i]) begin
                        mem[write_addr[AXIL_ADDR_WIDTH-1:2]][i*8 +: 8] <= write_data[i*8 +: 8];
                    end
                end

                aw_seen_reg <= 1'b0;
                w_seen_reg <= 1'b0;
                s_axi_bvalid_reg <= 1'b1;
            end else if (s_axi_bvalid_reg && s_axi_bready) begin
                s_axi_bvalid_reg <= 1'b0;
            end

            if (!s_axi_rvalid_reg && s_axi_arvalid) begin
                s_axi_arready_reg <= 1'b1;
                s_axi_rdata_reg <= mem[s_axi_araddr[AXIL_ADDR_WIDTH-1:2]];
                s_axi_rvalid_reg <= 1'b1;
            end else if (s_axi_rvalid_reg && s_axi_rready) begin
                s_axi_rvalid_reg <= 1'b0;
            end

            if (!rd_rvalid_reg && rd_arvalid) begin
                rd_arready_reg <= 1'b1;
                rd_rdata_reg <= mem[rd_araddr[AXIL_ADDR_WIDTH-1:2]];
                rd_rvalid_reg <= 1'b1;
            end else if (rd_rvalid_reg && rd_rready) begin
                rd_rvalid_reg <= 1'b0;
            end
        end
    end

endmodule
