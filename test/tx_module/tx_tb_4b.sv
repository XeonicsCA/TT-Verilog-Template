// SPDX-License-Identifier: Apache-2.0
// Testbench wrapper for tx_4b module
// Exposes I/O signals for cocotb unit testing

// 4-BIT VERSION OF TX_TB

`timescale 1ns / 1ps
`default_nettype none

module tx_tb_4b;

    // System clock and reset
    logic clk;
    logic rst_n;
    
    // SPI interface
    logic spi_clk;
    logic spi_r;          // SPI read enable (driven by test)
    
    // ALU interface (driven by test)
    logic [9:0] res_data;
    logic       carry_in;
    logic       res_valid;
    
    // DUT Outputs (monitored by test)
    logic       res_ready;
    wire [3:0]  miso;
    wire        carry_out;
    wire        tx_done;

    // Instantiate the TX_4B module (Device Under Test)
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

    // Simple clock for interactive waveform debugging (cocotb also drives clk)
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // 100 MHz
    end

    // Convenient VCD dump for waveform viewers
    `ifdef VCD_PATH
    initial begin
        $dumpfile(`VCD_PATH);
        $dumpvars(0, tx_tb_4b);
    end
    `endif

endmodule