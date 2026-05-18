`timescale 1ns / 1ps

module controller_core_bd_tb;

    localparam int unsigned MAX_OUTPUTS = 2;
    localparam int unsigned MAX_PIXELS_PER_OUTPUT = 16;
    localparam int unsigned AXIL_ADDR_WIDTH = 12;
    localparam int unsigned AXI_ADDR_WIDTH = 32;
    localparam int unsigned AXI_DATA_WIDTH = 64;
    localparam int unsigned CLK_PERIOD_NS = 10;
    localparam int unsigned FRAME_WAIT_CYCLES = 22000;

    localparam logic [31:0] PL_ENABLE = 32'h0000_0001;
    localparam logic [31:0] PL_COMMIT_FRAME = 32'h0000_0002;
    localparam logic [31:0] PL_BUSY = 32'h0000_0001;
    localparam logic [31:0] PL_CONFIG_ERROR = 32'h0000_0008;
    localparam logic [AXIL_ADDR_WIDTH-1:0] PL_REG_CONTROL = 12'h000;
    localparam logic [AXIL_ADDR_WIDTH-1:0] PL_REG_STATUS = 12'h004;
    localparam logic [AXIL_ADDR_WIDTH-1:0] PL_REG_ACTIVE_BANK = 12'h008;
    localparam logic [AXIL_ADDR_WIDTH-1:0] PL_REG_WRITE_BANK = 12'h00c;
    localparam logic [AXIL_ADDR_WIDTH-1:0] PL_REG_FRAME_COUNTER = 12'h010;
    localparam logic [AXIL_ADDR_WIDTH-1:0] PL_REG_OUTPUT_COUNT = 12'h020;
    localparam logic [AXIL_ADDR_WIDTH-1:0] PL_REG_MAX_PIXELS_PER_OUTPUT = 12'h024;
    localparam logic [AXIL_ADDR_WIDTH-1:0] PL_REG_FRAME_BASE_ADDR = 12'h028;
    localparam logic [AXIL_ADDR_WIDTH-1:0] PL_REG_OUTPUT0_PIXEL_COUNT = 12'h100;
    localparam logic [AXIL_ADDR_WIDTH-1:0] PL_REG_OUTPUT0_BUFFER_OFFSET = 12'h104;
    localparam logic [AXIL_ADDR_WIDTH-1:0] PL_REG_OUTPUT0_FLAGS = 12'h108;

    typedef enum int unsigned {
        AXI_MODE_NORMAL,
        AXI_MODE_NO_ARREADY,
        AXI_MODE_NO_RVALID,
        AXI_MODE_BAD_RRESP,
        AXI_MODE_MISSING_RLAST
    } axi_mode_t;

    logic aclk = 1'b0;
    logic aresetn = 1'b0;

    logic [AXIL_ADDR_WIDTH-1:0] s_axi_awaddr = '0;
    logic [2:0] s_axi_awprot = 3'b000;
    logic s_axi_awvalid = 1'b0;
    logic s_axi_awready;
    logic [31:0] s_axi_wdata = '0;
    logic [3:0] s_axi_wstrb = 4'hf;
    logic s_axi_wvalid = 1'b0;
    logic s_axi_wready;
    logic [1:0] s_axi_bresp;
    logic s_axi_bvalid;
    logic s_axi_bready = 1'b0;
    logic [AXIL_ADDR_WIDTH-1:0] s_axi_araddr = '0;
    logic [2:0] s_axi_arprot = 3'b000;
    logic s_axi_arvalid = 1'b0;
    logic s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [1:0] s_axi_rresp;
    logic s_axi_rvalid;
    logic s_axi_rready = 1'b0;

    logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr;
    logic [7:0] m_axi_awlen;
    logic [2:0] m_axi_awsize;
    logic [1:0] m_axi_awburst;
    logic m_axi_awvalid;
    logic m_axi_awready = 1'b1;
    logic [AXI_DATA_WIDTH-1:0] m_axi_wdata;
    logic [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb;
    logic m_axi_wlast;
    logic m_axi_wvalid;
    logic m_axi_wready = 1'b1;
    logic [1:0] m_axi_bresp = 2'b00;
    logic m_axi_bvalid = 1'b0;
    logic m_axi_bready;
    logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr;
    logic [7:0] m_axi_arlen;
    logic [2:0] m_axi_arsize;
    logic [1:0] m_axi_arburst;
    logic m_axi_arvalid;
    logic m_axi_arready = 1'b0;
    logic [AXI_DATA_WIDTH-1:0] m_axi_rdata = '0;
    logic [1:0] m_axi_rresp = 2'b00;
    logic m_axi_rlast = 1'b0;
    logic m_axi_rvalid = 1'b0;
    logic m_axi_rready;

    logic [MAX_OUTPUTS-1:0] ws2811_data;

    axi_mode_t axi_mode = AXI_MODE_NORMAL;
    int unsigned ar_ready_delay = 0;
    int unsigned read_latency = 2;
    int unsigned ar_count = 0;
    int unsigned r_count = 0;
    int unsigned ws_high_count = 0;
    int unsigned ws_rise_count = 0;
    int unsigned missing_arready_cycles = 0;
    int pending_latency = -1;
    logic [31:0] pixel_mem [0:31];
    logic [31:0] pending_addr;
    logic last_ws = 1'b0;

    always #(CLK_PERIOD_NS / 2) aclk = ~aclk;

    controller_core_bd #(
        .MAX_OUTPUTS(MAX_OUTPUTS),
        .MAX_PIXELS_PER_OUTPUT(MAX_PIXELS_PER_OUTPUT),
        .AXIL_ADDR_WIDTH(AXIL_ADDR_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .CLK_HZ(100_000_000)
    ) dut (
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
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
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
        .ws2811_data(ws2811_data)
    );

    task automatic init_pixels;
        begin
            for (int unsigned i = 0; i < 32; i++) begin
                pixel_mem[i] = 32'h0000_0000;
            end

            pixel_mem[0] = 32'h00ff_0000;
            pixel_mem[1] = 32'h0000_ff00;
            pixel_mem[2] = 32'h0000_00ff;
            pixel_mem[3] = 32'h00ff_ffff;
        end
    endtask

    task automatic reset_dut;
        begin
            aresetn <= 1'b0;
            s_axi_awaddr <= '0;
            s_axi_awvalid <= 1'b0;
            s_axi_wdata <= '0;
            s_axi_wstrb <= 4'hf;
            s_axi_wvalid <= 1'b0;
            s_axi_bready <= 1'b0;
            s_axi_araddr <= '0;
            s_axi_arvalid <= 1'b0;
            s_axi_rready <= 1'b0;
            axi_mode <= AXI_MODE_NORMAL;
            ar_ready_delay <= 0;
            read_latency <= 2;
            repeat (8) @(posedge aclk);
            aresetn <= 1'b1;
            repeat (4) @(posedge aclk);
        end
    endtask

    task automatic axil_write(input logic [AXIL_ADDR_WIDTH-1:0] addr, input logic [31:0] data);
        begin
            @(posedge aclk);
            s_axi_awaddr <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata <= data;
            s_axi_wstrb <= 4'hf;
            s_axi_wvalid <= 1'b1;
            s_axi_bready <= 1'b1;

            wait (s_axi_awready && s_axi_wready);
            @(posedge aclk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid <= 1'b0;

            wait (s_axi_bvalid);
            if (s_axi_bresp != 2'b00) begin
                $fatal(1, "AXI-Lite write got BRESP %0d", s_axi_bresp);
            end
            @(posedge aclk);
            s_axi_bready <= 1'b0;
        end
    endtask

    task automatic axil_read(input logic [AXIL_ADDR_WIDTH-1:0] addr, output logic [31:0] data);
        begin
            @(posedge aclk);
            s_axi_araddr <= addr;
            s_axi_arvalid <= 1'b1;
            s_axi_rready <= 1'b1;

            wait (s_axi_arready);
            @(posedge aclk);
            s_axi_arvalid <= 1'b0;

            wait (s_axi_rvalid);
            if (s_axi_rresp != 2'b00) begin
                $fatal(1, "AXI-Lite read got RRESP %0d", s_axi_rresp);
            end
            data = s_axi_rdata;
            @(posedge aclk);
            s_axi_rready <= 1'b0;
        end
    endtask

    task automatic program_one_output(input logic enabled);
        begin
            axil_write(PL_REG_CONTROL, 32'd0);
            axil_write(PL_REG_OUTPUT_COUNT, 32'd1);
            axil_write(PL_REG_OUTPUT0_PIXEL_COUNT, 32'd4);
            axil_write(PL_REG_OUTPUT0_BUFFER_OFFSET, 32'd0);
            axil_write(PL_REG_OUTPUT0_FLAGS, {22'd0, 2'd1, 7'd0, enabled});
            axil_write(PL_REG_WRITE_BANK, 32'd0);
            axil_write(PL_REG_FRAME_BASE_ADDR, 32'h0000_1000);
            axil_write(PL_REG_CONTROL, PL_ENABLE);
        end
    endtask

    task automatic commit_frame;
        begin
            axil_write(PL_REG_CONTROL, PL_ENABLE | PL_COMMIT_FRAME);
            axil_write(PL_REG_CONTROL, PL_ENABLE);
        end
    endtask

    task automatic expect_completed_frame(input string name, input int unsigned expected_ar, input bit expect_output);
        logic [31:0] read_value;
        begin
            repeat (FRAME_WAIT_CYCLES) @(posedge aclk);
            axil_read(PL_REG_STATUS, read_value);
            $display("%s: status=0x%08x ar_count=%0d r_count=%0d ws_high_count=%0d ws_rise_count=%0d",
                     name, read_value, ar_count, r_count, ws_high_count, ws_rise_count);

            if (read_value != 32'h0000_0000) begin
                $fatal(1, "%s: expected idle status, got 0x%08x", name, read_value);
            end
            if (ar_count != expected_ar || r_count != expected_ar) begin
                $fatal(1, "%s: expected %0d AXI reads, got AR=%0d R=%0d", name, expected_ar, ar_count, r_count);
            end
            if (expect_output && (ws_high_count == 0 || ws_rise_count == 0)) begin
                $fatal(1, "%s: ws2811_data[0] never toggled", name);
            end
            if (!expect_output && (ws_high_count != 0 || ws_rise_count != 0)) begin
                $fatal(1, "%s: ws2811_data[0] toggled unexpectedly", name);
            end

            axil_read(PL_REG_FRAME_COUNTER, read_value);
            if (read_value != 32'd1) begin
                $fatal(1, "%s: frame counter mismatch: 0x%08x", name, read_value);
            end
            axil_read(PL_REG_ACTIVE_BANK, read_value);
            if (read_value != 32'd0) begin
                $fatal(1, "%s: active bank mismatch: 0x%08x", name, read_value);
            end
        end
    endtask

    function automatic logic [AXI_DATA_WIDTH-1:0] read_beat(input logic [31:0] addr);
        int unsigned word_index;
        begin
            word_index = ((addr & 32'hffff_fff8) - 32'h0000_1000) >> 2;
            read_beat = {pixel_mem[word_index + 1], pixel_mem[word_index]};
        end
    endfunction

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            m_axi_arready <= 1'b0;
            m_axi_rvalid <= 1'b0;
            m_axi_rlast <= 1'b0;
            m_axi_rdata <= '0;
            m_axi_rresp <= 2'b00;
            pending_latency <= -1;
            ar_count <= 0;
            r_count <= 0;
            missing_arready_cycles <= 0;
        end else begin
            if (m_axi_awvalid || m_axi_wvalid) begin
                $fatal(1, "controller_core_bd unexpectedly issued an AXI write");
            end

            if (axi_mode == AXI_MODE_NO_ARREADY) begin
                m_axi_arready <= 1'b0;
            end else if (ar_count == 0 && missing_arready_cycles < ar_ready_delay) begin
                m_axi_arready <= 1'b0;
            end else begin
                m_axi_arready <= 1'b1;
            end

            if (m_axi_arvalid && !m_axi_arready) begin
                missing_arready_cycles <= missing_arready_cycles + 1;
            end

            if (m_axi_arvalid && m_axi_arready) begin
                if (m_axi_arlen != 8'd0 || m_axi_arsize != 3'd2 || m_axi_arburst != 2'b01) begin
                    $fatal(1, "bad AXI read command len=%0d size=%0d burst=%0d",
                           m_axi_arlen, m_axi_arsize, m_axi_arburst);
                end
                if (m_axi_araddr[1:0] != 2'b00
                    || m_axi_araddr < 32'h0000_1000
                    || m_axi_araddr >= 32'h0000_1020) begin
                    $fatal(1, "unexpected AXI read address: 0x%08x", m_axi_araddr);
                end

                pending_addr <= m_axi_araddr;
                pending_latency <= int'(read_latency);
                ar_count <= ar_count + 1;
            end else if (pending_latency >= 0) begin
                pending_latency <= pending_latency - 1;
            end

            if (axi_mode != AXI_MODE_NO_RVALID && !m_axi_rvalid && pending_latency == 0) begin
                m_axi_rdata <= read_beat(pending_addr);
                m_axi_rresp <= (axi_mode == AXI_MODE_BAD_RRESP) ? 2'b10 : 2'b00;
                m_axi_rvalid <= 1'b1;
                m_axi_rlast <= (axi_mode == AXI_MODE_MISSING_RLAST) ? 1'b0 : 1'b1;
            end else if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
                m_axi_rlast <= 1'b0;
                m_axi_rresp <= 2'b00;
                r_count <= r_count + 1;
            end
        end
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            ws_high_count <= 0;
            ws_rise_count <= 0;
            last_ws <= 1'b0;
        end else begin
            if (ws2811_data[0]) begin
                ws_high_count <= ws_high_count + 1;
            end
            if (ws2811_data[0] && !last_ws) begin
                ws_rise_count <= ws_rise_count + 1;
            end
            last_ws <= ws2811_data[0];
        end
    end

    initial begin
        logic [31:0] read_value;

        if ($test$plusargs("DUMP")) begin
            $dumpfile("controller_core_bd_tb.vcd");
            $dumpvars(0, controller_core_bd_tb);
        end

        init_pixels();

        reset_dut();
        program_one_output(1'b1);
        axil_read(PL_REG_MAX_PIXELS_PER_OUTPUT, read_value);
        if (read_value != MAX_PIXELS_PER_OUTPUT) begin
            $fatal(1, "bad MAX_PIXELS_PER_OUTPUT readback: 0x%08x", read_value);
        end
        commit_frame();
        expect_completed_frame("happy_path", 4, 1);

        reset_dut();
        ar_ready_delay <= 3;
        read_latency <= 4;
        program_one_output(1'b1);
        commit_frame();
        expect_completed_frame("stalling_axi_recovers", 4, 1);
        if (missing_arready_cycles == 0) begin
            $fatal(1, "stalling_axi_recovers: ARREADY was never stalled");
        end

        reset_dut();
        program_one_output(1'b0);
        commit_frame();
        expect_completed_frame("disabled_output", 0, 0);

        reset_dut();
        axi_mode <= AXI_MODE_NO_ARREADY;
        program_one_output(1'b1);
        commit_frame();
        repeat (200) @(posedge aclk);
        axil_read(PL_REG_STATUS, read_value);
        if ((read_value & PL_BUSY) == 32'h0 || ar_count != 0 || r_count != 0 || ws_high_count != 0) begin
            $fatal(1, "no_arready: expected busy wait with no accepted reads, status=0x%08x", read_value);
        end

        reset_dut();
        axi_mode <= AXI_MODE_NO_RVALID;
        program_one_output(1'b1);
        commit_frame();
        repeat (200) @(posedge aclk);
        axil_read(PL_REG_STATUS, read_value);
        if ((read_value & PL_BUSY) == 32'h0 || ar_count != 1 || r_count != 0 || ws_high_count != 0) begin
            $fatal(1, "no_rvalid: expected busy wait after one read request, status=0x%08x", read_value);
        end

        reset_dut();
        axi_mode <= AXI_MODE_BAD_RRESP;
        program_one_output(1'b1);
        commit_frame();
        repeat (7000) @(posedge aclk);
        axil_read(PL_REG_STATUS, read_value);
        $display("bad_rresp: status=0x%08x ar_count=%0d r_count=%0d ws_high_count=%0d",
                 read_value, ar_count, r_count, ws_high_count);
        if ((read_value & PL_CONFIG_ERROR) == 32'h0 || (read_value & PL_BUSY) != 32'h0 || ws_high_count != 0) begin
            $fatal(1, "bad_rresp: expected sticky config error and idle output");
        end
        axil_write(PL_REG_CONTROL, 32'd0);
        repeat (2) @(posedge aclk);
        axil_read(PL_REG_STATUS, read_value);
        if ((read_value & PL_CONFIG_ERROR) != 32'h0) begin
            $fatal(1, "bad_rresp: disabling control did not clear sticky config error");
        end

        reset_dut();
        axi_mode <= AXI_MODE_MISSING_RLAST;
        program_one_output(1'b1);
        commit_frame();
        repeat (7000) @(posedge aclk);
        axil_read(PL_REG_STATUS, read_value);
        $display("missing_rlast: status=0x%08x ar_count=%0d r_count=%0d ws_high_count=%0d",
                 read_value, ar_count, r_count, ws_high_count);
        if ((read_value & PL_CONFIG_ERROR) == 32'h0 || (read_value & PL_BUSY) != 32'h0 || ws_high_count != 0) begin
            $fatal(1, "missing_rlast: expected sticky config error and idle output");
        end

        $display("PASS: controller_core_bd AXI-Lite, master AXI, and output scenarios passed");
        $finish;
    end

endmodule
