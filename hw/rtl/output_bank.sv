module output_bank #(
    parameter int unsigned MAX_OUTPUTS = 16,
    parameter int unsigned CLK_HZ = 100_000_000,
    parameter int unsigned T0H_NS = 250,
    parameter int unsigned T0L_NS = 1_000,
    parameter int unsigned T1H_NS = 600,
    parameter int unsigned T1L_NS = 650,
    parameter int unsigned RESET_NS = 50_000
) (
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         global_enable,
    input  logic                         start_frame,
    input  logic [MAX_OUTPUTS-1:0]       output_enable,

    input  logic [MAX_OUTPUTS*24-1:0]    pixel_rgb_flat,
    input  logic [MAX_OUTPUTS-1:0]       pixel_valid,
    output logic [MAX_OUTPUTS-1:0]       pixel_ready,
    input  logic [MAX_OUTPUTS-1:0]       output_end_frame,

    output logic [MAX_OUTPUTS-1:0]       output_busy,
    output logic [MAX_OUTPUTS-1:0]       output_done_pulse,
    output logic [MAX_OUTPUTS-1:0]       output_underrun_pulse,
    output logic [MAX_OUTPUTS-1:0]       ws2811_out
);

    for (genvar output_index = 0; output_index < MAX_OUTPUTS; output_index++) begin : gen_output
        ws2811_tx #(
            .CLK_HZ(CLK_HZ),
            .T0H_NS(T0H_NS),
            .T0L_NS(T0L_NS),
            .T1H_NS(T1H_NS),
            .T1L_NS(T1L_NS),
            .RESET_NS(RESET_NS)
        ) tx (
            .clk(clk),
            .rst_n(rst_n),
            .enable(global_enable && output_enable[output_index]),
            .start(start_frame),
            .end_frame(output_end_frame[output_index]),
            .pixel_rgb(pixel_rgb_flat[output_index*24 +: 24]),
            .pixel_valid(pixel_valid[output_index]),
            .pixel_ready(pixel_ready[output_index]),
            .busy(output_busy[output_index]),
            .done_pulse(output_done_pulse[output_index]),
            .underrun_pulse(output_underrun_pulse[output_index]),
            .dout(ws2811_out[output_index])
        );
    end

endmodule
