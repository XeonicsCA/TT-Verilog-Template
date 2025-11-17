/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */
 
// Top-level Math Accelerator Unit (MAU) Module
// Integrates RX, Decode, ALU, and TX stages

// 4-BIT VERSION OF MAU_TOP
// tx/rx still handle 8-bit input/output but only lower 4-bits are used for operations

`timescale 1ns/1ps
`default_nettype none

module tt_um_mau_top (
    input  wire [7:0] ui_in,    // MOSI[7:0] - Instruction/Operand input
    output wire [7:0] uo_out,   // MISO[7:0] - Result output
    input  wire [7:0] uio_in,   // IOs: Input path, SPI clock (uio_in[0]), SPI write enable (uio_in[1]), SPI read enable (uio_in[2])
    output wire [7:0] uio_out,  // IOs: Output path, Result carry output (uio_out[3])
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // setup bidirectional IO
    assign uio_oe = 8'b0000_1000;

    // drive unused bidir outputs to known values
    assign uio_out[7:4] = 4'b0000;
    assign uio_out[2:0] = 3'b000;
    assign uo_out[7:4] = 4'b0000;  // Drive unused upper 4 bits to 0

    // Internal interconnect signals
    // Modified signals from 8b width to 4b width for RX, Decode, and TX
    
    // RX to Decode signals
    logic [3:0] rx_op;          // Opcode from RX
    logic [3:0] rx_a1;          // Operand a1 from RX
    logic [3:0] rx_a2;          // Operand a2 from RX
    logic [3:0] rx_b1;          // Operand b1 from RX
    logic [3:0] rx_b2;          // Operand b2 from RX
    logic       rx_valid;       // Valid instruction from RX
    
    // Decode to ALU signals
    logic       cmd_valid;      // Valid command to ALU
    logic [3:0] dec_x0;         // X lane operand 0
    logic [3:0] dec_x1;         // X lane operand 1
    logic [3:0] dec_y0;         // Y lane operand 0
    logic [3:0] dec_y1;         // Y lane operand 1    
    alu_pkg::alu_ctrl_t  alu_ctrl;   // ALU control signals  

    // ALU to TX signals
    logic [9:0] alu_result;     // 10-bit result from ALU
    logic        alu_carry;     // Carry from ALU
    logic        res_valid;     // Result valid from ALU
    
    // Handshaking signals
    logic        alu_ready;     // ALU ready (from decode to RX)
    logic        cmd_ready;     // Command ready (from ALU to decode)
    logic        res_ready;     // Result ready (from TX to ALU)
    
    // TX status
    logic        tx_done;       // Transmission complete
    
    // Module instantiations
    
    // RX Stage - Receives 20-bit instructions via SPI
    rx_4b rx_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .spi_clk    (uio_in[0]),
        .spi_w      (uio_in[1]),
        .mosi       (ui_in[3:0]),       // 4-bit MOSI input
        .alu_ready  (alu_ready),        // From decode stage
        
        // Outputs to decode
        .op         (rx_op),
        .a1         (rx_a1),
        .a2         (rx_a2),
        .b1         (rx_b1),
        .b2         (rx_b2),
        .rx_valid   (rx_valid)
    );
    
    // Decode Stage - Routes operands and generates control signals
    decode_stage_4b decode_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx_valid_in   (rx_valid),     // From RX
        .cmd_ready_in  (cmd_ready),    // From ALU
        
        // Inputs from RX
        .op         (rx_op),
        .a1         (rx_a1),
        .a2         (rx_a2),
        .b1         (rx_b1),
        .b2         (rx_b2),
        
        // Outputs
        .alu_ready_out  (alu_ready),    // To RX
        .cmd_valid_out  (cmd_valid),    // To ALU
        .ctrl       (alu_ctrl),         // To ALU
        .x0         (dec_x0),
        .x1         (dec_x1),
        .y0         (dec_y0),
        .y1         (dec_y1)
    );
    
    // ALU Stage - Performs mathematical operations
    alu_stage_4b alu_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        
        // Inputs from decode
        .x0         (dec_x0),
        .x1         (dec_x1),
        .y0         (dec_y0),
        .y1         (dec_y1),
        .ctrl       (alu_ctrl),
        
        // Handshaking
        .cmd_valid  (cmd_valid),    // From decode
        .cmd_ready  (cmd_ready),    // To decode
        .res_valid  (res_valid),    // To TX
        .res_ready  (res_ready),    // From TX
        
        // Results
        .res_q      (alu_result),
        .carry_q    (alu_carry)
    );
    
    // TX Stage - Serializes results back via SPI
    tx_4b tx_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .spi_clk    (uio_in[0]),
        .spi_r      (uio_in[2]),
        
        // From ALU
        .res_data   (alu_result),
        .carry_in   (alu_carry),
        .res_valid  (res_valid),
        .res_ready  (res_ready),    // To ALU
        
        // Outputs
        .miso       (uo_out[3:0]),    // 4-bit MISO output
        .carry_out  (uio_out[3]),     // Carry to uio_out[3]
        .tx_done    (tx_done)
    );

    // unused inputs to prevent warnings
    wire _unused = &{ena, 1'b0};

endmodule