// TX Stage Module
module tx (
    input logic clk,            // System clock
    input logic rst_n,          // Active low reset
    input logic spi_clk,        // SPI clock
    input logic spi_r,          // SPI read enable
    
    // ALU interface - proper handshaking
    input logic [17:0] res_data,   // 18-bit result from ALU
    input logic carry_in,          // Carry from ALU
    input logic res_valid,         // Result valid from ALU
    output logic res_ready,        // Ready to accept result (to ALU)

    // SPI interface
    output logic [7:0]  miso,      // 8-bit MISO data output
    output logic carry_out,        // Carry output signal (to uio[3])
    output logic tx_done           // Transmission complete flag
);

    // Internal signals and registers (5 bytes for symmetry with RX)
    logic [7:0] tx_reg0;         // Byte 0: Result[7:0]
    logic [7:0] tx_reg1;         // Byte 1: Result[15:8]
    logic [7:0] tx_reg2;         // Byte 2: {carry, 5'b0, result[17:16]}
    logic [7:0] tx_reg3;         // Byte 3: Status/flags (reserved for future use)
    logic [7:0] tx_reg4;         // Byte 4: Reserved/checksum (optional)
    logic [2:0] byte_counter;    // MOD-5 counter for transmission (0-4)
    logic spi_clk_prev;          // For edge detection
    logic spi_clk_rising;        // Rising edge detect
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

    // Handshaking logic - ready when we can accept new result
    // Ready when not holding a result OR when actively transmitting (will be done soon)
    assign res_ready = !result_captured || tx_active;

    // Load TX registers when result is valid and we're ready
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_reg0 <= 8'h00;
            tx_reg1 <= 8'h00;
            tx_reg2 <= 8'h00;
            tx_reg3 <= 8'h00;
            tx_reg4 <= 8'h00;
            result_captured <= 1'b0;
        end else if (res_valid && res_ready) begin
            // Capture new result from ALU
            tx_reg0 <= res_data[7:0];                          // Lower byte
            tx_reg1 <= res_data[15:8];                         // Middle byte
            tx_reg2 <= {carry_in, 5'b00000, res_data[17:16]}; // Upper 2 bits + carry + padding
            tx_reg3 <= 8'h00;                                  // Status/flags (reserved)
            tx_reg4 <= 8'h00;                                  // Reserved/checksum
            result_captured <= 1'b1;
        end else if (tx_done) begin
            // Clear captured flag after transmission completes
            result_captured <= 1'b0;
        end
    end

    // Transmission active flag
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_active <= 1'b0;
        end else if (result_captured && !tx_active && spi_r) begin
            // Start transmission when we have data and SPI read is enabled
            tx_active <= 1'b1;
        end else if (tx_done) begin
            tx_active <= 1'b0;
        end
    end

    // Byte counter for transmission (MOD-5 to match RX symmetry)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_counter <= 3'b000;
        end else if (!tx_active) begin
            byte_counter <= 3'b000;
        end else if (spi_clk_rising && spi_r && tx_active) begin
            if (byte_counter == 3'b100) begin  // Reset after 5 bytes (0-4)
                byte_counter <= 3'b000;
            end else begin
                byte_counter <= byte_counter + 1'b1;
            end
        end
    end

    // 5:1 Mux for MISO output (symmetric with RX)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            miso <= 8'h00;
        end else if (spi_clk_rising && spi_r && tx_active) begin
            case (byte_counter)
                3'b000: miso <= tx_reg0;  // Byte 0: Result[7:0]
                3'b001: miso <= tx_reg1;  // Byte 1: Result[15:8]
                3'b010: miso <= tx_reg2;  // Byte 2: {carry, 5'b0, Result[17:16]}
                3'b011: miso <= tx_reg3;  // Byte 3: Status/flags
                3'b100: miso <= tx_reg4;  // Byte 4: Reserved
                default: miso <= 8'h00;
            endcase
        end else begin
            miso <= 8'h00;  // Default to 0 when not reading
        end
    end

    // Carry output (could be routed to uio[3] as RES_CARRY)
    assign carry_out = carry_in;

    // TX done signal - indicates complete result transmitted (all 5 bytes)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_done <= 1'b0;
        end else if (spi_clk_rising && spi_r && tx_active && (byte_counter == 3'b100)) begin
            tx_done <= 1'b1;  // Set done when last byte (byte 4) transmitted
        end else begin
            tx_done <= 1'b0;
        end
    end

endmodule