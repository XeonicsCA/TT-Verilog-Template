//Top-level Math Accelerator Unit (MAU) Module
//Integrates RX, Decode, ALU, and TX stages

`timescale 1ns/1ps
`default_nettype none

module tt_um_mau_top_4b (
    input  wire [7:0] ui_in,    //MOSI[7:0] - Instruction/Operand input (only [3:0] used)
    output wire [7:0] uo_out,   //MISO[7:0] - Result output (only [3:0] used)
    input  wire [7:0] uio_in,   //IOs: Input path, SPI clock (uio_in[0]), SPI write enable (uio_in[1]), SPI read enable (uio_in[2])
    output wire [7:0] uio_out,  //IOs: Output path, Result carry output (uio_out[3])
    output wire [7:0] uio_oe,   //IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      //always 1 when the design is powered
    input  wire       clk,      //clock
    input  wire       rst_n     //reset_n, low to reset
);

    //Configure bidirectional IO pins (bit 3 is output for carry, rest are inputs)
    assign uio_oe = 8'b0000_1000;

    //Drive unused bidir outputs to known values
    assign uio_out[7:4] = 4'b0000;  //Upper 4 bits unused
    assign uio_out[2:0] = 3'b000;   //Lower 3 bits unused
    assign uo_out[7:4] = 4'b0000;   //Drive unused upper 4 bits of MISO to 0

    //Internal interconnect signals
    //Modified signals from 8b width to 4b width for RX, Decode, and TX
    
    //RX to Decode signals (instruction components)
    logic [3:0] rx_op;          //Opcode from RX stage
    logic [3:0] rx_a1;          //Operand a1 from RX stage
    logic [3:0] rx_a2;          //Operand a2 from RX stage
    logic [3:0] rx_b1;          //Operand b1 from RX stage
    logic [3:0] rx_b2;          //Operand b2 from RX stage
    logic       rx_valid;       //Valid instruction signal from RX
    
    //Decode to ALU signals (operands and control)
    logic       cmd_valid;      //Valid command to ALU
    logic [3:0] dec_x0;         //X lane operand 0 (routed from RX operands)
    logic [3:0] dec_x1;         //X lane operand 1 (routed from RX operands)
    logic [3:0] dec_y0;         //Y lane operand 0 (routed from RX operands)
    logic [3:0] dec_y1;         //Y lane operand 1 (routed from RX operands)
    alu_pkg::alu_ctrl_t  alu_ctrl;   //ALU control signals structure

    //ALU to TX signals (results)
    logic [9:0] alu_result;     //10 bit result from ALU
    logic        alu_carry;     //Carry bit from ALU
    logic        res_valid;     //Result valid signal from ALU
    
    //Handshaking signals (backpressure and flow control)
    logic        alu_ready;     //ALU ready signal (from decode to RX)
    logic        cmd_ready;     //Command ready signal (from ALU to decode)
    logic        res_ready;     //Result ready signal (from TX to ALU)
    
    //TX status
    logic        tx_done;       //Transmission complete flag
    
    //Module instantiations
    
    //RX Stage: Receives 20 bit instructions via SPI (5 nibbles x 4 bits)
    rx_4b rx_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .spi_clk    (uio_in[0]),        //SPI clock from bidirectional IO
        .spi_w      (uio_in[1]),        //SPI write enable from bidirectional IO
        .mosi       (ui_in[3:0]),       //4 bit MOSI input from dedicated inputs
        .alu_ready  (alu_ready),        //Backpressure from decode stage
        
        //Outputs to decode stage
        .op         (rx_op),
        .a1         (rx_a1),
        .a2         (rx_a2),
        .b1         (rx_b1),
        .b2         (rx_b2),
        .rx_valid   (rx_valid)
    );
    
    //Decode Stage: Routes operands and generates control signals based on opcode
    decode_stage_4b decode_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx_valid_in   (rx_valid),     //Valid instruction from RX
        .cmd_ready_in  (cmd_ready),    //Ready signal from ALU
        
        //Inputs from RX stage
        .op         (rx_op),
        .a1         (rx_a1),
        .a2         (rx_a2),
        .b1         (rx_b1),
        .b2         (rx_b2),
        
        //Outputs to other stages
        .alu_ready_out  (alu_ready),    //Backpressure to RX
        .cmd_valid_out  (cmd_valid),    //Valid command to ALU
        .ctrl       (alu_ctrl),         //Control signals to ALU
        .x0         (dec_x0),           //X lane operands to ALU
        .x1         (dec_x1),
        .y0         (dec_y0),           //Y lane operands to ALU
        .y1         (dec_y1)
    );
    
    //ALU Stage: Performs mathematical operations on operands
    alu_stage_4b alu_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        
        //Inputs from decode stage
        .x0         (dec_x0),
        .x1         (dec_x1),
        .y0         (dec_y0),
        .y1         (dec_y1),
        .ctrl       (alu_ctrl),         //Control signals from decode
        
        //Handshaking signals
        .cmd_valid  (cmd_valid),        //Valid command from decode
        .cmd_ready  (cmd_ready),        //Ready signal to decode
        .res_valid  (res_valid),        //Valid result to TX
        .res_ready  (res_ready),        //Ready signal from TX
        
        //Results to TX stage
        .res_q      (alu_result),
        .carry_q    (alu_carry)
    );
    
    //TX Stage: Serializes results back via SPI (5 nibbles x 4 bits)
    tx_4b tx_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .spi_clk    (uio_in[0]),        //SPI clock from bidirectional IO (shared with RX)
        .spi_r      (uio_in[2]),        //SPI read enable from bidirectional IO
        
        //From ALU stage
        .res_data   (alu_result),
        .carry_in   (alu_carry),
        .res_valid  (res_valid),
        .res_ready  (res_ready),        //Backpressure to ALU
        
        //Outputs
        .miso       (uo_out[3:0]),      //4 bit MISO output to dedicated outputs
        .carry_out  (uio_out[3]),       //Carry output to bidirectional IO
        .tx_done    (tx_done)
    );

    //Suppress warnings for unused inputs
    wire _unused = &{ena, 1'b0};

endmodule