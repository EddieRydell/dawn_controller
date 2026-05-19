`timescale 1ns / 1ps

module eth_frame_core #(
    parameter AXIL_ADDR_WIDTH = 12,
    parameter FRAME_WORDS = 8192,
    parameter FRAME_INDEX_WIDTH = 13
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
    output reg                        s_axi_awready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0]                s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]                 s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire                       s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output reg                        s_axi_wready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output reg [1:0]                  s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output reg                        s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire                       s_axi_bready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [AXIL_ADDR_WIDTH-1:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0]                 s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire                       s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output reg                        s_axi_arready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output reg [31:0]                 s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output reg [1:0]                  s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output reg                        s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire                       s_axi_rready,

    output wire [3:0]                 pl_data
);

    localparam [31:0] CORE_ID = 32'h4546_504c; // "EFPL"
    localparam [31:0] CORE_VERSION = 32'h0001_0000;

    localparam [AXIL_ADDR_WIDTH-1:0] REG_ID              = 12'h000;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_VERSION         = 12'h004;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_CONTROL         = 12'h008;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_STATUS          = 12'h00c;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_PIN_OUT         = 12'h010;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_COUNTER         = 12'h014;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_FRAME_CAPACITY  = 12'h018;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_FRAME_INDEX     = 12'h020;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_FRAME_WORDS     = 12'h024;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_FRAME_DATA      = 12'h028;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_FRAME_COMMIT    = 12'h02c;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_FRAME_COUNT     = 12'h030;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_COMMITTED_WORDS = 12'h034;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_LAST_FRAME_WORD = 12'h038;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_ERROR_COUNT     = 12'h03c;

    localparam [31:0] STATUS_READY = 32'h0000_0001;
    localparam [31:0] STATUS_OVERFLOW = 32'h0000_0002;

    reg [AXIL_ADDR_WIDTH-1:0] awaddr_reg;
    reg [31:0] wdata_reg;
    reg [3:0] wstrb_reg;
    reg aw_seen;
    reg w_seen;

    reg [31:0] control_reg;
    reg [31:0] status_reg;
    reg [31:0] pin_out_reg;
    reg [31:0] counter_reg;
    reg [31:0] frame_index_reg;
    reg [31:0] frame_words_reg;
    reg [31:0] frame_count_reg;
    reg [31:0] committed_words_reg;
    reg [31:0] last_frame_word_reg;
    reg [31:0] first_frame_word_reg;
    reg [31:0] error_count_reg;
    (* ram_style = "block" *) reg [31:0] frame_ram [0:FRAME_WORDS-1];
    reg [FRAME_INDEX_WIDTH-1:0] frame_read_addr_reg;
    reg frame_read_pending;

    reg [AXIL_ADDR_WIDTH-1:0] write_addr;
    reg [31:0] write_data;
    reg [3:0] write_strb;

    assign pl_data = pin_out_reg[3:0];

    function [31:0] apply_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0] strobe;
        integer i;
        begin
            apply_wstrb = old_value;
            for (i = 0; i < 4; i = i + 1) begin
                if (strobe[i]) begin
                    apply_wstrb[i*8 +: 8] = new_value[i*8 +: 8];
                end
            end
        end
    endfunction

    function [31:0] read_register;
        input [AXIL_ADDR_WIDTH-1:0] addr;
        begin
            case (addr)
            REG_ID:              read_register = CORE_ID;
            REG_VERSION:         read_register = CORE_VERSION;
            REG_CONTROL:         read_register = control_reg;
            REG_STATUS:          read_register = status_reg;
            REG_PIN_OUT:         read_register = pin_out_reg;
            REG_COUNTER:         read_register = counter_reg;
            REG_FRAME_CAPACITY:  read_register = FRAME_WORDS;
            REG_FRAME_INDEX:     read_register = frame_index_reg;
            REG_FRAME_WORDS:     read_register = frame_words_reg;
            REG_FRAME_DATA:      read_register = last_frame_word_reg;
            REG_FRAME_COMMIT:    read_register = 32'h0000_0000;
            REG_FRAME_COUNT:     read_register = frame_count_reg;
            REG_COMMITTED_WORDS: read_register = committed_words_reg;
            REG_LAST_FRAME_WORD: read_register = last_frame_word_reg;
            REG_ERROR_COUNT:     read_register = error_count_reg;
            default:             read_register = 32'h0000_0000;
            endcase
        end
    endfunction

    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
            s_axi_arready <= 1'b0;
            s_axi_rdata <= 32'h0000_0000;
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b0;
            awaddr_reg <= {AXIL_ADDR_WIDTH{1'b0}};
            wdata_reg <= 32'h0000_0000;
            wstrb_reg <= 4'h0;
            aw_seen <= 1'b0;
            w_seen <= 1'b0;
            control_reg <= 32'h0000_0000;
            status_reg <= STATUS_READY;
            pin_out_reg <= 32'h0000_0000;
            counter_reg <= 32'h0000_0000;
            frame_index_reg <= 32'h0000_0000;
            frame_words_reg <= 32'h0000_0000;
            frame_count_reg <= 32'h0000_0000;
            committed_words_reg <= 32'h0000_0000;
            last_frame_word_reg <= 32'h0000_0000;
            first_frame_word_reg <= 32'h0000_0000;
            error_count_reg <= 32'h0000_0000;
            frame_read_addr_reg <= {FRAME_INDEX_WIDTH{1'b0}};
            frame_read_pending <= 1'b0;
        end else begin
            counter_reg <= counter_reg + 32'd1;
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_arready <= 1'b0;

            if (!aw_seen && !s_axi_bvalid && s_axi_awvalid) begin
                awaddr_reg <= s_axi_awaddr;
                aw_seen <= 1'b1;
                s_axi_awready <= 1'b1;
            end

            if (!w_seen && !s_axi_bvalid && s_axi_wvalid) begin
                wdata_reg <= s_axi_wdata;
                wstrb_reg <= s_axi_wstrb;
                w_seen <= 1'b1;
                s_axi_wready <= 1'b1;
            end

            if (!s_axi_bvalid
                && ((aw_seen && w_seen)
                    || (aw_seen && s_axi_wvalid)
                    || (w_seen && s_axi_awvalid)
                    || (s_axi_awvalid && s_axi_wvalid))) begin
                write_addr = aw_seen ? awaddr_reg : s_axi_awaddr;
                write_data = w_seen ? wdata_reg : s_axi_wdata;
                write_strb = w_seen ? wstrb_reg : s_axi_wstrb;

                case (write_addr)
                REG_CONTROL: begin
                    control_reg <= apply_wstrb(control_reg, write_data, write_strb);
                    if (write_data[1]) begin
                        status_reg <= STATUS_READY;
                    end
                end
                REG_PIN_OUT: begin
                    pin_out_reg <= apply_wstrb(pin_out_reg, write_data, write_strb);
                end
                REG_FRAME_INDEX: begin
                    frame_index_reg <= apply_wstrb(frame_index_reg, write_data, write_strb);
                    frame_words_reg <= 32'h0000_0000;
                    first_frame_word_reg <= 32'h0000_0000;
                    status_reg <= STATUS_READY;
                end
                REG_FRAME_DATA: begin
                    if (frame_index_reg < FRAME_WORDS) begin
                        frame_ram[frame_index_reg[FRAME_INDEX_WIDTH-1:0]] <= write_data;
                        last_frame_word_reg <= write_data;
                        if (frame_words_reg == 32'h0000_0000) begin
                            first_frame_word_reg <= write_data;
                        end
                        frame_index_reg <= frame_index_reg + 32'd1;
                        if (frame_words_reg < FRAME_WORDS) begin
                            frame_words_reg <= frame_words_reg + 32'd1;
                        end
                    end else begin
                        status_reg <= STATUS_READY | STATUS_OVERFLOW;
                        error_count_reg <= error_count_reg + 32'd1;
                    end
                end
                REG_FRAME_COMMIT: begin
                    frame_count_reg <= frame_count_reg + 32'd1;
                    committed_words_reg <= frame_words_reg;
                    pin_out_reg <= first_frame_word_reg;
                end
                default: begin
                end
                endcase

                aw_seen <= 1'b0;
                w_seen <= 1'b0;
                s_axi_bresp <= 2'b00;
                s_axi_bvalid <= 1'b1;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (frame_read_pending) begin
                s_axi_rdata <= frame_ram[frame_read_addr_reg];
                s_axi_rresp <= 2'b00;
                s_axi_rvalid <= 1'b1;
                frame_read_pending <= 1'b0;
            end else if (!s_axi_rvalid && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                if (s_axi_araddr == REG_FRAME_DATA) begin
                    frame_read_addr_reg <= frame_index_reg[FRAME_INDEX_WIDTH-1:0];
                    frame_read_pending <= 1'b1;
                end else begin
                    s_axi_rdata <= read_register(s_axi_araddr);
                    s_axi_rresp <= 2'b00;
                    s_axi_rvalid <= 1'b1;
                end
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
