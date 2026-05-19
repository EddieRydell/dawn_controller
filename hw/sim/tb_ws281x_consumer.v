`timescale 1ns / 1ps
`include "../rtl/pl_contract.vh"

module tb_ws281x_consumer;
    localparam AXIL_ADDR_WIDTH = 12;
    localparam FRAME_ADDR_WIDTH = 6;
    localparam OUTPUT_COUNT = 4;
    localparam PIXELS_PER_OUTPUT = 2;
    localparam FRAME_WORDS = 16;

    reg aclk = 1'b0;
    reg aresetn = 1'b0;

    reg [AXIL_ADDR_WIDTH-1:0] ctl_awaddr = {AXIL_ADDR_WIDTH{1'b0}};
    reg [2:0] ctl_awprot = 3'b000;
    reg ctl_awvalid = 1'b0;
    wire ctl_awready;
    reg [31:0] ctl_wdata = 32'h0000_0000;
    reg [3:0] ctl_wstrb = 4'hf;
    reg ctl_wvalid = 1'b0;
    wire ctl_wready;
    wire [1:0] ctl_bresp;
    wire ctl_bvalid;
    reg ctl_bready = 1'b1;
    reg [AXIL_ADDR_WIDTH-1:0] ctl_araddr = {AXIL_ADDR_WIDTH{1'b0}};
    reg [2:0] ctl_arprot = 3'b000;
    reg ctl_arvalid = 1'b0;
    wire ctl_arready;
    wire [31:0] ctl_rdata;
    wire [1:0] ctl_rresp;
    wire ctl_rvalid;
    reg ctl_rready = 1'b1;

    reg [FRAME_ADDR_WIDTH-1:0] ram_awaddr = {FRAME_ADDR_WIDTH{1'b0}};
    reg [2:0] ram_awprot = 3'b000;
    reg ram_awvalid = 1'b0;
    wire ram_awready;
    reg [31:0] ram_wdata = 32'h0000_0000;
    reg [3:0] ram_wstrb = 4'hf;
    reg ram_wvalid = 1'b0;
    wire ram_wready;
    wire [1:0] ram_bresp;
    wire ram_bvalid;
    reg ram_bready = 1'b1;
    reg [FRAME_ADDR_WIDTH-1:0] ram_araddr = {FRAME_ADDR_WIDTH{1'b0}};
    reg [2:0] ram_arprot = 3'b000;
    reg ram_arvalid = 1'b0;
    wire ram_arready;
    wire [31:0] ram_rdata;
    wire [1:0] ram_rresp;
    wire ram_rvalid;
    reg ram_rready = 1'b1;

    wire [OUTPUT_COUNT-1:0] ws281x_data;
    wire [FRAME_ADDR_WIDTH-1:0] frame_araddr;
    wire frame_arvalid;
    wire frame_arready;
    wire [31:0] frame_rdata;
    wire [1:0] frame_rresp;
    wire frame_rvalid;
    wire frame_rready;

    integer i;
    integer word_addr;
    reg [31:0] write_bank;
    reg [31:0] bank_words;
    reg [31:0] read_data;

    always #5 aclk = ~aclk;

    eth_control_core #(
        .AXIL_ADDR_WIDTH(AXIL_ADDR_WIDTH),
        .FRAME_WORDS(FRAME_WORDS),
        .FRAME_ADDR_WIDTH(FRAME_ADDR_WIDTH),
        .OUTPUT_COUNT(OUTPUT_COUNT),
        .PIXELS_PER_OUTPUT(PIXELS_PER_OUTPUT),
        .CLK_HZ(100000000),
        .WS281X_BIT_RATE(800000)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awaddr(ctl_awaddr),
        .s_axi_awprot(ctl_awprot),
        .s_axi_awvalid(ctl_awvalid),
        .s_axi_awready(ctl_awready),
        .s_axi_wdata(ctl_wdata),
        .s_axi_wstrb(ctl_wstrb),
        .s_axi_wvalid(ctl_wvalid),
        .s_axi_wready(ctl_wready),
        .s_axi_bresp(ctl_bresp),
        .s_axi_bvalid(ctl_bvalid),
        .s_axi_bready(ctl_bready),
        .s_axi_araddr(ctl_araddr),
        .s_axi_arprot(ctl_arprot),
        .s_axi_arvalid(ctl_arvalid),
        .s_axi_arready(ctl_arready),
        .s_axi_rdata(ctl_rdata),
        .s_axi_rresp(ctl_rresp),
        .s_axi_rvalid(ctl_rvalid),
        .s_axi_rready(ctl_rready),
        .ws281x_data(ws281x_data),
        .m_frame_araddr(frame_araddr),
        .m_frame_arvalid(frame_arvalid),
        .m_frame_arready(frame_arready),
        .m_frame_rdata(frame_rdata),
        .m_frame_rresp(frame_rresp),
        .m_frame_rvalid(frame_rvalid),
        .m_frame_rready(frame_rready)
    );

    axil_frame_ram #(
        .AXIL_ADDR_WIDTH(FRAME_ADDR_WIDTH)
    ) frame_ram (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awaddr(ram_awaddr),
        .s_axi_awprot(ram_awprot),
        .s_axi_awvalid(ram_awvalid),
        .s_axi_awready(ram_awready),
        .s_axi_wdata(ram_wdata),
        .s_axi_wstrb(ram_wstrb),
        .s_axi_wvalid(ram_wvalid),
        .s_axi_wready(ram_wready),
        .s_axi_bresp(ram_bresp),
        .s_axi_bvalid(ram_bvalid),
        .s_axi_bready(ram_bready),
        .s_axi_araddr(ram_araddr),
        .s_axi_arprot(ram_arprot),
        .s_axi_arvalid(ram_arvalid),
        .s_axi_arready(ram_arready),
        .s_axi_rdata(ram_rdata),
        .s_axi_rresp(ram_rresp),
        .s_axi_rvalid(ram_rvalid),
        .s_axi_rready(ram_rready),
        .rd_araddr(frame_araddr),
        .rd_arvalid(frame_arvalid),
        .rd_arready(frame_arready),
        .rd_rdata(frame_rdata),
        .rd_rresp(frame_rresp),
        .rd_rvalid(frame_rvalid),
        .rd_rready(frame_rready)
    );

    task ctl_write;
        input [AXIL_ADDR_WIDTH-1:0] addr;
        input [31:0] data;
        begin
            @(posedge aclk);
            ctl_awaddr <= addr;
            ctl_wdata <= data;
            ctl_awvalid <= 1'b1;
            ctl_wvalid <= 1'b1;
            wait (ctl_awready && ctl_wready);
            @(posedge aclk);
            ctl_awvalid <= 1'b0;
            ctl_wvalid <= 1'b0;
            wait (ctl_bvalid);
            @(posedge aclk);
        end
    endtask

    task ctl_read;
        input [AXIL_ADDR_WIDTH-1:0] addr;
        output [31:0] data;
        begin
            @(posedge aclk);
            ctl_araddr <= addr;
            ctl_arvalid <= 1'b1;
            wait (ctl_arready);
            @(posedge aclk);
            ctl_arvalid <= 1'b0;
            wait (ctl_rvalid);
            data = ctl_rdata;
            @(posedge aclk);
        end
    endtask

    task ram_write;
        input [FRAME_ADDR_WIDTH-1:0] addr;
        input [31:0] data;
        begin
            @(posedge aclk);
            ram_awaddr <= addr;
            ram_wdata <= data;
            ram_awvalid <= 1'b1;
            ram_wvalid <= 1'b1;
            wait (ram_awready && ram_wready);
            @(posedge aclk);
            ram_awvalid <= 1'b0;
            ram_wvalid <= 1'b0;
            wait (ram_bvalid);
            @(posedge aclk);
        end
    endtask

    initial begin
        repeat (8) @(posedge aclk);
        aresetn <= 1'b1;
        repeat (8) @(posedge aclk);

        ctl_read(`PL_REG_ID, read_data);
        if (read_data != `PL_CORE_ID) begin
            $fatal(1, "core ID is %08x", read_data);
        end
        ctl_read(`PL_REG_VERSION, read_data);
        if (read_data != `PL_CORE_VERSION) begin
            $fatal(1, "core version is %08x", read_data);
        end

        ctl_read(`PL_REG_FRAME_BANK_WORDS, bank_words);
        ctl_read(`PL_REG_WRITE_BANK, write_bank);
        if (write_bank > 1) begin
            $fatal(1, "write bank is %08x", write_bank);
        end

        ctl_write(`PL_REG_FRAME_COMMIT, bank_words + 1);
        ctl_read(`PL_REG_STATUS, read_data);
        if ((read_data & `PL_STATUS_OVERFLOW) == 0) begin
            $fatal(1, "oversized commit did not set overflow: %08x", read_data);
        end
        ctl_read(`PL_REG_ERROR_COUNT, read_data);
        if (read_data != 32'h0000_0001) begin
            $fatal(1, "oversized commit error count is %08x", read_data);
        end
        ctl_write(`PL_REG_CONTROL, 32'h0000_0002);
        ctl_read(`PL_REG_STATUS, read_data);
        if (read_data != `PL_STATUS_READY) begin
            $fatal(1, "clear errors left status %08x", read_data);
        end

        for (i = 0; i < OUTPUT_COUNT * PIXELS_PER_OUTPUT; i = i + 1) begin
            word_addr = (write_bank * bank_words) + i;
            ram_write(word_addr[FRAME_ADDR_WIDTH-3:0] << 2, 32'h0001_0203 + i);
        end

        ctl_write(`PL_REG_FRAME_COMMIT, (write_bank << 31) | (OUTPUT_COUNT * PIXELS_PER_OUTPUT));
        ctl_read(`PL_REG_ACTIVE_BANK, read_data);
        if (read_data != write_bank) begin
            $fatal(1, "active bank is %08x expected %08x", read_data, write_bank);
        end
        ctl_read(`PL_REG_WRITE_BANK, read_data);
        if (read_data != (write_bank ^ 32'h0000_0001)) begin
            $fatal(1, "next write bank is %08x", read_data);
        end

        ctl_write(`PL_REG_CONSUMER_CONTROL, `PL_CONSUMER_RESET);
        ctl_write(`PL_REG_CONTROL, 32'h0000_0002);
        ctl_write(`PL_REG_CONSUMER_CONTROL, `PL_CONSUMER_ENABLE);

        for (i = 0; i < 200000; i = i + 1) begin
            ctl_read(`PL_REG_CONSUMER_FRAME_COUNT, read_data);
            if (read_data == 32'h0000_0001) begin
                ctl_read(`PL_REG_CONSUMER_ERROR_COUNT, read_data);
                if (read_data != 32'h0000_0000) begin
                    $fatal(1, "consumer error count is %08x", read_data);
                end
                ctl_read(`PL_REG_CONSUMER_SEQUENCE, read_data);
                if (read_data != 32'h0000_0001) begin
                    $fatal(1, "consumer sequence is %08x", read_data);
                end
                $display("WS281x consumer simulation passed");
                $finish;
            end
        end

        ctl_read(`PL_REG_CONSUMER_STATUS, read_data);
        $display("CONSUMER_STATUS=%08x", read_data);
        ctl_read(`PL_REG_CONSUMER_DEBUG, read_data);
        $display("CONSUMER_DEBUG=%08x", read_data);
        ctl_read(`PL_REG_FRAME_COUNT, read_data);
        $display("FRAME_COUNT=%08x", read_data);
        ctl_read(`PL_REG_COMMITTED_WORDS, read_data);
        $display("COMMITTED_WORDS=%08x", read_data);
        ctl_read(`PL_REG_ACTIVE_BANK, read_data);
        $display("ACTIVE_BANK=%08x", read_data);
        ctl_read(`PL_REG_FRAME_SEQUENCE, read_data);
        $display("FRAME_SEQUENCE=%08x", read_data);
        $fatal(1, "consumer did not complete");
    end
endmodule
