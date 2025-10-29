// TX Stage Module

module tx (
    input logic clk,            // System clock
    input logic rst_n,          // Active low reset
    input logic spi_clk,        // SPI clock
    input logic spi_r,          // SPI read enable
    input logic [17:0] result,  // 18-bit result from ALU
    input logic carry_in,       // Carry from ALU
    input logic result_valid,   // Result ready to transmit

    output logic [7:0]  miso,   // 8-bit MISO data output
    output logic carry_out,     // Carry output signal
    output logic tx_done        // Transmission complete flag
);

    // Internal signals and registers
    logic [7:0] tx_reg0;         // Bits [7:0] of result
    logic [7:0] tx_reg1;         // Bits [15:8] of result
    logic [7:0] tx_reg2;         // Bits [17:16] + status/carry bits
    logic [2:0] byte_counter;    // MOD-3 counter for transmission
    logic spi_clk_prev;          // For edge detection
    logic spi_clk_rising;        // Rising edge detect
    logic tx_active;             // Transmission in progress

    // Edge detection for SPI clock
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_clk_prev <= 1'b0;
        end else begin
            spi_clk_prev <= spi_clk;
        end
    end

    assign spi_clk_rising = spi_clk & ~spi_clk_prev;

    // Load TX registers when result is valid
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_reg0 <= 8'h00;
            tx_reg1 <= 8'h00;
            tx_reg2 <= 8'h00;
        end else if (result_valid && !tx_active) begin
            tx_reg0 <= result[7:0];                          // Lower byte
            tx_reg1 <= result[15:8];                         // Middle byte
            tx_reg2 <= {5'b00000, carry_in, result[17:16]}; // Upper 2 bits + carry + padding
        end
    end

    // Transmission active flag
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_active <= 1'b0;
        end else if (result_valid && !tx_active && spi_r) begin
            tx_active <= 1'b1;
        end else if (tx_done) begin
            tx_active <= 1'b0;
        end
    end

    // Byte counter for transmission
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_counter <= 3'b000;
        end else if (!tx_active) begin
            byte_counter <= 3'b000;
        end else if (spi_clk_rising && spi_r && tx_active) begin
            if (byte_counter == 3'b010) begin  // Reset after 3 bytes (0-2)
                byte_counter <= 3'b000;
            end else begin
                byte_counter <= byte_counter + 1'b1;
            end
        end
    end

    // 3:1 Mux for MISO output
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            miso <= 8'h00;
        end else if (spi_r && tx_active) begin
            case (byte_counter)
                3'b000: miso <= tx_reg0;  // Byte 0: Result[7:0]
                3'b001: miso <= tx_reg1;  // Byte 1: Result[15:8]
                3'b010: miso <= tx_reg2;  // Byte 2: Result[17:16] + carry + padding
                default: miso <= 8'h00;
            endcase
        end else begin
            miso <= 8'h00;  // Default to 0 when not reading
        end
    end

    // Carry output (could be routed to uio[3] as RES_CARRY)
    assign carry_out = carry_in;

    // TX done signal - indicates complete result transmitted
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_done <= 1'b0;
        end else if (spi_clk_rising && spi_r && tx_active && (byte_counter == 3'b010)) begin
            tx_done <= 1'b1;  // Set done when last byte transmitted
        end else begin
            tx_done <= 1'b0;
        end
    end

endmodule
