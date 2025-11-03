// Top-level Math Accelerator Unit (MAU) Module
// Integrates RX, Decode, ALU, and TX stages

// First, include the ALU control structure definition
typedef struct packed {
    // X lane
    logic       pre_x_en;    // 0:x0, 1:add
    logic       pre_x_sub;   // 0:add, 1:sub
    logic       mul_x_en;    // 0:m0,m1, 1:mul
    logic [2:0] mul_x_sel;   // 0:x0, 1:x1, 2:square, 3:c_from_y1, 4:one (skip)

    // Y lane
    logic       pre_y_en;    // 0:y0, 1:add
    logic       pre_y_sub;   // 0:add, 1:sub
    logic       mul_y_en;    // 0:m0m1, 1:mul
    logic [2:0] mul_y_sel;   // 0:y0, 1:y1, 2:square, 3:c_from_x1, 4:one (skip)

    // Post adder
    logic       post_en;     // 0:concat, 1:add
    logic       post_sub;    // 0:add, 1:sub
    logic       post_sel;    // 0:b, 1:zero (skip)
} alu_ctrl_t;

module mau_top (
    // Global signals
    input  logic       clk,        // System clock (TT clock)
    input  logic       rst_n,      // Active low reset (TT global reset)
    
    // SPI Interface (matches TinyTapeout I/O)
    input  logic [7:0] ui_in,      // MOSI[7:0] - Instruction/Operand input
    output logic [7:0] ui_out,     // MISO[7:0] - Result output
    
    // Bidirectional I/O for SPI control
    input  logic       spi_clk,    // SPI clock (uio[0])
    input  logic       spi_w,      // SPI write enable (uio[1])
    input  logic       spi_r,      // SPI read enable (uio[2])
    output logic       res_carry   // Result carry output (uio[3])
);

    // Internal interconnect signals
    
    // RX to Decode signals
    logic [7:0] rx_op;          // Opcode from RX
    logic [7:0] rx_a1;          // Operand a1 from RX
    logic [7:0] rx_a2;          // Operand a2 from RX
    logic [7:0] rx_b1;          // Operand b1 from RX
    logic [7:0] rx_b2;          // Operand b2 from RX
    logic       rx_valid;       // Valid instruction from RX
    
    // Decode to ALU signals
    logic       cmd_valid;      // Valid command to ALU
    logic [7:0] dec_x0;         // X lane operand 0
    logic [7:0] dec_x1;         // X lane operand 1
    logic [7:0] dec_y0;         // Y lane operand 0
    logic [7:0] dec_y1;         // Y lane operand 1
    alu_ctrl_t  alu_ctrl;       // ALU control signals
    
    // ALU to TX signals
    logic [17:0] alu_result;    // 18-bit result from ALU
    logic        alu_carry;     // Carry from ALU
    logic        res_valid;     // Result valid from ALU
    
    // Handshaking signals
    logic        alu_ready;     // ALU ready (from decode to RX)
    logic        cmd_ready;     // Command ready (from ALU to decode)
    logic        res_ready;     // Result ready (from TX to ALU)
    
    // TX status
    logic        tx_done;       // Transmission complete
    
    // Module instantiations
    
    // RX Stage - Receives 40-bit instructions via SPI
    rx rx_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .spi_clk    (spi_clk),
        .spi_w      (spi_w),
        .mosi       (ui_in),        // 8-bit MOSI input
        .alu_ready  (alu_ready),    // From decode stage
        
        // Outputs to decode
        .op         (rx_op),
        .a1         (rx_a1),
        .a2         (rx_a2),
        .b1         (rx_b1),
        .b2         (rx_b2),
        .rx_valid   (rx_valid)
    );
    
    // Decode Stage - Routes operands and generates control signals
    decode_stage decode_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx_valid   (rx_valid),     // From RX
        .cmd_ready  (cmd_ready),    // From ALU
        
        // Inputs from RX
        .op         (rx_op),
        .a1         (rx_a1),
        .a2         (rx_a2),
        .b1         (rx_b1),
        .b2         (rx_b2),
        
        // Outputs
        .alu_ready  (alu_ready),    // To RX
        .cmd_valid  (cmd_valid),    // To ALU
        .ctrl       (alu_ctrl),     // To ALU
        .x0         (dec_x0),
        .x1         (dec_x1),
        .y0         (dec_y0),
        .y1         (dec_y1)
    );
    
    // ALU Stage - Performs mathematical operations
    alu_stage alu_inst (
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
    tx tx_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .spi_clk    (spi_clk),
        .spi_r      (spi_r),
        
        // From ALU
        .res_data   (alu_result),
        .carry_in   (alu_carry),
        .res_valid  (res_valid),
        .res_ready  (res_ready),    // To ALU
        
        // Outputs
        .miso       (ui_out),        // 8-bit MISO output
        .carry_out  (res_carry),     // Carry to uio[3]
        .tx_done    (tx_done)
    );

endmodule

// ==============================================================================
// ISSUES AND INCONSISTENCIES IDENTIFIED:
// ==============================================================================
//
// 1. ALU_CTRL_T DEFINITION:
//    - Problem: The typedef is defined in decode_module.sv but needed by ALU too
//    - Solution: Moved to top file (could be in separate package file)
//
// 2. ALU MODULE SYNTAX ERRORS:
//    - Line 105: Missing comma after "pre_res" parameter
//    - Line 113: "detault" should be "default"
//    - Line 60: Missing semicolon in ternary operator
//
// 3. SIGNAL WIDTH MISMATCH:
//    - ALU outputs res_q[17:0] but should handle 18 bits properly
//    - Carry handling seems correct
//
// 4. MISSING ACCUMULATOR FUNCTIONALITY:
//    - Project mentions accumulator register but not implemented
//    - ALU has result register but no accumulation mode
//
// 5. OPCODE CONFLICTS:
//    - Multiple operations assigned to 0x00 in decode module
//    - Need unique opcodes for: VADD2, VSUB2, DIFF2, DET2, DIST2, POLY, SCMULX
//
// 6. FLAGS NOT IMPLEMENTED:
//    - Project mentions 4 bits for flags (accumulate_en, QNotation_en, X_en, Y_en)
//    - Currently only using lower bits of opcode
//
// 7. OPERAND ROUTER ROUTING:
//    - Currently using upper 4 bits of opcode for routing
//    - May conflict with flag usage
//
// 8. TT I/O MAPPING:
//    - uio pins need to be properly mapped:
//      * uio[0] = spi_clk (input)
//      * uio[1] = spi_w (input)
//      * uio[2] = spi_r (input)
//      * uio[3] = res_carry (output)
//    - This needs bidirectional I/O configuration
//
// 9. TIMING CONSIDERATIONS:
//    - No explicit pipeline registers between stages
//    - All handshaking assumes single-cycle operations
//    - May need adjustment based on synthesis results
//
// 10. RESET SYNCHRONIZATION:
//     - All modules use async reset (negedge rst_n)
//     - Good for TinyTapeout global reset
//
// ==============================================================================
// RECOMMENDED FIXES:
// ==============================================================================
//
// 1. Fix ALU module syntax errors (lines 60, 105, 113)
// 2. Assign unique opcodes to all operations
// 3. Implement flag decoding (upper 4 bits of opcode)
// 4. Add accumulator functionality if needed
// 5. Create testbench to verify handshaking
// 6. Consider adding pipeline registers if timing fails
//
// ==============================================================================