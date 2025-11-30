//Testbench wrapper for tx_4b module

`timescale 1ns / 1ps
`default_nettype none

module tx_tb_4b;
    //System signals
    logic clk;              //System clock
    logic rst_n;            //Active low reset
    
    //SPI interface signals
    logic spi_clk;          //SPI clock
    logic spi_r;            //SPI read enable
    
    //ALU interface, simulated ALU for TX tests
    logic [9:0] res_data;   //10 bit result data from ALU
    logic       carry_in;   //Carry bit from ALU
    logic       res_valid;  //Result valid signal from ALU
    
    //DUT Outputs
    logic       res_ready;  //Ready signal to ALU
    wire [3:0]  miso;       //4 bit MISO output line
    wire        carry_out;  //Carry output
    wire        tx_done;    //Transmission complete flag

    //Instantiate the TX_4B module, Device Under Test (DUT)
    tx_4b dut (
        .clk(clk),
        .rst_n(rst_n),
        .spi_clk(spi_clk),
        .spi_r(spi_r),
        
        .res_data(res_data),
        .carry_in(carry_in),
        .res_valid(res_valid),
        
        .res_ready(res_ready),
        .miso(miso),
        .carry_out(carry_out),
        .tx_done(tx_done)
    );

    //Generate 100MHz clock for simulation
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // Toggle every 5ns
    end

    //Generate VCD waveform dump for debugging if VCD_PATH is defined
    `ifdef VCD_PATH
    initial begin
        $dumpfile(`VCD_PATH);
        $dumpvars(0, tx_tb_4b);
    end
    `endif

endmodule