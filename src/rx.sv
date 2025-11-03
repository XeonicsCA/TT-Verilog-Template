// RX Stage Module

module rx (
    input  logic clk,           // System clock
    input  logic rst_n,         // Active low reset
    input  logic spi_clk,       // SPI clock
    input  logic spi_w,         // SPI write enable
    input  logic [7:0] mosi,    // 8-bit MOSI data input
    input  logic alu_ready,     // ALU ready to accept new instruction
    
    // Outputs to Decode Stage
    output logic [7:0] op,      // Opcode/flags register
    output logic [7:0] a1,      // Operand a1 register
    output logic [7:0] a2,      // Operand a2 register
    output logic [7:0] b1,      // Operand b1 register
    output logic [7:0] b2,      // Operand b2 register
    output logic rx_valid       // Indicates all 40 bits received and ready
);

    // Internal signals
    logic [7:0] rx_register;    // 8-bit RX register for sampling MOSI
    logic [2:0] byte_counter;   // MOD-5 counter (0-4)
    logic spi_clk_prev;         // For edge detection
    logic spi_clk_rising;       // Rising edge detect
    
    // Opcode and Operand Registers (40-bit instruction storage)
    logic [7:0] op_reg;         // Opcode/flags register [7:0]
    logic [7:0] a1_reg;         // Operand a1 register [7:0]
    logic [7:0] a2_reg;         // Operand a2 register [7:0]
    logic [7:0] b1_reg;         // Operand b1 register [7:0]
    logic [7:0] b2_reg;         // Operand b2 register [7:0]

    // Edge detection for SPI clock
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_clk_prev <= 1'b0;
        end else begin
            spi_clk_prev <= spi_clk;
        end
    end

    assign spi_clk_rising = spi_clk & ~spi_clk_prev;

    // RX Register - samples MOSI on SPI_CLK rising edge when SPI_W is active
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_register <= 8'h00;
        end else if (spi_clk_rising && spi_w) begin
            rx_register <= mosi;
        end
    end

    // MOD-5 Byte Counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_counter <= 3'b000;
        end else if (spi_clk_rising && spi_w) begin
            if (byte_counter == 3'b100) begin  // Reset after 5 bytes (0-4)
                byte_counter <= 3'b000;
            end else begin
                byte_counter <= byte_counter + 1'b1;
            end
        end
    end

    // 1:5 Demux - Direct data to correct operand registers
    // Only updates registers if ALU is ready OR we haven't completed receiving yet
    // This implements minimal handshaking to prevent data loss
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_reg <= 8'h00;
            a1_reg <= 8'h00;
            a2_reg <= 8'h00;
            b1_reg <= 8'h00;
            b2_reg <= 8'h00;
        end else if (spi_clk_rising && spi_w) begin
            // Only update registers if:
            // 1. ALU is ready to accept new data, OR
            // 2. We haven't finished receiving current instruction yet (!rx_valid)
            if (alu_ready || !rx_valid) begin
                case (byte_counter)
                    3'b000: op_reg <= rx_register;  // Byte 0: Opcode/flags
                    3'b001: a1_reg <= rx_register;  // Byte 1: Operand a1
                    3'b010: a2_reg <= rx_register;  // Byte 2: Operand a2
                    3'b011: b1_reg <= rx_register;  // Byte 3: Operand b1
                    3'b100: b2_reg <= rx_register;  // Byte 4: Operand b2
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

    // RX Valid signal - indicates complete 40-bit instruction received AND ready for processing
    // Only asserts when ALU is ready to prevent data corruption
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_valid <= 1'b0;
        end else if (spi_clk_rising && spi_w && (byte_counter == 3'b100) && alu_ready) begin
            rx_valid <= 1'b1;  // Set valid only when last byte received AND ALU ready
        end else if (alu_ready) begin
            rx_valid <= 1'b0;  // Clear when ALU takes the data (ready goes high after processing)
        end
        // Hold rx_valid state if ALU is busy
    end

endmodule