`timescale 1ns / 1ps
`include "pl_contract.vh"

module eth_control_core #(
    parameter AXIL_ADDR_WIDTH = 12,
    parameter FRAME_WORDS = `PL_DEFAULT_FRAME_WORDS,
    parameter FRAME_ADDR_WIDTH = 15,
    parameter OUTPUT_COUNT = `PL_DEFAULT_OUTPUT_COUNT,
    parameter PIXELS_PER_OUTPUT = `PL_DEFAULT_PIXELS_PER_OUTPUT,
    parameter CLK_HZ = `PL_DEFAULT_CLK_HZ,
    parameter WS281X_BIT_RATE = `PL_DEFAULT_WS281X_BIT_RATE
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

    output wire [OUTPUT_COUNT-1:0]    ws281x_data,

    output reg [FRAME_ADDR_WIDTH-1:0] m_frame_araddr,
    output reg                        m_frame_arvalid,
    input  wire                       m_frame_arready,
    input  wire [31:0]                m_frame_rdata,
    input  wire [1:0]                 m_frame_rresp,
    input  wire                       m_frame_rvalid,
    output wire                       m_frame_rready
);

    localparam [31:0] CORE_ID = `PL_CORE_ID; // "EFPL"
    localparam [31:0] CORE_VERSION = `PL_CORE_VERSION;
    localparam [31:0] FRAME_WORDS_PER_BANK = FRAME_WORDS / 2;
    localparam [31:0] FRAME_WORDS_REQUIRED = OUTPUT_COUNT * PIXELS_PER_OUTPUT;
    localparam integer WS_BIT_CYCLES = CLK_HZ / WS281X_BIT_RATE;
    localparam integer WS_T0H_CYCLES = 35;
    localparam integer WS_T1H_CYCLES = 70;
    localparam integer WS_RESET_CYCLES = 28000;

    localparam [AXIL_ADDR_WIDTH-1:0] REG_ID              = `PL_REG_ID;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_VERSION         = `PL_REG_VERSION;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_CONTROL         = `PL_REG_CONTROL;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_STATUS          = `PL_REG_STATUS;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_PIN_OUT         = `PL_REG_PIN_OUT;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_COUNTER         = `PL_REG_COUNTER;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_FRAME_CAPACITY  = `PL_REG_FRAME_CAPACITY;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_FRAME_COMMIT    = `PL_REG_FRAME_COMMIT;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_FRAME_COUNT     = `PL_REG_FRAME_COUNT;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_COMMITTED_WORDS = `PL_REG_COMMITTED_WORDS;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_FIRST_FRAME_WORD = `PL_REG_FIRST_FRAME_WORD;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_LAST_FRAME_WORD = `PL_REG_LAST_FRAME_WORD;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_ERROR_COUNT     = `PL_REG_ERROR_COUNT;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_FRAME_BANK_WORDS = `PL_REG_FRAME_BANK_WORDS;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_ACTIVE_BANK     = `PL_REG_ACTIVE_BANK;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_WRITE_BANK      = `PL_REG_WRITE_BANK;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_FRAME_SEQUENCE  = `PL_REG_FRAME_SEQUENCE;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_CONSUMER_CONTROL = `PL_REG_CONSUMER_CONTROL;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_CONSUMER_STATUS = `PL_REG_CONSUMER_STATUS;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_CONSUMER_SEQUENCE = `PL_REG_CONSUMER_SEQUENCE;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_CONSUMER_FRAME_COUNT = `PL_REG_CONSUMER_FRAME_COUNT;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_CONSUMER_ERROR_COUNT = `PL_REG_CONSUMER_ERROR_COUNT;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_WS281X_BIT_RATE = `PL_REG_WS281X_BIT_RATE;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_WS281X_OUTPUT_COUNT = `PL_REG_WS281X_OUTPUT_COUNT;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_WS281X_PIXELS_PER_OUTPUT = `PL_REG_WS281X_PIXELS_PER_OUTPUT;
    localparam [AXIL_ADDR_WIDTH-1:0] REG_CONSUMER_DEBUG = `PL_REG_CONSUMER_DEBUG;

    localparam [31:0] STATUS_READY = `PL_STATUS_READY;
    localparam [31:0] STATUS_OVERFLOW = `PL_STATUS_OVERFLOW;
    localparam [31:0] STATUS_CONSUMER_ERROR = `PL_STATUS_CONSUMER_ERROR;
    localparam [31:0] CONSUMER_STATUS_ENABLED = `PL_CONSUMER_STATUS_ENABLED;
    localparam [31:0] CONSUMER_STATUS_BUSY = `PL_CONSUMER_STATUS_BUSY;
    localparam [31:0] CONSUMER_STATUS_RESET_LOW = `PL_CONSUMER_STATUS_RESET_LOW;
    localparam [31:0] CONSUMER_STATUS_ERROR = `PL_CONSUMER_STATUS_ERROR;

    localparam [2:0] TX_IDLE = 3'd0;
    localparam [2:0] TX_LOAD_FIRST = 3'd1;
    localparam [2:0] TX_SEND = 3'd2;
    localparam [2:0] TX_RESET = 3'd3;
    localparam [2:0] TX_ERROR = 3'd4;

    localparam [1:0] RD_IDLE = 2'd0;
    localparam [1:0] RD_ADDR = 2'd1;
    localparam [1:0] RD_DATA = 2'd2;

    reg [AXIL_ADDR_WIDTH-1:0] awaddr_reg;
    reg [31:0] wdata_reg;
    reg [3:0] wstrb_reg;
    reg aw_seen;
    reg w_seen;

    reg [31:0] control_reg;
    reg [31:0] status_reg;
    reg [31:0] pin_out_reg;
    reg [31:0] counter_reg;
    reg [31:0] frame_count_reg;
    reg [31:0] committed_words_reg;
    reg [31:0] first_frame_word_reg;
    reg [31:0] last_frame_word_reg;
    reg [31:0] staged_first_frame_word_reg;
    reg [31:0] staged_last_frame_word_reg;
    reg [31:0] error_count_reg;
    reg [31:0] active_bank_reg;
    reg [31:0] frame_sequence_reg;
    reg [31:0] consumer_control_reg;
    reg [31:0] consumer_sequence_reg;
    reg [31:0] consumer_frame_count_reg;
    reg [31:0] consumer_error_count_reg;
    reg consumer_error_sticky_reg;

    reg [2:0] tx_state_reg;
    reg [1:0] rd_state_reg;
    reg [31:0] tx_sequence_reg;
    reg [31:0] tx_active_bank_reg;
    reg [31:0] tx_words_reg;
    reg [31:0] pixel_index_reg;
    reg [31:0] read_pixel_index_reg;
    reg [31:0] bit_cycle_reg;
    reg [4:0] bit_index_reg;
    reg [31:0] reset_cycle_reg;
    reg [31:0] read_output_reg;
    reg [31:0] current_pixel_reg [0:OUTPUT_COUNT-1];
    reg [31:0] next_pixel_reg [0:OUTPUT_COUNT-1];
    reg next_pixel_valid_reg;
    reg read_active_reg;
    reg [OUTPUT_COUNT-1:0] ws281x_data_reg;

    reg [AXIL_ADDR_WIDTH-1:0] write_addr;
    reg [31:0] write_data;
    reg [3:0] write_strb;
    reg [FRAME_ADDR_WIDTH-1:0] next_read_addr;
    integer output_index;
    wire frame_read_address_fire;
    wire frame_read_data_fire;

    assign ws281x_data = ws281x_data_reg;
    assign m_frame_rready = 1'b1;
    assign frame_read_address_fire = rd_state_reg == RD_ADDR && m_frame_arvalid && m_frame_arready;
    assign frame_read_data_fire = m_frame_rvalid
                                  && (rd_state_reg == RD_DATA || frame_read_address_fire);

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
            REG_ID:               read_register = CORE_ID;
            REG_VERSION:          read_register = CORE_VERSION;
            REG_CONTROL:          read_register = control_reg;
            REG_STATUS:           read_register = status_reg;
            REG_PIN_OUT:          read_register = pin_out_reg;
            REG_COUNTER:          read_register = counter_reg;
            REG_FRAME_CAPACITY:   read_register = FRAME_WORDS;
            REG_FRAME_COMMIT:     read_register = 32'h0000_0000;
            REG_FRAME_COUNT:      read_register = frame_count_reg;
            REG_COMMITTED_WORDS:  read_register = committed_words_reg;
            REG_FIRST_FRAME_WORD: read_register = first_frame_word_reg;
            REG_LAST_FRAME_WORD:  read_register = last_frame_word_reg;
            REG_ERROR_COUNT:      read_register = error_count_reg;
            REG_FRAME_BANK_WORDS: read_register = FRAME_WORDS_PER_BANK;
            REG_ACTIVE_BANK:      read_register = active_bank_reg;
            REG_WRITE_BANK:       read_register = active_bank_reg ^ 32'h0000_0001;
            REG_FRAME_SEQUENCE:   read_register = frame_sequence_reg;
            REG_CONSUMER_CONTROL: read_register = consumer_control_reg;
            REG_CONSUMER_STATUS:  read_register = consumer_status(1'b0);
            REG_CONSUMER_SEQUENCE: read_register = consumer_sequence_reg;
            REG_CONSUMER_FRAME_COUNT: read_register = consumer_frame_count_reg;
            REG_CONSUMER_ERROR_COUNT: read_register = consumer_error_count_reg;
            REG_WS281X_BIT_RATE:  read_register = WS281X_BIT_RATE;
            REG_WS281X_OUTPUT_COUNT: read_register = OUTPUT_COUNT;
            REG_WS281X_PIXELS_PER_OUTPUT: read_register = PIXELS_PER_OUTPUT;
            REG_CONSUMER_DEBUG: read_register = {8'h00, tx_state_reg, rd_state_reg, next_pixel_valid_reg, read_active_reg, bit_index_reg, pixel_index_reg[9:0]};
            default:              read_register = 32'h0000_0000;
            endcase
        end
    endfunction

    function [31:0] consumer_status;
        input unused;
        begin
            consumer_status = 32'h0000_0000;
            if (consumer_control_reg[0]) begin
                consumer_status = consumer_status | CONSUMER_STATUS_ENABLED;
            end
            if (tx_state_reg != TX_IDLE) begin
                consumer_status = consumer_status | CONSUMER_STATUS_BUSY;
            end
            if (tx_state_reg == TX_RESET) begin
                consumer_status = consumer_status | CONSUMER_STATUS_RESET_LOW;
            end
            if (consumer_error_sticky_reg) begin
                consumer_status = consumer_status | CONSUMER_STATUS_ERROR;
            end
        end
    endfunction

    function [23:0] grb_word;
        input [31:0] rgb_word;
        begin
            grb_word = {rgb_word[15:8], rgb_word[23:16], rgb_word[7:0]};
        end
    endfunction

    function ws_bit_value;
        input [31:0] rgb_word;
        input [4:0] bit_index;
        reg [23:0] grb;
        begin
            grb = grb_word(rgb_word);
            ws_bit_value = grb[23 - bit_index];
        end
    endfunction

    function [FRAME_ADDR_WIDTH-1:0] frame_byte_addr;
        input [31:0] bank;
        input [31:0] pixel;
        input [31:0] output_num;
        reg [31:0] word_index;
        begin
            word_index = (bank[0] ? FRAME_WORDS_PER_BANK : 32'h0000_0000) + (pixel * OUTPUT_COUNT) + output_num;
            frame_byte_addr = word_index[FRAME_ADDR_WIDTH-3:0] << 2;
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
            frame_count_reg <= 32'h0000_0000;
            committed_words_reg <= 32'h0000_0000;
            first_frame_word_reg <= 32'h0000_0000;
            last_frame_word_reg <= 32'h0000_0000;
            staged_first_frame_word_reg <= 32'h0000_0000;
            staged_last_frame_word_reg <= 32'h0000_0000;
            error_count_reg <= 32'h0000_0000;
            active_bank_reg <= 32'h0000_0000;
            frame_sequence_reg <= 32'h0000_0000;
            consumer_control_reg <= 32'h0000_0000;
            consumer_sequence_reg <= 32'h0000_0000;
            consumer_frame_count_reg <= 32'h0000_0000;
            consumer_error_count_reg <= 32'h0000_0000;
            consumer_error_sticky_reg <= 1'b0;
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
                        consumer_error_sticky_reg <= 1'b0;
                    end
                end
                REG_PIN_OUT: begin
                    pin_out_reg <= apply_wstrb(pin_out_reg, write_data, write_strb);
                end
                REG_FRAME_COMMIT: begin
                    if (write_data[30:0] <= FRAME_WORDS_PER_BANK) begin
                        frame_count_reg <= frame_count_reg + 32'd1;
                        frame_sequence_reg <= frame_sequence_reg + 32'd1;
                        active_bank_reg <= {31'h0000_0000, write_data[31]};
                        committed_words_reg <= write_data[30:0];
                        first_frame_word_reg <= staged_first_frame_word_reg;
                        last_frame_word_reg <= staged_last_frame_word_reg;
                        pin_out_reg <= staged_first_frame_word_reg;
                    end else begin
                        status_reg <= STATUS_READY | STATUS_OVERFLOW;
                        error_count_reg <= error_count_reg + 32'd1;
                    end
                end
                REG_FIRST_FRAME_WORD: begin
                    staged_first_frame_word_reg <= apply_wstrb(staged_first_frame_word_reg, write_data, write_strb);
                end
                REG_LAST_FRAME_WORD: begin
                    staged_last_frame_word_reg <= apply_wstrb(staged_last_frame_word_reg, write_data, write_strb);
                end
                REG_CONSUMER_CONTROL: begin
                    consumer_control_reg <= apply_wstrb(consumer_control_reg, write_data, write_strb);
                    if (write_data[1]) begin
                        tx_state_reg <= TX_IDLE;
                        rd_state_reg <= RD_IDLE;
                        m_frame_arvalid <= 1'b0;
                        next_pixel_valid_reg <= 1'b0;
                        ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
                    end
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

            if (!s_axi_rvalid && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rdata <= read_register(s_axi_araddr);
                s_axi_rresp <= 2'b00;
                s_axi_rvalid <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end

            if (tx_state_reg == TX_IDLE && consumer_control_reg[0] && frame_sequence_reg != consumer_sequence_reg) begin
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
