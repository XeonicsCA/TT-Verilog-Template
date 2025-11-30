// RX Stage Module
// Instruction: 20 bits total (5 nibbles x 4 bits)
// Format: [op(4b)][a1(4b)][a2(4b)][b1(4b)][b2(4b)]

`timescale 1ns/1ps
`default_nettype none

module rx_4b (
    input  logic clk,           //System clock
    input  logic rst_n,         //Active low reset
    input  logic spi_clk,       //SPI clock
    input  logic spi_w,         //SPI write enable
    input  logic [3:0] mosi,    //4 bit MOSI data input 
    input  logic alu_ready,     //ALU ready to accept new instruction
    
    //Outputs to Decode Stage
    output logic [3:0] op,      //Opcode register 
    output logic [3:0] a1,      //Operand a1 register 
    output logic [3:0] a2,      //Operand a2 register 
    output logic [3:0] b1,      //Operand b1 register 
    output logic [3:0] b2,      //Operand b2 register 
    output logic rx_valid       //Indicates all 20 bits received and ready
);
    //Internal signals
    logic [2:0] nibble_counter;  //MOD 5 counter for tracking what the current nibble is
    logic spi_clk_prev;          //Previous SPI clock value for edge detection
    logic spi_clk_rising;        //Rising edge detect signal
    logic alu_ready_prev;        //Previous ALU ready state
    logic alu_ready_falling;     //ALU ready falling edge detect
    
    //Opcode and Operand Registers
    logic [3:0] op_reg;          //Opcode register [3:0] 
    logic [3:0] a1_reg;          //Operand a1 register [3:0] 
    logic [3:0] a2_reg;          //Operand a2 register [3:0] 
    logic [3:0] b1_reg;          //Operand b1 register [3:0] 
    logic [3:0] b2_reg;          //Operand b2 register [3:0] 

    //Track previous ALU ready state to detect when instruction has been accepted
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_ready_prev <= 1'b0;
        end else begin
            alu_ready_prev <= alu_ready;
        end
    end
    //Detect falling edge indicating ALU accepted instruction
    assign alu_ready_falling = alu_ready_prev & ~alu_ready;

    //Track previous SPI clock state for edge detection
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_clk_prev <= 1'b0;
        end else begin
            spi_clk_prev <= spi_clk;
        end
    end

    //Detect rising edge of SPI clock
    assign spi_clk_rising = spi_clk & ~spi_clk_prev;

    // MOD 5 Nibble Counter to track what the current nibble is
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nibble_counter <= 3'b000;
        //Reset counter if SPI write is disabled
        end else if (!spi_w) begin
            nibble_counter <= 3'b000;
        //Increment on SPI clock rising edge when write is enabled
        end else if (spi_clk_rising && spi_w) begin
            if (nibble_counter == 3'b100) begin  //Reset after 5 nibbles
                nibble_counter <= 3'b000;
            end else begin
                nibble_counter <= nibble_counter + 1'b1;
            end
        end
    end

    //1:5 Demux, it directs MOSI data to correct operand register based on nibble count
    //Only updates registers if ALU is ready or the MAU hasn't completed receiving yet
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            //Clear all registers on reset
            op_reg <= 4'h0;
            a1_reg <= 4'h0;
            a2_reg <= 4'h0;
            b1_reg <= 4'h0;
            b2_reg <= 4'h0;
        end else if (spi_clk_rising && spi_w) begin
            //Only update registers if ALU is ready to accept new data or MAU hasn't finished receiving current instruction yet
            if (alu_ready || !rx_valid) begin
                case (nibble_counter)
                    //Sample MOSI directly and route to appropriate register
                    3'b000: op_reg <= mosi; //Nibble 0: Opcode
                    3'b001: a1_reg <= mosi; //Nibble 1: Operand a1
                    3'b010: a2_reg <= mosi; //Nibble 2: Operand a2
                    3'b011: b1_reg <= mosi; //Nibble 3: Operand b1
                    3'b100: b2_reg <= mosi; //Nibble 4: Operand b2
                    default:;
                endcase
            end
            // Otherwise hold current values
        end
    end
    
    //Connect internal registers to output ports
    assign op = op_reg;
    assign a1 = a1_reg;
    assign a2 = a2_reg;
    assign b1 = b1_reg;
    assign b2 = b2_reg;

    //RX Valid signal, indicates complete 20 bit instruction received and ready for processing
    //Only asserts when ALU is ready to prevent data corruption
    //Clears rx_valid once ALU has accepted the instruction
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_valid <= 1'b0;
        //Set valid only when last nibble is received and ALU is ready
        end else if (spi_clk_rising && spi_w &&
                     (nibble_counter == 3'b100) && alu_ready) begin
            rx_valid <= 1'b1;
        //Clear valid once ALU has accepted instruction
        end else if (alu_ready_falling) begin
            rx_valid <= 1'b0;
        end
        //Otherwise maintain current value of rx_valid
    end

endmodule