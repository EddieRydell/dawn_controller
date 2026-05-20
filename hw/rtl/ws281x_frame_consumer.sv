`timescale 1ns / 1ps

module ws281x_frame_consumer #(
    parameter FRAME_WORDS = 8192,
    parameter FRAME_ADDR_WIDTH = 15,
    parameter OUTPUT_COUNT = 4,
    parameter PIXELS_PER_OUTPUT = 1024,
    parameter CLK_HZ = 100000000,
    parameter WS281X_BIT_RATE = 800000
) (
    input  wire                       aclk,
    input  wire                       aresetn,

    input  wire                       enable,
    input  wire                       reset_pulse,
    input  wire [31:0]                active_bank,
    input  wire [31:0]                committed_words,
    input  wire [31:0]                frame_sequence,
    input  wire [31:0]                runtime_active_output_count,
    input  wire [31:0]                runtime_strand0_pixel_count,
    input  wire [31:0]                runtime_strand1_pixel_count,
    input  wire [31:0]                runtime_strand2_pixel_count,
    input  wire [31:0]                runtime_strand3_pixel_count,

    output wire                       busy,
    output wire                       reset_low,
    output logic                      error_pulse,
    output logic [31:0]               consumer_sequence,
    output logic [31:0]               consumer_frame_count,
    output logic [31:0]               consumer_error_count,
    output logic [31:0]               consumer_active_bank,
    output wire [31:0]                consumer_debug,

    output wire [OUTPUT_COUNT-1:0]    ws281x_data,

    output logic [FRAME_ADDR_WIDTH-1:0] m_frame_araddr,
    output logic                       m_frame_arvalid,
    input  wire                       m_frame_arready,
    input  wire [31:0]                m_frame_rdata,
    input  wire [1:0]                 m_frame_rresp,
    input  wire                       m_frame_rvalid,
    output wire                       m_frame_rready
);

    localparam [31:0] FRAME_WORDS_PER_BANK = FRAME_WORDS / 2;
    localparam integer WS_BIT_CYCLES = CLK_HZ / WS281X_BIT_RATE;
    localparam integer WS_T0H_CYCLES = 35;
    localparam integer WS_T1H_CYCLES = 70;
    localparam integer WS_RESET_CYCLES = 28000;
    localparam [31:0] NO_BUSY_BANK = 32'hffff_ffff;

    localparam [2:0] TX_IDLE = 3'd0;
    localparam [2:0] TX_LOAD_FIRST = 3'd1;
    localparam [2:0] TX_SEND = 3'd2;
    localparam [2:0] TX_RESET = 3'd3;
    localparam [2:0] TX_ERROR = 3'd4;

    localparam [1:0] RD_IDLE = 2'd0;
    localparam [1:0] RD_ADDR = 2'd1;
    localparam [1:0] RD_DATA = 2'd2;

    logic [2:0] tx_state_reg;
    logic [1:0] rd_state_reg;
    logic [31:0] tx_sequence_reg;
    logic [31:0] tx_active_bank_reg;
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
    integer output_index;

    assign ws281x_data = ws281x_data_reg;
    assign m_frame_rready = 1'b1;
    assign busy = tx_state_reg != TX_IDLE;
    assign reset_low = tx_state_reg == TX_RESET;
    assign consumer_debug = {8'h00, tx_state_reg, rd_state_reg, next_pixel_valid_reg, read_active_reg, bit_index_reg, pixel_index_reg[9:0]};
    assign frame_read_address_fire = rd_state_reg == RD_ADDR && m_frame_arvalid && m_frame_arready;
    assign frame_read_data_fire = m_frame_rvalid && (rd_state_reg == RD_DATA || frame_read_address_fire);

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

    function automatic [31:0] strand_pixel_count(input [31:0] output_num);
        begin
            case (output_num)
            32'd0: strand_pixel_count = runtime_strand0_pixel_count;
            32'd1: strand_pixel_count = runtime_strand1_pixel_count;
            32'd2: strand_pixel_count = runtime_strand2_pixel_count;
            32'd3: strand_pixel_count = runtime_strand3_pixel_count;
            default: strand_pixel_count = 32'h0000_0000;
            endcase
        end
    endfunction

    function automatic output_active_for_pixel(input [31:0] pixel, input [31:0] output_num);
        begin
            output_active_for_pixel =
                output_num < OUTPUT_COUNT
                && output_num < runtime_active_output_count
                && pixel < strand_pixel_count(output_num);
        end
    endfunction

    function automatic [31:0] max_effective_pixels;
        integer idx;
        logic [31:0] length;
        begin
            max_effective_pixels = 32'h0000_0000;
            for (idx = 0; idx < OUTPUT_COUNT; idx = idx + 1) begin
                length = strand_pixel_count(idx);
                if (idx < runtime_active_output_count && length > max_effective_pixels) begin
                    max_effective_pixels = length;
                end
            end
        end
    endfunction

    function automatic [31:0] required_frame_words;
        integer idx;
        logic [31:0] length;
        logic [31:0] required;
        begin
            required_frame_words = 32'h0000_0000;
            for (idx = 0; idx < OUTPUT_COUNT; idx = idx + 1) begin
                length = strand_pixel_count(idx);
                if (idx < runtime_active_output_count && length != 32'h0000_0000) begin
                    required = ((length - 32'd1) * OUTPUT_COUNT) + idx + 32'd1;
                    if (required > required_frame_words) begin
                        required_frame_words = required;
                    end
                end
            end
        end
    endfunction

    function automatic [31:0] next_read_output(input [31:0] pixel, input [31:0] start_output);
        integer idx;
        logic found;
        begin
            next_read_output = OUTPUT_COUNT;
            found = 1'b0;
            for (idx = 0; idx < OUTPUT_COUNT; idx = idx + 1) begin
                if (!found && idx >= start_output && output_active_for_pixel(pixel, idx)) begin
                    next_read_output = idx;
                    found = 1'b1;
                end
            end
        end
    endfunction

    always_ff @(posedge aclk) begin
        logic [FRAME_ADDR_WIDTH-1:0] next_read_addr;
        logic [31:0] next_output;
        logic [31:0] frame_pixels;
        logic [31:0] frame_required_words;

        if (!aresetn) begin
            tx_state_reg <= TX_IDLE;
            rd_state_reg <= RD_IDLE;
            tx_sequence_reg <= 32'h0000_0000;
            tx_active_bank_reg <= 32'h0000_0000;
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
            error_pulse <= 1'b0;
            consumer_sequence <= 32'h0000_0000;
            consumer_frame_count <= 32'h0000_0000;
            consumer_error_count <= 32'h0000_0000;
            consumer_active_bank <= NO_BUSY_BANK;
            for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
                current_pixel_reg[output_index] <= 32'h0000_0000;
                next_pixel_reg[output_index] <= 32'h0000_0000;
            end
        end else begin
            error_pulse <= 1'b0;

            if (reset_pulse) begin
                tx_state_reg <= TX_IDLE;
                rd_state_reg <= RD_IDLE;
                m_frame_arvalid <= 1'b0;
                next_pixel_valid_reg <= 1'b0;
                ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
                consumer_active_bank <= NO_BUSY_BANK;
            end

            if (tx_state_reg == TX_IDLE && enable && frame_sequence != consumer_sequence) begin
                frame_pixels = max_effective_pixels();
                frame_required_words = required_frame_words();
                if (committed_words >= frame_required_words) begin
                    tx_sequence_reg <= frame_sequence;
                    tx_active_bank_reg <= active_bank;
                    consumer_active_bank <= active_bank;
                    pixel_index_reg <= 32'h0000_0000;
                    read_pixel_index_reg <= 32'h0000_0000;
                    next_pixel_valid_reg <= 1'b0;
                    for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
                        current_pixel_reg[output_index] <= 32'h0000_0000;
                    end
                    if (frame_pixels == 32'h0000_0000) begin
                        reset_cycle_reg <= 32'h0000_0000;
                        tx_state_reg <= TX_RESET;
                        rd_state_reg <= RD_IDLE;
                        m_frame_arvalid <= 1'b0;
                        read_active_reg <= 1'b0;
                    end else begin
                        next_output = next_read_output(32'h0000_0000, 32'h0000_0000);
                        read_output_reg <= next_output;
                        read_active_reg <= 1'b1;
                        tx_state_reg <= TX_LOAD_FIRST;
                        rd_state_reg <= RD_ADDR;
                        m_frame_araddr <= frame_byte_addr(active_bank, 32'h0000_0000, next_output);
                        m_frame_arvalid <= 1'b1;
                    end
                end else begin
                    consumer_sequence <= frame_sequence;
                    consumer_error_count <= consumer_error_count + 32'd1;
                    error_pulse <= 1'b1;
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
                    consumer_error_count <= consumer_error_count + 32'd1;
                    error_pulse <= 1'b1;
                end else begin
                    if (read_active_reg) begin
                        current_pixel_reg[read_output_reg] <= m_frame_rdata;
                    end else begin
                        next_pixel_reg[read_output_reg] <= m_frame_rdata;
                    end

                    next_output = next_read_output(read_pixel_index_reg, read_output_reg + 32'd1);
                    if (next_output == OUTPUT_COUNT) begin
                        rd_state_reg <= RD_IDLE;
                        if (read_active_reg) begin
                            read_active_reg <= 1'b0;
                        end else begin
                            next_pixel_valid_reg <= 1'b1;
                        end
                    end else begin
                        read_output_reg <= next_output;
                        next_read_addr = frame_byte_addr(tx_active_bank_reg, read_pixel_index_reg, next_output);
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
                    if (max_effective_pixels() > 32'd1) begin
                        read_pixel_index_reg <= 32'd1;
                        next_output = next_read_output(32'd1, 32'h0000_0000);
                        read_output_reg <= next_output;
                        next_pixel_valid_reg <= 1'b0;
                        for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
                            next_pixel_reg[output_index] <= 32'h0000_0000;
                        end
                        next_read_addr = frame_byte_addr(tx_active_bank_reg, 32'd1, next_output);
                        m_frame_araddr <= next_read_addr;
                        m_frame_arvalid <= 1'b1;
                        rd_state_reg <= RD_ADDR;
                    end
                end
            end
            TX_SEND: begin
                for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
                    ws281x_data_reg[output_index] <= output_active_for_pixel(pixel_index_reg, output_index)
                        && bit_cycle_reg < (ws_bit_value(current_pixel_reg[output_index], bit_index_reg) ? WS_T1H_CYCLES : WS_T0H_CYCLES);
                end

                if (bit_cycle_reg == WS_BIT_CYCLES - 1) begin
                    bit_cycle_reg <= 32'h0000_0000;
                    if (bit_index_reg == 5'd23) begin
                        bit_index_reg <= 5'd0;
                        ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
                        if (pixel_index_reg == max_effective_pixels() - 32'd1) begin
                            tx_state_reg <= TX_RESET;
                            reset_cycle_reg <= 32'h0000_0000;
                        end else if (next_pixel_valid_reg) begin
                            for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
                                current_pixel_reg[output_index] <= next_pixel_reg[output_index];
                            end
                            pixel_index_reg <= pixel_index_reg + 32'd1;
                            next_pixel_valid_reg <= 1'b0;
                            if (pixel_index_reg + 32'd2 < max_effective_pixels()) begin
                                read_pixel_index_reg <= pixel_index_reg + 32'd2;
                                next_output = next_read_output(pixel_index_reg + 32'd2, 32'h0000_0000);
                                read_output_reg <= next_output;
                                for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
                                    next_pixel_reg[output_index] <= 32'h0000_0000;
                                end
                                next_read_addr = frame_byte_addr(tx_active_bank_reg, pixel_index_reg + 32'd2, next_output);
                                m_frame_araddr <= next_read_addr;
                                m_frame_arvalid <= 1'b1;
                                rd_state_reg <= RD_ADDR;
                            end
                        end else begin
                            tx_state_reg <= TX_ERROR;
                            consumer_error_count <= consumer_error_count + 32'd1;
                            error_pulse <= 1'b1;
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
                    consumer_sequence <= tx_sequence_reg;
                    consumer_frame_count <= consumer_frame_count + 32'd1;
                    consumer_active_bank <= NO_BUSY_BANK;
                    tx_state_reg <= TX_IDLE;
                end else begin
                    reset_cycle_reg <= reset_cycle_reg + 32'd1;
                end
            end
            TX_ERROR: begin
                ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
                m_frame_arvalid <= 1'b0;
                rd_state_reg <= RD_IDLE;
                consumer_active_bank <= NO_BUSY_BANK;
                tx_state_reg <= TX_IDLE;
            end
            default: begin
            end
            endcase
        end
    end

endmodule
