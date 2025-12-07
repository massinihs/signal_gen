# signal_gen
This repo contains the signal generation from the FPGA to simulate the output of a current going through an insect.

The design uses a lookup table of 201 values to simulate the output signal going through an ant. 

The data values are repeated in 4 sections: Random noise, high frequency, low frequency, medium frequency. 

These data values are sent through SPI using a bit shifter for MOSI to the DAC. An FSM is required to determine whether the DAC is in the IDLE or TRANSMIT state. 
