//Testbench wrapper for rx_4b module

`timescale 1ns / 1ps
`default_nettype none

module rx_tb_4b (
    input  wire       clk,
    input  wire       rst_n,
    
    //SPI interface
    input  wire       spi_clk,      //SPI clock signal
    input  wire       spi_w,        //SPI write enable
    input  wire [3:0] mosi,         //4-bit MOSI data line
    
    //Control input
    input  wire       alu_ready,    //Signal indicating ALU is ready for new instruction
    
    //Outputs
    output wire [3:0] op_reg,       //Opcode register 
    output wire [3:0] a1_reg,       //Operand A1 register 
    output wire [3:0] a2_reg,       //Operand A2 register 
    output wire [3:0] b1_reg,       //Operand B1 register 
    output wire [3:0] b2_reg,       //Operand B2 register 
    output wire       rx_valid      //Indicates complete instruction received
);

    //Instantiate the RX_4B module, Device Under Test (DUT)
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

    //Clock generation handled by cocotb during testing
    initial begin
        //Clock will be driven by cocotb
    end

    //Generate VCD waveform dump for debugging if VCD_PATH is defined
    `ifdef VCD_PATH
    initial begin
        $dumpfile(`VCD_PATH);
        $dumpvars(0, rx_tb_4b);
    end
    `endif

endmodule