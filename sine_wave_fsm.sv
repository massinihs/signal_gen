module sine_wave_fsm #(
    parameter SAMPLE_DIV = 1000,
    parameter SAMPLES_PER_PERIOD = 200,
    parameter SPI_DIV = 8
)(
    input  logic clk,
    input  logic rst_n,

    input  logic [11:0] current_sample,
    output logic [7:0]  phase_index,

    output logic spi_cs_n,
    output logic spi_sck,
    output logic spi_mosi
);

    // Sample tick generator (48 kHz) //
    logic [9:0] sample_counter;
    logic sample_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_counter <= 0;
            sample_tick <= 0;
        end else begin
            sample_tick <= 0;
            if (sample_counter >= SAMPLE_DIV - 1) begin
                sample_counter <= 0;
                sample_tick <= 1;
            end else begin
                sample_counter <= sample_counter + 1;
            end
        end
    end

    // LUT index increment //
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            phase_index <= 0;
        else if (sample_tick)
            phase_index <= (phase_index == SAMPLES_PER_PERIOD - 1)
                           ? 0 : phase_index + 1;
    end

    // SPI state machine //
    localparam IDLE = 1'd0;
    localparam TRANSMIT = 1'd1;

    logic spi_state;
    logic [15:0] spi_data;
    logic [4:0]  bit_counter;
    logic [3:0]  spi_clk_div;
    logic start_transmission;

    // MCP4822 command: 0011,{data}
    wire [15:0] dac_cmd = {4'b0011, current_sample};

    // FSM //
    always @(posedge clk or negedge rst_n) begin
        // reset values
        if (!rst_n) begin
            spi_state <= IDLE;
            spi_cs_n <= 1;
            spi_sck <= 0;
            spi_mosi <= 0;
            bit_counter <= 0;
            spi_clk_div <= 0;
            start_transmission <= 0;
        end else begin

            // Begin SPI transmission at each sample_tick
            if (sample_tick)
                start_transmission <= 1;

            case (spi_state)

                IDLE: begin
                    spi_cs_n <= 1;
                    spi_sck <= 0;

                    if (start_transmission) begin
                        spi_data <= dac_cmd;
                        bit_counter <= 15;
                        spi_cs_n <= 0;
                        spi_state <= TRANSMIT; // go to TRANSMIT state
                        spi_clk_div <= 0;
                        start_transmission <= 0;
                    end
                end

                TRANSMIT: begin
                    // SCK clock 
                    if (spi_clk_div >= SPI_DIV - 1) begin
                        spi_clk_div <= 0;
                        spi_sck <= ~spi_sck; 
                        if (spi_sck) begin
                            if (bit_counter == 0)
                                spi_state <= IDLE;
                            else
                                bit_counter <= bit_counter - 1; // shift MOSI
                        end else begin
                            spi_mosi <= spi_data[bit_counter];
                        end
                    end else begin
                        spi_clk_div <= spi_clk_div + 1; 
                    end
                end

            endcase
        end
    end
endmodule
