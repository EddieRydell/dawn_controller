`timescale 1ns / 1ps

module pl_top_tb;

    localparam int unsigned MAX_OUTPUTS = 2;
    localparam int unsigned MAX_PIXELS_PER_OUTPUT = 16;
    localparam int unsigned ADDR_WIDTH = 32;
    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned CLK_PERIOD_NS = 10;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic enable = 1'b0;
    logic commit_frame = 1'b0;
    logic [1:0] active_bank = 2'd0;
    logic [ADDR_WIDTH-1:0] frame_base_addr = 32'h0000_1000;
    logic [31:0] output_count = 32'd1;
    logic [MAX_OUTPUTS*32-1:0] output_pixel_count_flat = '0;
    logic [MAX_OUTPUTS*32-1:0] output_buffer_offset_flat = '0;
    logic [MAX_OUTPUTS*32-1:0] output_flags_flat = '0;

    logic [ADDR_WIDTH-1:0] m_axi_araddr;
    logic [7:0] m_axi_arlen;
    logic [2:0] m_axi_arsize;
    logic [1:0] m_axi_arburst;
    logic m_axi_arvalid;
    logic m_axi_arready = 1'b0;
    logic [DATA_WIDTH-1:0] m_axi_rdata = '0;
    logic [1:0] m_axi_rresp = 2'b00;
    logic m_axi_rlast = 1'b0;
    logic m_axi_rvalid = 1'b0;
    logic m_axi_rready;

    logic [MAX_OUTPUTS-1:0] ws2811_out;
    logic busy;
    logic frame_pending;
    logic underrun;
    logic config_error;
    logic frame_done_pulse;

    int unsigned ar_count = 0;
    int unsigned r_count = 0;
    int unsigned ws_high_count = 0;
    int unsigned ws_rise_count = 0;

    logic [31:0] pixel_mem [0:31];
    logic [31:0] pending_addr;
    int pending_latency = -1;
    logic last_ws;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    pl_top #(
        .MAX_OUTPUTS(MAX_OUTPUTS),
        .MAX_PIXELS_PER_OUTPUT(MAX_PIXELS_PER_OUTPUT),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .CLK_HZ(100_000_000)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .commit_frame(commit_frame),
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
        .ws2811_out(ws2811_out),
        .busy(busy),
        .frame_pending(frame_pending),
        .underrun(underrun),
        .config_error(config_error),
        .frame_done_pulse(frame_done_pulse)
    );

    function automatic logic [DATA_WIDTH-1:0] read_beat(input logic [31:0] addr);
        int unsigned word_index;
        begin
            word_index = ((addr & 32'hffff_fff8) - frame_base_addr) >> 2;
            read_beat = {pixel_mem[word_index + 1], pixel_mem[word_index]};
        end
    endfunction

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            m_axi_arready <= 1'b0;
            m_axi_rvalid <= 1'b0;
            m_axi_rlast <= 1'b0;
            m_axi_rdata <= '0;
            pending_latency <= -1;
            ar_count <= 0;
            r_count <= 0;
        end else begin
            m_axi_arready <= 1'b1;

            if (m_axi_arvalid && m_axi_arready) begin
                pending_addr <= m_axi_araddr;
                pending_latency <= 2;
                ar_count <= ar_count + 1;
            end else if (pending_latency >= 0) begin
                pending_latency <= pending_latency - 1;
            end

            if (!m_axi_rvalid && pending_latency == 0) begin
                m_axi_rdata <= read_beat(pending_addr);
                m_axi_rvalid <= 1'b1;
                m_axi_rlast <= 1'b1;
            end else if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
                m_axi_rlast <= 1'b0;
                r_count <= r_count + 1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ws_high_count <= 0;
            ws_rise_count <= 0;
            last_ws <= 1'b0;
        end else begin
            if (ws2811_out[0]) begin
                ws_high_count <= ws_high_count + 1;
            end
            if (ws2811_out[0] && !last_ws) begin
                ws_rise_count <= ws_rise_count + 1;
            end
            last_ws <= ws2811_out[0];
        end
    end

    initial begin
        if ($test$plusargs("DUMP")) begin
            $dumpfile("pl_top_tb.vcd");
            $dumpvars(0, pl_top_tb);
        end

        pixel_mem[0] = 32'h00ff_0000;
        pixel_mem[1] = 32'h0000_ff00;
        pixel_mem[2] = 32'h0000_00ff;
        pixel_mem[3] = 32'h00ff_ffff;

        output_pixel_count_flat[0 +: 32] = 32'd4;
        output_buffer_offset_flat[0 +: 32] = 32'd0;
        output_flags_flat[0 +: 32] = 32'h0000_0101;

        repeat (8) @(posedge clk);
        rst_n <= 1'b1;
        enable <= 1'b1;
        repeat (4) @(posedge clk);
        commit_frame <= 1'b1;
        @(posedge clk);
        commit_frame <= 1'b0;

        repeat (20000) @(posedge clk);

        $display("ar_count=%0d r_count=%0d ws_high_count=%0d ws_rise_count=%0d busy=%0b underrun=%0b config_error=%0b",
                 ar_count, r_count, ws_high_count, ws_rise_count, busy, underrun, config_error);

        if (ar_count == 0) begin
            $fatal(1, "pl_top did not issue any AXI read requests");
        end
        if (r_count == 0) begin
            $fatal(1, "AXI read responses were not accepted");
        end
        if (ws_high_count == 0 || ws_rise_count == 0) begin
            $fatal(1, "ws2811_out[0] never toggled high");
        end
        if (config_error) begin
            $fatal(1, "config_error asserted");
        end

        $display("PASS: pl_top read pixels and drove ws2811_out[0]");
        $finish;
    end

endmodule
