`timescale 1ns / 1ps

module eth_control_core_impl #(
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

    output logic [FRAME_ADDR_WIDTH-1:0] m_frame_araddr,
    output logic                       m_frame_arvalid,
    input  wire                       m_frame_arready,
    input  wire [31:0]                m_frame_rdata,
    input  wire [1:0]                 m_frame_rresp,
    input  wire                       m_frame_rvalid,
    output wire                       m_frame_rready
);

    import pl_control_regs_pkg::*;

    localparam [31:0] STATUS_READY = 32'h0000_0001;
    localparam [31:0] STATUS_OVERFLOW = 32'h0000_0002;
    localparam [31:0] STATUS_CONSUMER_ERROR = 32'h0000_0004;
    localparam [31:0] FRAME_WORDS_PER_BANK = FRAME_WORDS / 2;
    localparam [31:0] FRAME_WORDS_REQUIRED = OUTPUT_COUNT * PIXELS_PER_OUTPUT;
    localparam integer WS_BIT_CYCLES = CLK_HZ / WS281X_BIT_RATE;
    localparam integer WS_T0H_CYCLES = 35;
    localparam integer WS_T1H_CYCLES = 70;
    localparam integer WS_RESET_CYCLES = 28000;

    localparam [2:0] TX_IDLE = 3'd0;
    localparam [2:0] TX_LOAD_FIRST = 3'd1;
    localparam [2:0] TX_SEND = 3'd2;
    localparam [2:0] TX_RESET = 3'd3;
    localparam [2:0] TX_ERROR = 3'd4;

    localparam [1:0] RD_IDLE = 2'd0;
    localparam [1:0] RD_ADDR = 2'd1;
    localparam [1:0] RD_DATA = 2'd2;

    pl_control__in_t hwif_in;
    pl_control__out_t hwif_out;

    logic [31:0] status_reg;
    logic [31:0] counter_reg;
    logic [31:0] frame_count_reg;
    logic [31:0] committed_words_reg;
    logic [31:0] committed_first_frame_word_reg;
    logic [31:0] committed_last_frame_word_reg;
    logic [31:0] staged_first_frame_word_reg;
    logic [31:0] staged_last_frame_word_reg;
    logic [31:0] error_count_reg;
    logic [31:0] active_bank_reg;
    logic [31:0] frame_sequence_reg;
    logic [31:0] consumer_sequence_reg;
    logic [31:0] consumer_frame_count_reg;
    logic [31:0] consumer_error_count_reg;
    logic consumer_error_sticky_reg;

    logic frame_commit_swmod_q;
    logic control_clear_swmod_q;
    logic consumer_reset_swmod_q;
    logic first_frame_word_swmod_q;
    logic last_frame_word_swmod_q;

    logic [2:0] tx_state_reg;
    logic [1:0] rd_state_reg;
    logic [31:0] tx_sequence_reg;
    logic [31:0] tx_active_bank_reg;
    logic [31:0] tx_words_reg;
    logic [31:0] pixel_index_reg;
    logic [31:0] read_pixel_index_reg;
    logic [31:0] bit_cycle_reg;
    logic [4:0] bit_index_reg;
    logic [31:0] reset_cycle_reg;
    logic [31:0] read_output_reg;
    logic [31:0] current_pixel_reg [0:OUTPUT_COUNT-1];
    logic [31:0] next_pixel_reg [0:OUTPUT_COUNT-1];
    logic next_pixel_valid_reg;
    logic read_active_reg;
    logic [OUTPUT_COUNT-1:0] ws281x_data_reg;

    wire frame_read_address_fire;
    wire frame_read_data_fire;
    wire [31:0] consumer_status_value;
    wire [31:0] commit_value;
    integer output_index;

    assign ws281x_data = ws281x_data_reg;
    assign m_frame_rready = 1'b1;
    assign frame_read_address_fire = rd_state_reg == RD_ADDR && m_frame_arvalid && m_frame_arready;
    assign frame_read_data_fire = m_frame_rvalid && (rd_state_reg == RD_DATA || frame_read_address_fire);
    assign consumer_status_value = {28'h0, consumer_error_sticky_reg, tx_state_reg == TX_RESET, tx_state_reg != TX_IDLE, hwif_out.CONSUMER_CONTROL.enable.value};
    assign commit_value = {hwif_out.FRAME_COMMIT.bank.value, hwif_out.FRAME_COMMIT.word_count.value};

    assign hwif_in.STATUS.ready.next = status_reg[0];
    assign hwif_in.STATUS.overflow.next = status_reg[1];
    assign hwif_in.STATUS.consumer_error.next = status_reg[2];
    assign hwif_in.PIN_OUT.value.next = committed_first_frame_word_reg;
    assign hwif_in.COUNTER.value.next = counter_reg;
    assign hwif_in.FRAME_CAPACITY.value.next = FRAME_WORDS;
    assign hwif_in.FRAME_COUNT.value.next = frame_count_reg;
    assign hwif_in.COMMITTED_WORDS.value.next = committed_words_reg;
    assign hwif_in.FIRST_FRAME_WORD.value.next = committed_first_frame_word_reg;
    assign hwif_in.LAST_FRAME_WORD.value.next = committed_last_frame_word_reg;
    assign hwif_in.ERROR_COUNT.value.next = error_count_reg;
    assign hwif_in.FRAME_BANK_WORDS.value.next = FRAME_WORDS_PER_BANK;
    assign hwif_in.ACTIVE_BANK.value.next = active_bank_reg;
    assign hwif_in.WRITE_BANK.value.next = active_bank_reg ^ 32'h0000_0001;
    assign hwif_in.FRAME_SEQUENCE.value.next = frame_sequence_reg;
    assign hwif_in.CONSUMER_STATUS.enabled.next = consumer_status_value[0];
    assign hwif_in.CONSUMER_STATUS.busy.next = consumer_status_value[1];
    assign hwif_in.CONSUMER_STATUS.reset_low.next = consumer_status_value[2];
    assign hwif_in.CONSUMER_STATUS.error.next = consumer_status_value[3];
    assign hwif_in.CONSUMER_SEQUENCE.value.next = consumer_sequence_reg;
    assign hwif_in.CONSUMER_FRAME_COUNT.value.next = consumer_frame_count_reg;
    assign hwif_in.CONSUMER_ERROR_COUNT.value.next = consumer_error_count_reg;
    assign hwif_in.CONSUMER_DEBUG.value.next = {8'h00, tx_state_reg, rd_state_reg, next_pixel_valid_reg, read_active_reg, bit_index_reg, pixel_index_reg[9:0]};

    pl_control_regs regs (
        .clk(aclk),
        .rst_n(aresetn),
        .s_axil_awready(s_axi_awready),
        .s_axil_awvalid(s_axi_awvalid),
        .s_axil_awaddr(s_axi_awaddr[11:0]),
        .s_axil_awprot(s_axi_awprot),
        .s_axil_wready(s_axi_wready),
        .s_axil_wvalid(s_axi_wvalid),
        .s_axil_wdata(s_axi_wdata),
        .s_axil_wstrb(s_axi_wstrb),
        .s_axil_bready(s_axi_bready),
        .s_axil_bvalid(s_axi_bvalid),
        .s_axil_bresp(s_axi_bresp),
        .s_axil_arready(s_axi_arready),
        .s_axil_arvalid(s_axi_arvalid),
        .s_axil_araddr(s_axi_araddr[11:0]),
        .s_axil_arprot(s_axi_arprot),
        .s_axil_rready(s_axi_rready),
        .s_axil_rvalid(s_axi_rvalid),
        .s_axil_rdata(s_axi_rdata),
        .s_axil_rresp(s_axi_rresp),
        .hwif_in(hwif_in),
        .hwif_out(hwif_out)
    );

    function automatic [23:0] grb_word(input [31:0] rgb_word);
        grb_word = {rgb_word[15:8], rgb_word[23:16], rgb_word[7:0]};
    endfunction

    function automatic ws_bit_value(input [31:0] rgb_word, input [4:0] bit_index);
        logic [23:0] grb;
        begin
            grb = grb_word(rgb_word);
            ws_bit_value = grb[23 - bit_index];
        end
    endfunction

    function automatic [FRAME_ADDR_WIDTH-1:0] frame_byte_addr(input [31:0] bank, input [31:0] pixel, input [31:0] output_num);
        logic [31:0] word_index;
        begin
            word_index = (bank[0] ? FRAME_WORDS_PER_BANK : 32'h0000_0000) + (pixel * OUTPUT_COUNT) + output_num;
            frame_byte_addr = word_index[FRAME_ADDR_WIDTH-3:0] << 2;
        end
    endfunction

    always_ff @(posedge aclk) begin
        logic [FRAME_ADDR_WIDTH-1:0] next_read_addr;

        if (!aresetn) begin
            status_reg <= STATUS_READY;
            counter_reg <= 32'h0000_0000;
            frame_count_reg <= 32'h0000_0000;
            committed_words_reg <= 32'h0000_0000;
            committed_first_frame_word_reg <= 32'h0000_0000;
            committed_last_frame_word_reg <= 32'h0000_0000;
            staged_first_frame_word_reg <= 32'h0000_0000;
            staged_last_frame_word_reg <= 32'h0000_0000;
            error_count_reg <= 32'h0000_0000;
            active_bank_reg <= 32'h0000_0000;
            frame_sequence_reg <= 32'h0000_0000;
            consumer_sequence_reg <= 32'h0000_0000;
            consumer_frame_count_reg <= 32'h0000_0000;
            consumer_error_count_reg <= 32'h0000_0000;
            consumer_error_sticky_reg <= 1'b0;
            frame_commit_swmod_q <= 1'b0;
            control_clear_swmod_q <= 1'b0;
            consumer_reset_swmod_q <= 1'b0;
            first_frame_word_swmod_q <= 1'b0;
            last_frame_word_swmod_q <= 1'b0;
            tx_state_reg <= TX_IDLE;
            rd_state_reg <= RD_IDLE;
            tx_sequence_reg <= 32'h0000_0000;
            tx_active_bank_reg <= 32'h0000_0000;
            tx_words_reg <= 32'h0000_0000;
            pixel_index_reg <= 32'h0000_0000;
            read_pixel_index_reg <= 32'h0000_0000;
            bit_cycle_reg <= 32'h0000_0000;
            bit_index_reg <= 5'd0;
            reset_cycle_reg <= 32'h0000_0000;
            read_output_reg <= 32'h0000_0000;
            next_pixel_valid_reg <= 1'b0;
            read_active_reg <= 1'b0;
            ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
            m_frame_araddr <= {FRAME_ADDR_WIDTH{1'b0}};
            m_frame_arvalid <= 1'b0;
            for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
                current_pixel_reg[output_index] <= 32'h0000_0000;
                next_pixel_reg[output_index] <= 32'h0000_0000;
            end
        end else begin
            counter_reg <= counter_reg + 32'd1;

            frame_commit_swmod_q <= hwif_out.FRAME_COMMIT.word_count.swmod || hwif_out.FRAME_COMMIT.bank.swmod;
            control_clear_swmod_q <= hwif_out.CONTROL.clear_errors.swmod;
            consumer_reset_swmod_q <= hwif_out.CONSUMER_CONTROL.reset_fsm.swmod;
            first_frame_word_swmod_q <= hwif_out.FIRST_FRAME_WORD.value.swmod;
            last_frame_word_swmod_q <= hwif_out.LAST_FRAME_WORD.value.swmod;

            if (first_frame_word_swmod_q) begin
                staged_first_frame_word_reg <= hwif_out.FIRST_FRAME_WORD.value.value;
            end
            if (last_frame_word_swmod_q) begin
                staged_last_frame_word_reg <= hwif_out.LAST_FRAME_WORD.value.value;
            end

            if (control_clear_swmod_q && hwif_out.CONTROL.clear_errors.value) begin
                status_reg <= STATUS_READY;
                consumer_error_sticky_reg <= 1'b0;
            end

            if (consumer_reset_swmod_q && hwif_out.CONSUMER_CONTROL.reset_fsm.value) begin
                tx_state_reg <= TX_IDLE;
                rd_state_reg <= RD_IDLE;
                m_frame_arvalid <= 1'b0;
                next_pixel_valid_reg <= 1'b0;
                ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
            end

            if (frame_commit_swmod_q) begin
                if (commit_value[30:0] <= FRAME_WORDS_PER_BANK) begin
                    frame_count_reg <= frame_count_reg + 32'd1;
                    frame_sequence_reg <= frame_sequence_reg + 32'd1;
                    active_bank_reg <= {31'h0000_0000, commit_value[31]};
                    committed_words_reg <= commit_value[30:0];
                    committed_first_frame_word_reg <= staged_first_frame_word_reg;
                    committed_last_frame_word_reg <= staged_last_frame_word_reg;
                end else begin
                    status_reg <= STATUS_READY | STATUS_OVERFLOW;
                    error_count_reg <= error_count_reg + 32'd1;
                end
            end

            if (tx_state_reg == TX_IDLE && hwif_out.CONSUMER_CONTROL.enable.value && frame_sequence_reg != consumer_sequence_reg) begin
                if (committed_words_reg >= FRAME_WORDS_REQUIRED) begin
                    tx_sequence_reg <= frame_sequence_reg;
                    tx_active_bank_reg <= active_bank_reg;
                    tx_words_reg <= committed_words_reg;
                    pixel_index_reg <= 32'h0000_0000;
                    read_pixel_index_reg <= 32'h0000_0000;
                    read_output_reg <= 32'h0000_0000;
                    next_pixel_valid_reg <= 1'b0;
                    read_active_reg <= 1'b1;
                    tx_state_reg <= TX_LOAD_FIRST;
                    rd_state_reg <= RD_ADDR;
                    m_frame_araddr <= frame_byte_addr(active_bank_reg, 32'h0000_0000, 32'h0000_0000);
                    m_frame_arvalid <= 1'b1;
                end else begin
                    consumer_sequence_reg <= frame_sequence_reg;
                    consumer_error_count_reg <= consumer_error_count_reg + 32'd1;
                    consumer_error_sticky_reg <= 1'b1;
                    status_reg <= STATUS_READY | STATUS_CONSUMER_ERROR;
                end
            end

            if (frame_read_address_fire) begin
                m_frame_arvalid <= 1'b0;
                rd_state_reg <= RD_DATA;
            end

            if (frame_read_data_fire) begin
                if (m_frame_rresp != 2'b00) begin
                    tx_state_reg <= TX_ERROR;
                    rd_state_reg <= RD_IDLE;
                    consumer_error_count_reg <= consumer_error_count_reg + 32'd1;
                    consumer_error_sticky_reg <= 1'b1;
                    status_reg <= STATUS_READY | STATUS_CONSUMER_ERROR;
                end else begin
                    if (read_active_reg) begin
                        current_pixel_reg[read_output_reg] <= m_frame_rdata;
                    end else begin
                        next_pixel_reg[read_output_reg] <= m_frame_rdata;
                    end

                    if (read_output_reg == OUTPUT_COUNT - 1) begin
                        rd_state_reg <= RD_IDLE;
                        if (read_active_reg) begin
                            read_active_reg <= 1'b0;
                        end else begin
                            next_pixel_valid_reg <= 1'b1;
                        end
                    end else begin
                        read_output_reg <= read_output_reg + 32'd1;
                        next_read_addr = frame_byte_addr(tx_active_bank_reg, read_pixel_index_reg, read_output_reg + 32'd1);
                        m_frame_araddr <= next_read_addr;
                        m_frame_arvalid <= 1'b1;
                        rd_state_reg <= RD_ADDR;
                    end
                end
            end

            case (tx_state_reg)
            TX_LOAD_FIRST: begin
                ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
                if (rd_state_reg == RD_IDLE && !read_active_reg) begin
                    pixel_index_reg <= 32'h0000_0000;
                    bit_index_reg <= 5'd0;
                    bit_cycle_reg <= 32'h0000_0000;
                    tx_state_reg <= TX_SEND;
                    if (PIXELS_PER_OUTPUT > 1) begin
                        read_pixel_index_reg <= 32'd1;
                        read_output_reg <= 32'h0000_0000;
                        next_pixel_valid_reg <= 1'b0;
                        next_read_addr = frame_byte_addr(tx_active_bank_reg, 32'd1, 32'h0000_0000);
                        m_frame_araddr <= next_read_addr;
                        m_frame_arvalid <= 1'b1;
                        rd_state_reg <= RD_ADDR;
                    end
                end
            end
            TX_SEND: begin
                for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
                    ws281x_data_reg[output_index] <= bit_cycle_reg < (ws_bit_value(current_pixel_reg[output_index], bit_index_reg) ? WS_T1H_CYCLES : WS_T0H_CYCLES);
                end

                if (bit_cycle_reg == WS_BIT_CYCLES - 1) begin
                    bit_cycle_reg <= 32'h0000_0000;
                    if (bit_index_reg == 5'd23) begin
                        bit_index_reg <= 5'd0;
                        ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
                        if (pixel_index_reg == PIXELS_PER_OUTPUT - 1) begin
                            tx_state_reg <= TX_RESET;
                            reset_cycle_reg <= 32'h0000_0000;
                        end else if (next_pixel_valid_reg) begin
                            for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
                                current_pixel_reg[output_index] <= next_pixel_reg[output_index];
                            end
                            pixel_index_reg <= pixel_index_reg + 32'd1;
                            next_pixel_valid_reg <= 1'b0;
                            if (pixel_index_reg + 32'd2 < PIXELS_PER_OUTPUT) begin
                                read_pixel_index_reg <= pixel_index_reg + 32'd2;
                                read_output_reg <= 32'h0000_0000;
                                next_read_addr = frame_byte_addr(tx_active_bank_reg, pixel_index_reg + 32'd2, 32'h0000_0000);
                                m_frame_araddr <= next_read_addr;
                                m_frame_arvalid <= 1'b1;
                                rd_state_reg <= RD_ADDR;
                            end
                        end else begin
                            tx_state_reg <= TX_ERROR;
                            consumer_error_count_reg <= consumer_error_count_reg + 32'd1;
                            consumer_error_sticky_reg <= 1'b1;
                            status_reg <= STATUS_READY | STATUS_CONSUMER_ERROR;
                        end
                    end else begin
                        bit_index_reg <= bit_index_reg + 5'd1;
                    end
                end else begin
                    bit_cycle_reg <= bit_cycle_reg + 32'd1;
                end
            end
            TX_RESET: begin
                ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
                if (reset_cycle_reg == WS_RESET_CYCLES - 1) begin
                    consumer_sequence_reg <= tx_sequence_reg;
                    consumer_frame_count_reg <= consumer_frame_count_reg + 32'd1;
                    tx_state_reg <= TX_IDLE;
                end else begin
                    reset_cycle_reg <= reset_cycle_reg + 32'd1;
                end
            end
            TX_ERROR: begin
                ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
                m_frame_arvalid <= 1'b0;
                rd_state_reg <= RD_IDLE;
                tx_state_reg <= TX_IDLE;
            end
            default: begin
            end
            endcase
        end
    end

endmodule
