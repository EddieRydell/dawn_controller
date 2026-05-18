module axi_regs #(
    parameter int unsigned MAX_OUTPUTS = 16,
    parameter int unsigned MAX_PIXELS_PER_OUTPUT = 1024,
    parameter int unsigned ADDR_WIDTH = 12
) (
    input  logic                   s_axi_aclk,
    input  logic                   s_axi_aresetn,

    input  logic [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  logic [2:0]             s_axi_awprot,
    input  logic                   s_axi_awvalid,
    output logic                   s_axi_awready,

    input  logic [31:0]            s_axi_wdata,
    input  logic [3:0]             s_axi_wstrb,
    input  logic                   s_axi_wvalid,
    output logic                   s_axi_wready,

    output logic [1:0]             s_axi_bresp,
    output logic                   s_axi_bvalid,
    input  logic                   s_axi_bready,

    input  logic [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  logic [2:0]             s_axi_arprot,
    input  logic                   s_axi_arvalid,
    output logic                   s_axi_arready,

    output logic [31:0]            s_axi_rdata,
    output logic [1:0]             s_axi_rresp,
    output logic                   s_axi_rvalid,
    input  logic                   s_axi_rready,

    input  logic [31:0]            status_i,
    output logic [31:0]            control_o,
    output logic                   commit_frame_o,
    output logic [31:0]            active_bank_o,
    output logic [31:0]            write_bank_o,
    output logic [31:0]            frame_base_addr_o,
    output logic [31:0]            output_count_o,
    output logic [MAX_OUTPUTS*32-1:0] output_pixel_count_o,
    output logic [MAX_OUTPUTS*32-1:0] output_buffer_offset_o,
    output logic [MAX_OUTPUTS*32-1:0] output_flags_o
);

    import regs_pkg::*;

    logic [31:0] control_reg;
    logic [31:0] status_reg;
    logic [31:0] active_bank_reg;
    logic [31:0] write_bank_reg;
    logic [31:0] frame_counter_reg;
    logic [31:0] dropped_frame_counter_reg;
    logic [31:0] late_commit_counter_reg;
    logic [31:0] output_count_reg;
    logic [31:0] frame_base_addr_reg;
    logic commit_frame_pulse;

    logic [31:0] output_pixel_count [MAX_OUTPUTS];
    logic [31:0] output_buffer_offset [MAX_OUTPUTS];
    logic [31:0] output_flags [MAX_OUTPUTS];

    logic [ADDR_WIDTH-1:0] awaddr_reg;
    logic [ADDR_WIDTH-1:0] araddr_reg;
    logic [31:0] wdata_reg;
    logic [3:0] wstrb_reg;
    logic aw_pending;
    logic w_pending;

    wire aw_fire = s_axi_awready && s_axi_awvalid;
    wire w_fire = s_axi_wready && s_axi_wvalid;
    wire write_accept = !s_axi_bvalid && (aw_pending || aw_fire) && (w_pending || w_fire);
    wire read_accept = s_axi_arready && s_axi_arvalid;
    wire [ADDR_WIDTH-1:0] write_addr = aw_fire ? s_axi_awaddr : awaddr_reg;
    wire [31:0] write_data = w_fire ? s_axi_wdata : wdata_reg;
    wire [3:0] write_strb = w_fire ? s_axi_wstrb : wstrb_reg;

    function automatic logic [31:0] apply_wstrb(
        input logic [31:0] old_value,
        input logic [31:0] new_value,
        input logic [3:0] strobe
    );
        logic [31:0] merged;
        begin
            merged = old_value;
            for (int i = 0; i < 4; i++) begin
                if (strobe[i]) begin
                    merged[i*8 +: 8] = new_value[i*8 +: 8];
                end
            end
            return merged;
        end
    endfunction

    function automatic logic [31:0] read_register(input logic [ADDR_WIDTH-1:0] addr);
        logic [31:0] value;
        int unsigned output_index;
        logic [ADDR_WIDTH-1:0] output_offset;
        begin
            value = 32'h0000_0000;

            unique case (addr)
            PL_REG_CONTROL: begin
                value = control_reg;
            end
            PL_REG_STATUS: begin
                value = status_reg;
            end
            PL_REG_ACTIVE_BANK: begin
                value = active_bank_reg;
            end
            PL_REG_WRITE_BANK: begin
                value = write_bank_reg;
            end
            PL_REG_FRAME_COUNTER: begin
                value = frame_counter_reg;
            end
            PL_REG_DROPPED_FRAME_COUNTER: begin
                value = dropped_frame_counter_reg;
            end
            PL_REG_LATE_COMMIT_COUNTER: begin
                value = late_commit_counter_reg;
            end
            PL_REG_OUTPUT_COUNT: begin
                value = output_count_reg;
            end
            PL_REG_MAX_PIXELS_PER_OUTPUT: begin
                value = MAX_PIXELS_PER_OUTPUT;
            end
            PL_REG_FRAME_BASE_ADDR: begin
                value = frame_base_addr_reg;
            end
            default: begin
                if (addr >= PL_REG_OUTPUT_BASE) begin
                    output_index = (addr - PL_REG_OUTPUT_BASE) / PL_REG_OUTPUT_STRIDE;
                    output_offset = (addr - PL_REG_OUTPUT_BASE) % PL_REG_OUTPUT_STRIDE;
                    if (output_index < MAX_OUTPUTS) begin
                        unique case (output_offset)
                        12'h000: value = output_pixel_count[output_index];
                        12'h004: value = output_buffer_offset[output_index];
                        12'h008: value = output_flags[output_index];
                        default: value = 32'h0000_0000;
                        endcase
                    end
                end
            end
            endcase

            return value;
        end
    endfunction

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 1'b1;
            s_axi_wready <= 1'b1;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
            s_axi_arready <= 1'b1;
            s_axi_rdata <= 32'h0000_0000;
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b0;
            awaddr_reg <= '0;
            araddr_reg <= '0;
            wdata_reg <= 32'h0000_0000;
            wstrb_reg <= 4'h0;
            aw_pending <= 1'b0;
            w_pending <= 1'b0;

            control_reg <= 32'h0000_0000;
            status_reg <= 32'h0000_0000;
            active_bank_reg <= 32'h0000_0000;
            write_bank_reg <= 32'h0000_0000;
            frame_counter_reg <= 32'h0000_0000;
            dropped_frame_counter_reg <= 32'h0000_0000;
            late_commit_counter_reg <= 32'h0000_0000;
            output_count_reg <= 32'h0000_0000;
            frame_base_addr_reg <= 32'h0000_0000;
            commit_frame_pulse <= 1'b0;

            for (int i = 0; i < MAX_OUTPUTS; i++) begin
                output_pixel_count[i] <= 32'h0000_0000;
                output_buffer_offset[i] <= 32'h0000_0000;
                output_flags[i] <= 32'h0000_0000;
            end
        end else begin
            status_reg <= status_i;
            commit_frame_pulse <= 1'b0;

            if (s_axi_awready && s_axi_awvalid) begin
                awaddr_reg <= s_axi_awaddr;
            end

            if (s_axi_wready && s_axi_wvalid) begin
                wdata_reg <= s_axi_wdata;
                wstrb_reg <= s_axi_wstrb;
            end

            if (write_accept) begin
                logic [31:0] next_control;
                int unsigned output_index;
                logic [ADDR_WIDTH-1:0] output_offset;

                unique case (write_addr)
                PL_REG_CONTROL: begin
                    next_control = apply_wstrb(control_reg, write_data, write_strb);
                    control_reg <= next_control & ~PL_COMMIT_FRAME;
                    if (next_control & PL_COMMIT_FRAME) begin
                        active_bank_reg <= write_bank_reg;
                        frame_counter_reg <= frame_counter_reg + 32'd1;
                        commit_frame_pulse <= 1'b1;
                    end
                end
                PL_REG_WRITE_BANK: begin
                    write_bank_reg <= apply_wstrb(write_bank_reg, write_data, write_strb);
                end
                PL_REG_OUTPUT_COUNT: begin
                    output_count_reg <= apply_wstrb(output_count_reg, write_data, write_strb);
                end
                PL_REG_FRAME_BASE_ADDR: begin
                    frame_base_addr_reg <= apply_wstrb(frame_base_addr_reg, write_data, write_strb);
                end
                default: begin
                    if (write_addr >= PL_REG_OUTPUT_BASE) begin
                        output_index = (write_addr - PL_REG_OUTPUT_BASE) / PL_REG_OUTPUT_STRIDE;
                        output_offset = (write_addr - PL_REG_OUTPUT_BASE) % PL_REG_OUTPUT_STRIDE;
                        if (output_index < MAX_OUTPUTS) begin
                            unique case (output_offset)
                            12'h000: output_pixel_count[output_index] <= apply_wstrb(output_pixel_count[output_index], write_data, write_strb);
                            12'h004: output_buffer_offset[output_index] <= apply_wstrb(output_buffer_offset[output_index], write_data, write_strb);
                            12'h008: output_flags[output_index] <= apply_wstrb(output_flags[output_index], write_data, write_strb);
                            default: begin
                            end
                            endcase
                        end
                    end
                end
                endcase

                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;
                aw_pending <= 1'b0;
                w_pending <= 1'b0;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end else begin
                if (aw_fire) begin
                    aw_pending <= 1'b1;
                end
                if (w_fire) begin
                    w_pending <= 1'b1;
                end
            end

            if (read_accept) begin
                araddr_reg <= s_axi_araddr;
                s_axi_rdata <= read_register(s_axi_araddr);
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= 2'b00;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    assign control_o = control_reg;
    assign commit_frame_o = commit_frame_pulse;
    assign active_bank_o = active_bank_reg;
    assign write_bank_o = write_bank_reg;
    assign frame_base_addr_o = frame_base_addr_reg;
    assign output_count_o = output_count_reg;

    for (genvar output_index = 0; output_index < MAX_OUTPUTS; output_index++) begin : gen_config_outputs
        assign output_pixel_count_o[output_index*32 +: 32] = output_pixel_count[output_index];
        assign output_buffer_offset_o[output_index*32 +: 32] = output_buffer_offset[output_index];
        assign output_flags_o[output_index*32 +: 32] = output_flags[output_index];
    end

endmodule
