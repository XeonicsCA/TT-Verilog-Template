// SPDX-License-Identifier: Apache-2.0
// Testbench wrapper for rx_4b module
// Exposes internal signals for unit testing

// 4-BIT VERSION OF RX_TB

`timescale 1ns / 1ps
`default_nettype none

module rx_tb_4b (
    input  wire       clk,
    input  wire       rst_n,
    
    // SPI interface
    input  wire       spi_clk,
    input  wire       spi_w,
    input  wire [3:0] mosi,      // 4-bit MOSI (reduced from 8-bit)
    
    // Control input
    input  wire       alu_ready,
    
    // Outputs - exposed registers
    output wire [3:0] op_reg,    // 4-bit registers (reduced from 8-bit)
    output wire [3:0] a1_reg,
    output wire [3:0] a2_reg,
    output wire [3:0] b1_reg,
    output wire [3:0] b2_reg,
    output wire       rx_valid
);

    // Instantiate the RX_4B module
    rx_4b rx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .spi_clk(spi_clk),
        .spi_w(spi_w),
        .mosi(mosi),
        .alu_ready(alu_ready),
        .op(op_reg),
        .a1(a1_reg),
        .a2(a2_reg),
        .b1(b1_reg),
        .b2(b2_reg),
        .rx_valid(rx_valid)
    );

    // Simple clock for interactive waveform debugging (cocotb also drives clk)
    initial begin
        // Clock will be driven by cocotb
    end

    // Convenient VCD dump for waveform viewers
    `ifdef VCD_PATH
    initial begin
        $dumpfile(`VCD_PATH);
        $dumpvars(0, rx_tb_4b);
    end
    `endif

endmodule