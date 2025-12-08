module sine_wave_generator #(
    parameter SAMPLE_DIV = 1000,
    parameter SAMPLES_PER_PERIOD = 200,
    parameter SPI_DIV = 8
)(
    input  logic rst_n,
    output logic spi_cs_n,
    output logic spi_sck,
    output logic spi_mosi
);

    // HF internal oscillator
    logic clk;
    HSOSC #(.CLKHF_DIV(2'b01)) hf_osc (
        .CLKHFPU(1'b1),
        .CLKHFEN(1'b1),
        .CLKHF(clk)
    );

    // LUT output sample
    logic [7:0]  lut_index;
    logic [11:0] lut_sample;

    // Instantiate LUT
    sine_lut #(
        .SAMPLES_PER_PERIOD(SAMPLES_PER_PERIOD)
    ) lut_inst (
        .index(lut_index),
        .value(lut_sample)
    );

    // Instantiate FSM
    sine_wave_fsm #(
        .SAMPLE_DIV(SAMPLE_DIV),
        .SAMPLES_PER_PERIOD(SAMPLES_PER_PERIOD),
        .SPI_DIV(SPI_DIV)
    ) fsm_inst (
        .clk(clk),
        .rst_n(rst_n),
        .current_sample(lut_sample),
        .phase_index(lut_index),

        .spi_cs_n(spi_cs_n),
        .spi_sck(spi_sck),
        .spi_mosi(spi_mosi)
    );

endmodule
