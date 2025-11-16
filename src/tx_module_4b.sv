// TX Stage Module - 4-bit Version
// Result: 10 bits + carry (from 4-bit ALU)
// Format: [res[3:0]][res[7:4]][res[9:8],carry,1'b0][status][reserved]

`timescale 1ns/1ps
`default_nettype none

module tx_4b (
    input logic clk,            // System clock
    input logic rst_n,          // Active low reset
    input logic spi_clk,        // SPI clock
    input logic spi_r,          // SPI read enable
    
    // ALU interface - proper handshaking
    input logic [9:0] res_data,    // 10-bit result from ALU (reduced from 18-bit)
    input logic carry_in,          // Carry from ALU
    input logic res_valid,         // Result valid from ALU
    output logic res_ready,        // Ready to accept result (to ALU)

    // SPI interface
    output logic [3:0]  miso,      // 4-bit MISO data output (reduced from 8-bit)
    output logic carry_out,        // Carry output signal (to uio[3])
    output logic tx_done           // Transmission complete flag
);

    // Internal signals and registers (5 nibbles for symmetry with RX)
    logic [3:0] tx_reg0;         // Nibble 0: Result[3:0]
    logic [3:0] tx_reg1;         // Nibble 1: Result[7:4]
    logic [3:0] tx_reg2;         // Nibble 2: {Result[9:8], carry, 1'b0}
    logic [3:0] tx_reg3;         // Nibble 3: Status/flags (reserved for future use)
    logic [3:0] tx_reg4;         // Nibble 4: Reserved/checksum (optional)
    logic [2:0] nibble_counter;  // MOD-5 counter for transmission (0-4)
    logic spi_clk_prev;          // For edge detection
    logic spi_clk_rising;        // Rising edge detect
    logic spi_clk_falling;       // [FIX] Falling edge detect
    logic tx_active;             // Transmission in progress
    logic result_captured;       // Result has been captured in registers

    // Edge detection for SPI clock
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_clk_prev <= 1'b0;
        end else begin
            spi_clk_prev <= spi_clk;
        end
    end

    assign spi_clk_rising = spi_clk & ~spi_clk_prev;
    assign spi_clk_falling = ~spi_clk & spi_clk_prev; // [FIX] Add falling edge detector

    // Handshaking logic - ready when we can accept new result
    // Ready when not holding a result OR when actively transmitting
    assign res_ready = !result_captured || tx_active;

    // Load TX registers when result is valid and we're ready
    // [FIX] Updated handshake logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_reg0 <= 4'h0;
            tx_reg1 <= 4'h0;
            tx_reg2 <= 4'h0;
            tx_reg3 <= 4'h0;
            tx_reg4 <= 4'h0;
            result_captured <= 1'b0;
        // Only load new data if NOT currently transmitting
        end else if (res_valid && res_ready && !tx_active) begin
            // Capture new result from ALU
            tx_reg0 <= res_data[3:0];                      // Lower nibble
            tx_reg1 <= res_data[7:4];                      // Middle nibble
            tx_reg2 <= {res_data[9:8], carry_in, 1'b0};   // Upper 2 bits + carry + padding
            tx_reg3 <= 4'h0;                               // Status/flags (reserved)
            tx_reg4 <= 4'h0;                               // Reserved/checksum
            result_captured <= 1'b1;
        // Clear buffer *only* when done and no new data is waiting
        end else if (tx_done && !res_valid) begin 
            result_captured <= 1'b0;
        // Handle case where data arrives *exactly* as tx finishes
        end else if (tx_done && res_valid) begin
            tx_reg0 <= res_data[3:0]; // Load new data
            tx_reg1 <= res_data[7:4];
            tx_reg2 <= {res_data[9:8], carry_in, 1'b0};
            tx_reg3 <= 4'h0;
            tx_reg4 <= 4'h0;
            result_captured <= 1'b1; // Remain captured
        end
    end

    // Transmission active flag
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_active <= 1'b0;
        end else if (result_captured && !tx_active && spi_r) begin
            // Start transmission when we have data and SPI read is enabled
            tx_active <= 1'b1;
        end else if (tx_done) begin // tx_done is a pulse
            tx_active <= 1'b0;
        end
    end

    // Nibble counter for transmission (MOD-5 to match RX symmetry)
    // [FIX] Increment on FALLING edge of SPI clock
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nibble_counter <= 3'b000;
        end else if (!tx_active) begin // Reset counter if not active
            nibble_counter <= 3'b000;
        // Use spi_clk_falling to increment *after* test reads on rising edge
        end else if (spi_clk_falling && spi_r && tx_active) begin
            if (nibble_counter == 3'b100) begin  // Reset after 5 nibbles (0-4)
                nibble_counter <= 3'b000;
            end else begin
                nibble_counter <= nibble_counter + 1'b1;
            end
        end
    end

    // [FIX] Mux for MISO output (switched to combinational)
    always_comb begin
        miso = 4'h0;  // Default to 0 when not reading
        if (spi_r && tx_active) begin
            case (nibble_counter)
                3'b000: miso = tx_reg0;  // Nibble 0: Result[3:0]
                3'b001: miso = tx_reg1;  // Nibble 1: Result[7:4]
                3'b010: miso = tx_reg2;  // Nibble 2: {Result[9:8], carry, 1'b0}
                3'b011: miso = tx_reg3;  // Nibble 3: Status/flags
                3'b100: miso = tx_reg4;  // Nibble 4: Reserved
                default: miso = 4'h0;
            endcase
        end
    end

    // Carry output (could be routed to uio[3] as RES_CARRY)
    assign carry_out = carry_in;

    // TX done signal - indicates complete result transmitted (all 5 nibbles)
    // [FIX] Pulse tx_done on FALLING edge of 5th nibble
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_done <= 1'b0;
        end else if (spi_clk_falling && spi_r && tx_active && (nibble_counter == 3'b100)) begin
            tx_done <= 1'b1;  // Set done when last nibble (nibble 4) transmitted
        end else begin
            tx_done <= 1'b0; // This makes it a 1-cycle pulse
        end
    end

endmodule