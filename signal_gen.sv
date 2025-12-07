module sine_wave_generator #(
    parameter SAMPLE_DIV = 1000, // Divides main clock to 48 kHz
    parameter SAMPLES_PER_PERIOD = 200, // Number of samples per period
    parameter SPI_DIV = 8  // Divides main clock for SCK
) (
    input  logic rst_n,      // Active low reset
    output logic spi_cs_n,   // SPI chip select (active low)
    output logic spi_sck,    // SPI clock
    output logic spi_mosi    // SPI data out
);

    // Internal oscillator
    logic clk;
    HSOSC #(.CLKHF_DIV(2'b01)) hf_osc (
        .CLKHFPU(1'b1),
        .CLKHFEN(1'b1),
        .CLKHF(clk)
    );
   
    // Arbitrary data 
    logic [11:0] arb_wave [0:200];

    initial begin
        arb_wave = '{
            // 0–49: RANDOM NOISE
            12'd1055, 12'd3145, 12'd2048, 12'd2114, 12'd3034, 12'd3464, 12'd99,   12'd2791, 12'd3995, 12'd4034,
            12'd445,  12'd202,  12'd3913, 12'd2329, 12'd529,  12'd4057, 12'd2085, 12'd2579, 12'd2088, 12'd1025,
            12'd3085, 12'd2644, 12'd3987, 12'd2627, 12'd3782, 12'd1064, 12'd293,  12'd3396, 12'd1879, 12'd2451,
            12'd2248, 12'd3731, 12'd3508, 12'd821,  12'd213,  12'd3247, 12'd1486, 12'd3894, 12'd1829, 12'd825,
            12'd1632, 12'd329,  12'd3276, 12'd2123, 12'd3474, 12'd1231, 12'd2121, 12'd3272, 12'd1031, 12'd3956,

            // 50–99: HIGH FREQUENCY 5,760 Hz
            12'd2860, 12'd3028, 12'd2898, 12'd2486, 12'd1841, 12'd1043, 12'd194,  12'd657,  12'd1487, 12'd2394,
            12'd3272, 12'd4007, 12'd4485, 12'd4713, 12'd4572, 12'd4068, 12'd3239, 12'd2154, 12'd901,  12'd414,
            12'd414,  12'd901,  12'd2154, 12'd3239, 12'd4068, 12'd4572, 12'd4713, 12'd4485, 12'd4007, 12'd3272,
            12'd2394, 12'd1487, 12'd657,  12'd194,  12'd1043, 12'd1841, 12'd2486, 12'd2898, 12'd3028, 12'd2860,

            // 100–149: LOW FREQUENCY 960 Hz
            12'd2048, 12'd2501, 12'd2942, 12'd3357, 12'd3734, 12'd4062, 12'd4328, 12'd4523, 12'd4639, 12'd4672,
            12'd4620, 12'd4485, 12'd4273, 12'd3987, 12'd3638, 12'd3239, 12'd2791, 12'd2310, 12'd1809, 12'd1299,
            12'd800,  12'd333,  12'd0,    12'd0,    12'd0,    12'd333,  12'd800,  12'd1299, 12'd1809, 12'd2310,
            12'd2791, 12'd3239, 12'd3638, 12'd3987, 12'd4273, 12'd4485, 12'd4620, 12'd4672, 12'd4639, 12'd4523,
            12'd4328, 12'd4062, 12'd3734, 12'd3357, 12'd2942, 12'd2501, 12'd2048, 12'd1594, 12'd1107, 12'd608,

            // 150–199: MEDIUM FREQUENCY 2,880 Hz
            12'd159,  12'd253,  12'd508,  12'd588,  12'd508,  12'd253,  12'd159,  12'd608,  12'd1107, 12'd1594,
            12'd2048, 12'd2459, 12'd2639, 12'd2735, 12'd2735, 12'd2639, 12'd2459, 12'd2222, 12'd1961, 12'd1711,
            12'd1509, 12'd1383, 12'd1350, 12'd1415, 12'd1569, 12'd1791, 12'd2048,

            // 200
            12'd2048
        };

    end

   
   
    logic [9:0] sample_counter;
    logic sample_tick;
   
   // SAMPLE PULSE//
   // get a 48 kHz pulse sample_tick
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
   
    
    logic [5:0] phase_index;
    logic [11:0] current_sample;
   

   // LUT INDEX //
   // Switch to another index in the LUT based on 96 kHz pulse sample_tick
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_index <= 0;
        end else if (sample_tick) begin
            if (phase_index >= SAMPLES_PER_PERIOD - 1)
                phase_index <= 0;
            else
                phase_index <= phase_index + 1;
        end
    end
   
    always @(posedge clk) begin
        current_sample <= arb_wave[phase_index];
    end
   
    // SPI FSM states
    localparam IDLE = 1'd0;
    localparam TRANSMIT = 1'd1;
   
    logic spi_state;
    logic [4:0] bit_counter;  // which bit of the 16 bits of the SPI transmission are we on
    logic [15:0] spi_data;    // 16 bit SPI Data
    logic [3:0] spi_clk_div;  // SPI sck clock divisor 
    logic start_transmission; //
   
    // MCP4822 command format: {A/B, 0, GA, SHDN, Data[11:0]}
    // 0011xxxxxxxxxxxx
    wire [15:0] dac_command = {4'b0011, current_sample};
   
    // MAIN FSM //
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_state <= IDLE;
            spi_cs_n <= 1;
            spi_sck <= 0;
            spi_mosi <= 0;
            bit_counter <= 0;
            spi_clk_div <= 0;
            start_transmission <= 0;
        end else begin
            // start SPI communication
            if (sample_tick)
                start_transmission <= 1;
           
            case (spi_state)
                IDLE: begin
                    spi_cs_n <= 1; // turn off communication
                    spi_sck <= 0;
                   
                    // if clock pulse, start communication
                    if (start_transmission) begin
                        spi_data <= dac_command;
                        spi_state <= TRANSMIT; // go to TRANSMIT state
                        bit_counter <= 15;
                        spi_cs_n <= 0;
                        spi_clk_div <= 0;
                        start_transmission <= 0;
                    end
                end
               
                TRANSMIT: begin
                    // Set up SPI clock of 3 MHz, SPI_DIV = 8, 48 MHz/ 16 = 3 MHz
                    if (spi_clk_div >= SPI_DIV - 1) begin
                        spi_clk_div <= 0;
                        spi_sck <= ~spi_sck;
                       
                        if (spi_sck) begin  
                            if (bit_counter == 0) begin
                                spi_state <= IDLE;
                            end else begin
                                bit_counter <= bit_counter - 1; // shift 
                            end
                        end else begin  
                            spi_mosi <= spi_data[bit_counter]; // populate mosi bit
                        end
                    end else begin
                        spi_clk_div <= spi_clk_div + 1; // update counter
                    end
                end
               
                default: spi_state <= IDLE;
            endcase
        end
    end

endmodule
