//TX Stage Module
//Result: 10 bits + carry (from 4-bit ALU)
//Format: [res[3:0]][res[7:4]][res[9:8],carry,1'b0][status][reserved]

`timescale 1ns/1ps
`default_nettype none

module tx_4b (
    input logic clk,            //System clock
    input logic rst_n,          //Active low reset
    input logic spi_clk,        //SPI clock
    input logic spi_r,          //SPI read enable
    
    //ALU interface
    input logic [9:0] res_data,    //10 bit result from ALU
    input logic carry_in,          //Carry from ALU
    input logic res_valid,         //Result valid from ALU
    output logic res_ready,        //Ready to accept result

    //SPI interface
    output logic [3:0]  miso,      //4-bit MISO data output
    output logic carry_out,        //Carry output signal
    output logic tx_done           //Transmission complete flag
);

    //Internal signals and registers
    logic [3:0] tx_reg0;         //Nibble 0: Result[3:0]
    logic [3:0] tx_reg1;         //Nibble 1: Result[7:4]
    logic [3:0] tx_reg2;         //Nibble 2: {Result[9:8], carry, 1'b0}
    logic [3:0] tx_reg3;         //Nibble 3: Status/flags
    logic [3:0] tx_reg4;         //Nibble 4: Reserved/checksum
    logic [2:0] nibble_counter;  //MOD 5 counter for transmission
    logic spi_clk_prev;          //Previous SPI clock value for edge detection
    logic spi_clk_rising;        //Rising edge detect signal
    logic spi_clk_falling;       //Falling edge detect signal
    logic tx_active;             //Transmission in progress flag
    logic result_captured;       //Result has been captured in registers

    //Track previous SPI clock state for edge detection
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_clk_prev <= 1'b0;
        end else begin
            spi_clk_prev <= spi_clk;
        end
    end

    //Detect SPI clock edges
    assign spi_clk_rising = spi_clk & ~spi_clk_prev;
    assign spi_clk_falling = ~spi_clk & spi_clk_prev;

    //Handshaking logic, ready when it can accept new result
    //Ready when not holding a result or when actively transmitting
    assign res_ready = !result_captured || tx_active;

    //Load TX registers when result is valid and its ready
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            //Clear all registers on reset
            tx_reg0 <= 4'h0;
            tx_reg1 <= 4'h0;
            tx_reg2 <= 4'h0;
            tx_reg3 <= 4'h0;
            tx_reg4 <= 4'h0;
            result_captured <= 1'b0;
        //Only load new data if not currently transmitting
        end else if (res_valid && res_ready && !tx_active) begin
            //Capture new result from ALU into TX registers
            tx_reg0 <= res_data[3:0];                      //Lower nibble
            tx_reg1 <= res_data[7:4];                      //Middle nibble
            tx_reg2 <= {res_data[9:8], carry_in, 1'b0};    //Upper 2 bits + carry + padding
            tx_reg3 <= 4'h0;                               //Status/flags
            tx_reg4 <= 4'h0;                               //Reserved/checksum
            result_captured <= 1'b1;
        //Clear buffer only when done and no new data is waiting
        end else if (tx_done && !res_valid) begin 
            result_captured <= 1'b0;
        //Handle case where new data arrives exactly as transmission finishes
        end else if (tx_done && res_valid) begin
            //Load new data immediately
            tx_reg0 <= res_data[3:0];
            tx_reg1 <= res_data[7:4];
            tx_reg2 <= {res_data[9:8], carry_in, 1'b0};
            tx_reg3 <= 4'h0;
            tx_reg4 <= 4'h0;
            result_captured <= 1'b1; //Remain captured
        end
    end

    //Transmission active flag management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_active <= 1'b0;
        //Start transmission when we have data and SPI read is enabled
        end else if (result_captured && !tx_active && spi_r) begin
            tx_active <= 1'b1;
        //Stop transmission when done
        end else if (tx_done) begin
            tx_active <= 1'b0;
        end
    end

    //Nibble counter for transmission
    //Increment on falling edge of SPI clock
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nibble_counter <= 3'b000;
        //Reset counter when not transmitting
        end else if (!tx_active) begin
            nibble_counter <= 3'b000;
        //Increment counter after data has been read on rising edge
        end else if (spi_clk_falling && spi_r && tx_active) begin
            if (nibble_counter == 3'b100) begin  //Reset after 5 nibbles
                nibble_counter <= 3'b000;
            end else begin
                nibble_counter <= nibble_counter + 1'b1;
            end
        end
    end

    //Mux for MISO output
    always_comb begin
        miso = 4'h0;  //Default to 0 when not reading
        if (spi_r && tx_active) begin
            //Select appropriate TX register based on nibble counter
            case (nibble_counter)
                3'b000: miso = tx_reg0;  //Nibble 0: Result[3:0]
                3'b001: miso = tx_reg1;  //Nibble 1: Result[7:4]
                3'b010: miso = tx_reg2;  //Nibble 2: {Result[9:8], carry, 1'b0}
                3'b011: miso = tx_reg3;  //Nibble 3: Status/flags
                3'b100: miso = tx_reg4;  //Nibble 4: Reserved
                default: miso = 4'h0;
            endcase
        end
    end

    //Carry output
    assign carry_out = carry_in;

    //TX done signal, indicates complete result transmitted
    //Pulse tx_done on falling edge of 5th nibble
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_done <= 1'b0;
        //Assert done when last nibble has been transmitted
        end else if (spi_clk_falling && spi_r && tx_active && (nibble_counter == 3'b100)) begin
            tx_done <= 1'b1;
        end else begin
            tx_done <= 1'b0; //This makes it a 1 cycle pulse
        end
    end

endmodule