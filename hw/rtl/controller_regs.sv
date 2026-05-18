module controller_regs #(
    parameter int unsigned MAX_OUTPUTS = 16,
    parameter int unsigned MAX_PIXELS_PER_OUTPUT = 1024,
    parameter int unsigned ADDR_WIDTH = 12
) (
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic                   reg_wr_en,
    input  logic [ADDR_WIDTH-1:0]  reg_wr_addr,
    input  logic [31:0]            reg_wr_data,
    input  logic [3:0]             reg_wr_strb,

    input  logic [ADDR_WIDTH-1:0]  reg_rd_addr,
    output logic [31:0]            reg_rd_data,

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
            PL_REG_CONTROL: value = control_reg;
            PL_REG_STATUS: value = status_reg;
            PL_REG_ACTIVE_BANK: value = active_bank_reg;
            PL_REG_WRITE_BANK: value = write_bank_reg;
            PL_REG_FRAME_COUNTER: value = frame_counter_reg;
            PL_REG_DROPPED_FRAME_COUNTER: value = dropped_frame_counter_reg;
            PL_REG_LATE_COMMIT_COUNTER: value = late_commit_counter_reg;
            PL_REG_OUTPUT_COUNT: value = output_count_reg;
            PL_REG_MAX_PIXELS_PER_OUTPUT: value = MAX_PIXELS_PER_OUTPUT;
            PL_REG_FRAME_BASE_ADDR: value = frame_base_addr_reg;
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

    always_comb begin
        reg_rd_data = read_register(reg_rd_addr);
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
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

            if (reg_wr_en) begin
                logic [31:0] next_control;
                int unsigned output_index;
                logic [ADDR_WIDTH-1:0] output_offset;

                unique case (reg_wr_addr)
                PL_REG_CONTROL: begin
                    next_control = apply_wstrb(control_reg, reg_wr_data, reg_wr_strb);
                    control_reg <= next_control & ~PL_COMMIT_FRAME;
                    if (next_control & PL_COMMIT_FRAME) begin
                        active_bank_reg <= write_bank_reg;
                        frame_counter_reg <= frame_counter_reg + 32'd1;
                        commit_frame_pulse <= 1'b1;
                    end
                end
                PL_REG_WRITE_BANK: begin
                    write_bank_reg <= apply_wstrb(write_bank_reg, reg_wr_data, reg_wr_strb);
                end
                PL_REG_OUTPUT_COUNT: begin
                    output_count_reg <= apply_wstrb(output_count_reg, reg_wr_data, reg_wr_strb);
                end
                PL_REG_FRAME_BASE_ADDR: begin
                    frame_base_addr_reg <= apply_wstrb(frame_base_addr_reg, reg_wr_data, reg_wr_strb);
                end
                default: begin
                    if (reg_wr_addr >= PL_REG_OUTPUT_BASE) begin
                        output_index = (reg_wr_addr - PL_REG_OUTPUT_BASE) / PL_REG_OUTPUT_STRIDE;
                        output_offset = (reg_wr_addr - PL_REG_OUTPUT_BASE) % PL_REG_OUTPUT_STRIDE;
                        if (output_index < MAX_OUTPUTS) begin
                            unique case (output_offset)
                            12'h000: output_pixel_count[output_index] <= apply_wstrb(output_pixel_count[output_index], reg_wr_data, reg_wr_strb);
                            12'h004: output_buffer_offset[output_index] <= apply_wstrb(output_buffer_offset[output_index], reg_wr_data, reg_wr_strb);
                            12'h008: output_flags[output_index] <= apply_wstrb(output_flags[output_index], reg_wr_data, reg_wr_strb);
                            default: begin
                            end
                            endcase
                        end
                    end
                end
                endcase
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
