module frame_reader #(
    parameter int unsigned MAX_OUTPUTS = 16,
    parameter int unsigned MAX_PIXELS_PER_OUTPUT = 1024,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 64
) (
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         enable,
    input  logic                         start_frame,
    input  logic [1:0]                   active_bank,
    input  logic [ADDR_WIDTH-1:0]        frame_base_addr,

    input  logic [31:0]                  output_count,
    input  logic [MAX_OUTPUTS*32-1:0]    output_pixel_count_flat,
    input  logic [MAX_OUTPUTS*32-1:0]    output_buffer_offset_flat,
    input  logic [MAX_OUTPUTS*32-1:0]    output_flags_flat,

    output logic [ADDR_WIDTH-1:0]        m_axi_araddr,
    output logic [7:0]                   m_axi_arlen,
    output logic [2:0]                   m_axi_arsize,
    output logic [1:0]                   m_axi_arburst,
    output logic                         m_axi_arvalid,
    input  logic                         m_axi_arready,

    input  logic [DATA_WIDTH-1:0]        m_axi_rdata,
    input  logic [1:0]                   m_axi_rresp,
    input  logic                         m_axi_rlast,
    input  logic                         m_axi_rvalid,
    output logic                         m_axi_rready,

    output logic [MAX_OUTPUTS*24-1:0]    pixel_rgb_flat,
    output logic [MAX_OUTPUTS-1:0]       pixel_valid,
    input  logic [MAX_OUTPUTS-1:0]       pixel_ready,
    output logic [MAX_OUTPUTS-1:0]       output_end_frame,

    output logic                         busy,
    output logic                         done_pulse,
    output logic                         config_error
);

    localparam int unsigned PIXEL_BYTES = 4;
    localparam int unsigned BANK_BYTES = MAX_OUTPUTS * MAX_PIXELS_PER_OUTPUT * PIXEL_BYTES;

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_SELECT_OUTPUT,
        STATE_ISSUE_READ,
        STATE_WAIT_READ,
        STATE_HAVE_PIXEL,
        STATE_DONE
    } state_t;

    state_t state;
    logic [31:0] output_index;
    logic [31:0] pixel_index;
    logic [31:0] current_pixel_count;
    logic [31:0] current_output_flags;
    logic [31:0] current_buffer_offset;
    logic [ADDR_WIDTH-1:0] read_addr;
    logic read_upper_word;

    function automatic logic [23:0] apply_color_order(
        input logic [23:0] rgb,
        input logic [1:0] order
    );
        logic [7:0] r;
        logic [7:0] g;
        logic [7:0] b;
        begin
            r = rgb[23:16];
            g = rgb[15:8];
            b = rgb[7:0];
            unique case (order)
            2'd0: apply_color_order = {r, g, b};
            2'd1: apply_color_order = {g, r, b};
            2'd2: apply_color_order = {b, r, g};
            default: apply_color_order = {b, g, r};
            endcase
        end
    endfunction

    function automatic logic [31:0] frame_bank_offset(input logic [1:0] bank);
        begin
            frame_bank_offset = 32'(bank) * 32'(BANK_BYTES);
        end
    endfunction

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            m_axi_araddr <= '0;
            m_axi_arlen <= '0;
            m_axi_arsize <= '0;
            m_axi_arburst <= 2'b01;
            m_axi_arvalid <= 1'b0;
            m_axi_rready <= 1'b0;
            pixel_rgb_flat <= '0;
            pixel_valid <= '0;
            output_end_frame <= '0;
            busy <= 1'b0;
            done_pulse <= 1'b0;
            config_error <= 1'b0;
            state <= STATE_IDLE;
            output_index <= 32'd0;
            pixel_index <= 32'd0;
            current_pixel_count <= 32'd0;
            current_output_flags <= 32'd0;
            current_buffer_offset <= 32'd0;
            read_addr <= '0;
            read_upper_word <= 1'b0;
        end else begin
            m_axi_rready <= 1'b0;
            done_pulse <= 1'b0;
            config_error <= 1'b0;

            unique case (state)
            STATE_IDLE: begin
                busy <= 1'b0;
                pixel_rgb_flat <= '0;
                pixel_valid <= '0;
                output_end_frame <= '0;

                if (enable && start_frame) begin
                    busy <= 1'b1;
                    output_index <= 32'd0;
                    pixel_index <= 32'd0;
                    if (output_count > MAX_OUTPUTS) begin
                        config_error <= 1'b1;
                        state <= STATE_DONE;
                    end else begin
                        state <= STATE_SELECT_OUTPUT;
                    end
                end
            end

            STATE_SELECT_OUTPUT: begin
                busy <= 1'b1;
                pixel_valid <= '0;
                output_end_frame <= '0;

                if (!enable) begin
                    state <= STATE_IDLE;
                end else if (output_index >= output_count) begin
                    state <= STATE_DONE;
                end else begin
                    current_pixel_count <= output_pixel_count_flat[output_index*32 +: 32];
                    current_buffer_offset <= output_buffer_offset_flat[output_index*32 +: 32];
                    current_output_flags <= output_flags_flat[output_index*32 +: 32];
                    pixel_index <= 32'd0;

                    if (output_pixel_count_flat[output_index*32 +: 32] == 32'd0
                        || output_flags_flat[output_index*32] == 1'b0) begin
                        output_index <= output_index + 32'd1;
                    end else begin
                        state <= STATE_ISSUE_READ;
                    end
                end
            end

            STATE_ISSUE_READ: begin
                logic [ADDR_WIDTH-1:0] next_read_addr;

                busy <= 1'b1;

                if (!m_axi_arvalid) begin
                    next_read_addr = frame_base_addr
                        + frame_bank_offset(active_bank)
                        + current_buffer_offset
                        + (pixel_index * PIXEL_BYTES);
                    read_addr <= next_read_addr;
                    read_upper_word <= next_read_addr[2];
                    m_axi_araddr <= next_read_addr;
                    m_axi_arlen <= 8'd0;
                    m_axi_arsize <= 3'd2;
                    m_axi_arburst <= 2'b01;
                    m_axi_arvalid <= 1'b1;
                end else if (m_axi_arready) begin
                    m_axi_arvalid <= 1'b0;
                    state <= STATE_WAIT_READ;
                end
            end

            STATE_WAIT_READ: begin
                busy <= 1'b1;
                m_axi_rready <= 1'b1;

                if (m_axi_rvalid && m_axi_rready) begin
                    logic [31:0] pixel_word;
                    logic [23:0] ordered_pixel;

                    pixel_word = read_upper_word ? m_axi_rdata[63:32] : m_axi_rdata[31:0];
                    ordered_pixel = apply_color_order(pixel_word[23:0],
                        current_output_flags[9:8]);
                    pixel_rgb_flat[output_index*24 +: 24] <= ordered_pixel;
                    pixel_valid[output_index] <= 1'b1;
                    output_end_frame[output_index] <= (pixel_index == current_pixel_count - 32'd1);
                    state <= STATE_HAVE_PIXEL;
                end
            end

            STATE_HAVE_PIXEL: begin
                busy <= 1'b1;

                if (!enable) begin
                    state <= STATE_IDLE;
                end else if (pixel_ready[output_index]) begin
                    pixel_valid[output_index] <= 1'b0;
                    output_end_frame[output_index] <= 1'b0;
                    if (pixel_index == current_pixel_count - 32'd1) begin
                        output_index <= output_index + 32'd1;
                        state <= STATE_SELECT_OUTPUT;
                    end else begin
                        pixel_index <= pixel_index + 32'd1;
                        state <= STATE_ISSUE_READ;
                    end
                end
            end

            STATE_DONE: begin
                busy <= 1'b0;
                done_pulse <= 1'b1;
                state <= STATE_IDLE;
            end

            default: begin
                state <= STATE_IDLE;
            end
            endcase
        end
    end

endmodule
