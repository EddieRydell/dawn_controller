`timescale 1ns / 1ps

module pl_top_tb;

    localparam int unsigned MAX_OUTPUTS = 2;
    localparam int unsigned MAX_PIXELS_PER_OUTPUT = 16;
    localparam int unsigned ADDR_WIDTH = 32;
    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned CLK_PERIOD_NS = 10;
    localparam int unsigned FRAME_WAIT_CYCLES = 22000;

    typedef enum int unsigned {
        AXI_MODE_NORMAL,
        AXI_MODE_NO_ARREADY,
        AXI_MODE_NO_RVALID,
        AXI_MODE_BAD_RRESP,
        AXI_MODE_MISSING_RLAST
    } axi_mode_t;

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
    logic [31:0] debug_reader_state;
    logic [31:0] debug_reader_output_index;
    logic [31:0] debug_reader_pixel_index;
    logic [31:0] debug_pixel_accept_count;
    logic [31:0] debug_ws_high_count;

    axi_mode_t axi_mode = AXI_MODE_NORMAL;
    int unsigned ar_ready_delay = 0;
    int unsigned read_latency = 2;
    int unsigned ar_count = 0;
    int unsigned r_count = 0;
    int unsigned ws_high_count = 0;
    int unsigned ws_rise_count = 0;
    int unsigned frame_done_count = 0;
    int unsigned config_error_count = 0;
    int unsigned missing_arready_cycles = 0;
    int pending_latency = -1;
    logic [31:0] pixel_mem [0:31];
    logic [31:0] pending_addr;
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
        .frame_done_pulse(frame_done_pulse),
        .debug_reader_state(debug_reader_state),
        .debug_reader_output_index(debug_reader_output_index),
        .debug_reader_pixel_index(debug_reader_pixel_index),
        .debug_pixel_accept_count(debug_pixel_accept_count),
        .debug_ws_high_count(debug_ws_high_count)
    );

    function automatic logic [DATA_WIDTH-1:0] read_beat(input logic [31:0] addr);
        int unsigned word_index;
        begin
            word_index = ((addr & 32'hffff_fff8) - frame_base_addr) >> 2;
            read_beat = {pixel_mem[word_index + 1], pixel_mem[word_index]};
        end
    endfunction

    task automatic init_pixels;
        begin
            for (int unsigned i = 0; i < 32; i++) begin
                pixel_mem[i] = 32'h0000_0000;
            end

            pixel_mem[0] = 32'h00ff_0000;
            pixel_mem[1] = 32'h0000_ff00;
            pixel_mem[2] = 32'h0000_00ff;
            pixel_mem[3] = 32'h00ff_ffff;
            pixel_mem[4] = 32'h0080_0000;
            pixel_mem[5] = 32'h0000_8000;
            pixel_mem[6] = 32'h0000_0080;
            pixel_mem[7] = 32'h0080_8080;
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n <= 1'b0;
            enable <= 1'b0;
            commit_frame <= 1'b0;
            active_bank <= 2'd0;
            frame_base_addr <= 32'h0000_1000;
            output_count <= 32'd1;
            output_pixel_count_flat <= '0;
            output_buffer_offset_flat <= '0;
            output_flags_flat <= '0;
            axi_mode <= AXI_MODE_NORMAL;
            ar_ready_delay <= 0;
            read_latency <= 2;
            repeat (8) @(posedge clk);
            rst_n <= 1'b1;
            repeat (4) @(posedge clk);
        end
    endtask

    task automatic configure_output0(input logic enabled, input logic [31:0] pixel_count);
        begin
            output_count <= 32'd1;
            output_pixel_count_flat[0 +: 32] <= pixel_count;
            output_buffer_offset_flat[0 +: 32] <= 32'd0;
            output_flags_flat[0 +: 32] <= {22'd0, 2'd1, 7'd0, enabled};
            enable <= 1'b1;
            @(posedge clk);
        end
    endtask

    task automatic start_frame;
        begin
            commit_frame <= 1'b1;
            @(posedge clk);
            commit_frame <= 1'b0;
        end
    endtask

    task automatic expect_idle_frame(
        input string name,
        input int unsigned expected_ar,
        input int unsigned expected_r,
        input bit expect_output
    );
        begin
            repeat (FRAME_WAIT_CYCLES) @(posedge clk);
            $display("%s: ar_count=%0d r_count=%0d ws_high_count=%0d ws_rise_count=%0d busy=%0b done=%0d underrun=%0b config_errors=%0d",
                     name, ar_count, r_count, ws_high_count, ws_rise_count, busy,
                     frame_done_count, underrun, config_error_count);

            if (ar_count != expected_ar) begin
                $fatal(1, "%s: expected %0d AR handshakes, got %0d", name, expected_ar, ar_count);
            end
            if (r_count != expected_r) begin
                $fatal(1, "%s: expected %0d R handshakes, got %0d", name, expected_r, r_count);
            end
            if (busy) begin
                $fatal(1, "%s: DUT stayed busy after frame wait", name);
            end
            if (underrun) begin
                $fatal(1, "%s: unexpected underrun", name);
            end
            if (expect_output && (ws_high_count == 0 || ws_rise_count == 0)) begin
                $fatal(1, "%s: output never toggled", name);
            end
            if (!expect_output && (ws_high_count != 0 || ws_rise_count != 0)) begin
                $fatal(1, "%s: output toggled unexpectedly", name);
            end
        end
    endtask

    always_ff @(posedge clk) begin
        if (!rst_n) begin
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
                if (m_axi_arlen != 8'd0) begin
                    $fatal(1, "unexpected AXI ARLEN: %0d", m_axi_arlen);
                end
                if (m_axi_arsize != 3'd2) begin
                    $fatal(1, "unexpected AXI ARSIZE: %0d", m_axi_arsize);
                end
                if (m_axi_arburst != 2'b01) begin
                    $fatal(1, "unexpected AXI ARBURST: %0d", m_axi_arburst);
                end
                if (m_axi_araddr[1:0] != 2'b00) begin
                    $fatal(1, "unaligned AXI read address: 0x%08x", m_axi_araddr);
                end
                if (m_axi_araddr < frame_base_addr || m_axi_araddr >= frame_base_addr + 32'd32) begin
                    $fatal(1, "AXI read address outside test frame: 0x%08x", m_axi_araddr);
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

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ws_high_count <= 0;
            ws_rise_count <= 0;
            frame_done_count <= 0;
            config_error_count <= 0;
            last_ws <= 1'b0;
        end else begin
            if (ws2811_out[0]) begin
                ws_high_count <= ws_high_count + 1;
            end
            if (ws2811_out[0] && !last_ws) begin
                ws_rise_count <= ws_rise_count + 1;
            end
            if (frame_done_pulse) begin
                frame_done_count <= frame_done_count + 1;
            end
            if (config_error) begin
                config_error_count <= config_error_count + 1;
            end
            last_ws <= ws2811_out[0];
        end
    end

    initial begin
        if ($test$plusargs("DUMP")) begin
            $dumpfile("pl_top_tb.vcd");
            $dumpvars(0, pl_top_tb);
        end

        init_pixels();

        reset_dut();
        configure_output0(1'b1, 32'd4);
        start_frame();
        expect_idle_frame("happy_path", 4, 4, 1);
        if (config_error_count != 0) begin
            $fatal(1, "happy_path: unexpected config_error pulse");
        end

        reset_dut();
        ar_ready_delay <= 3;
        read_latency <= 4;
        configure_output0(1'b1, 32'd4);
        start_frame();
        expect_idle_frame("stalling_axi_recovers", 4, 4, 1);
        if (missing_arready_cycles == 0) begin
            $fatal(1, "stalling_axi_recovers: ARREADY was never stalled");
        end

        reset_dut();
        configure_output0(1'b0, 32'd4);
        start_frame();
        expect_idle_frame("disabled_output", 0, 0, 0);

        reset_dut();
        axi_mode <= AXI_MODE_NO_ARREADY;
        configure_output0(1'b1, 32'd4);
        start_frame();
        repeat (200) @(posedge clk);
        if (!busy || ar_count != 0 || r_count != 0 || ws_high_count != 0) begin
            $fatal(1, "no_arready: expected busy wait with no output/read completion");
        end

        reset_dut();
        axi_mode <= AXI_MODE_NO_RVALID;
        configure_output0(1'b1, 32'd4);
        start_frame();
        repeat (200) @(posedge clk);
        if (!busy || ar_count != 1 || r_count != 0 || ws_high_count != 0) begin
            $fatal(1, "no_rvalid: expected busy wait after one accepted read");
        end

        reset_dut();
        axi_mode <= AXI_MODE_BAD_RRESP;
        configure_output0(1'b1, 32'd4);
        start_frame();
        repeat (7000) @(posedge clk);
        $display("bad_rresp: ar_count=%0d r_count=%0d ws_high_count=%0d busy=%0b config_errors=%0d",
                 ar_count, r_count, ws_high_count, busy, config_error_count);
        if (config_error_count == 0 || busy || ws_high_count != 0) begin
            $fatal(1, "bad_rresp: expected config_error, idle, and no output");
        end

        reset_dut();
        axi_mode <= AXI_MODE_MISSING_RLAST;
        configure_output0(1'b1, 32'd4);
        start_frame();
        repeat (7000) @(posedge clk);
        $display("missing_rlast: ar_count=%0d r_count=%0d ws_high_count=%0d busy=%0b config_errors=%0d",
                 ar_count, r_count, ws_high_count, busy, config_error_count);
        if (config_error_count == 0 || busy || ws_high_count != 0) begin
            $fatal(1, "missing_rlast: expected config_error, idle, and no output");
        end

        $display("PASS: pl_top AXI/output scenarios passed");
        $finish;
    end

endmodule
