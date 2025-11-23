// RX Stage Module - 4-bit Version
// Instruction: 20 bits total (5 nibbles x 4 bits)
// Format: [op(4b)][a1(4b)][a2(4b)][b1(4b)][b2(4b)]

`timescale 1ns/1ps
`default_nettype none

module rx_4b (
    input  logic clk,           // System clock
    input  logic rst_n,         // Active low reset
    input  logic spi_clk,       // SPI clock
    input  logic spi_w,         // SPI write enable
    input  logic [3:0] mosi,    // 4-bit MOSI data input (reduced from 8-bit)
    input  logic alu_ready,     // ALU ready to accept new instruction
    
    // Outputs to Decode Stage
    output logic [3:0] op,      // Opcode register (reduced from 8-bit)
    output logic [3:0] a1,      // Operand a1 register (reduced from 8-bit)
    output logic [3:0] a2,      // Operand a2 register (reduced from 8-bit)
    output logic [3:0] b1,      // Operand b1 register (reduced from 8-bit)
    output logic [3:0] b2,      // Operand b2 register (reduced from 8-bit)
    output logic rx_valid       // Indicates all 20 bits received and ready
);
    // Internal signals
    // logic [3:0] rx_register; // Removed rx_register
    logic [2:0] nibble_counter; // MOD-5 counter (0-4) for 5 nibbles
    logic spi_clk_prev;         // For edge detection
    logic spi_clk_rising;       // Rising edge detect
    logic alu_ready_prev;       // Track prev alu ready state
    logic alu_ready_falling;    // ALU ready falling-edge detect
    
    // Opcode and Operand Registers (20-bit instruction storage)
    logic [3:0] op_reg;         // Opcode register [3:0] (reduced from 8-bit)
    logic [3:0] a1_reg;         // Operand a1 register [3:0] (reduced from 8-bit)
    logic [3:0] a2_reg;         // Operand a2 register [3:0] (reduced from 8-bit)
    logic [3:0] b1_reg;         // Operand b1 register [3:0] (reduced from 8-bit)
    logic [3:0] b2_reg;         // Operand b2 register [3:0] (reduced from 8-bit)

    // Track ALU ready to detect when an instruction has been accepted
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_ready_prev <= 1'b0;
        end else begin
            alu_ready_prev <= alu_ready;
        end
    end
    assign alu_ready_falling = alu_ready_prev & ~alu_ready;

    // Edge detection for SPI clock
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_clk_prev <= 1'b0;
        end else begin
            spi_clk_prev <= spi_clk;
        end
    end

    assign spi_clk_rising = spi_clk & ~spi_clk_prev;

    // MOD-5 Nibble Counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nibble_counter <= 3'b000;
        // [FIX 3] Reset the counter if SPI write is disabled
        end else if (!spi_w) begin
            nibble_counter <= 3'b000;
        end else if (spi_clk_rising && spi_w) begin
            if (nibble_counter == 3'b100) begin  // Reset after 5 nibbles (0-4)
                nibble_counter <= 3'b000;
            end else begin
                nibble_counter <= nibble_counter + 1'b1;
            end
        end
    end

    // 1:5 Demux - Direct data to correct operand registers
    // Only updates registers if ALU is ready OR we haven't completed receiving yet
    // This implements minimal handshaking to prevent data loss
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_reg <= 4'h0;
            a1_reg <= 4'h0;
            a2_reg <= 4'h0;
            b1_reg <= 4'h0;
            b2_reg <= 4'h0;
        end else if (spi_clk_rising && spi_w) begin
            // Only update registers if:
            // 1. ALU is ready to accept new data, OR
            // 2. We haven't finished receiving current instruction yet (!rx_valid)
            if (alu_ready || !rx_valid) begin
                case (nibble_counter)
                    // [FIX 1] Sample mosi directly instead of rx_register
                    3'b000: op_reg <= mosi; // Nibble 0: Opcode
                    3'b001: a1_reg <= mosi; // Nibble 1: Operand a1
                    3'b010: a2_reg <= mosi; // Nibble 2: Operand a2
                    3'b011: b1_reg <= mosi; // Nibble 3: Operand b1
                    3'b100: b2_reg <= mosi; // Nibble 4: Operand b2
                    default:; // Should not occur
                endcase
            end
            // Otherwise hold current values (ALU busy and instruction complete)
        end
    end
    
    // Output assignments - pass registers to decode stage
    assign op = op_reg;
    assign a1 = a1_reg;
    assign a2 = a2_reg;
    assign b1 = b1_reg;
    assign b2 = b2_reg;

    // RX Valid signal - indicates complete 20-bit instruction received AND ready for processing
    // Only asserts when ALU is ready to prevent data corruption
    // In addition, clear rx_valid once the ALU has accepted the instruction
    // (detected via a falling edge on alu_ready), so back-to-back instructions
    // can be distinguished cleanly at the decode/ALU boundary.
    always_ff @(posedge clk or negedge rst_n) begin               // NEW
        if (!rst_n) begin                                          // NEW
            rx_valid <= 1'b0;                                      // NEW
        end else if (spi_clk_rising && spi_w &&                    // NEW
                     (nibble_counter == 3'b100) && alu_ready) begin// NEW
            // NEW: Set valid only when the last nibble is received
            // NEW: and the downstream ALU path is ready to take it.
            rx_valid <= 1'b1;                                      // NEW
        end else if (alu_ready_falling) begin                      // NEW
            // NEW: Once the ALU has accepted this instruction
            // NEW: (cmd_ready/alu_ready has gone 1->0), drop rx_valid
            // NEW: so the next 5-nibble transfer is treated as a new instruction.
            rx_valid <= 1'b0;                                      // NEW
        end                                                        // NEW
        // Otherwise hold the current value of rx_valid.            // NEW
    end

endmodule