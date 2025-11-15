`default_nettype none
`timescale 1ns/1ps

// 4-BIT VERSION OF DECODE_TB

// Standalone unit-test wrapper for the decode_stage module.
// Exposes simple pins that cocotb (test_decode.py) can drive & observe.
// Uses the packed struct type from alu_pkg for the control bus, and also
// provides a flattened view (ctrl_flat) for easy access from cocotb.

// EXTRA_ARGS="--timing" make SIM=verilator test-decode

module decode_tb_4b;

    // Clock / reset
    logic clk;
    logic rst_n;

    // Handshake + instruction inputs
    logic        rx_valid_in;
    logic        cmd_ready_in;
    logic [3:0]  op;
    logic [3:0]  a1, a2, b1, b2;

    // Outputs to ALU / RX
    logic        alu_ready_out;
    logic        cmd_valid_out;

    // Import ALU control struct and expose both typed and flat versions
    alu_pkg::alu_ctrl_t ctrl;
    logic [($bits(alu_pkg::alu_ctrl_t))-1:0] ctrl_flat;
    assign ctrl_flat = ctrl;

    // Routed operands to ALU (from decode)
    logic [3:0] x0, x1, y0, y1;

    // DUT: the actual decode module under test
    decode_stage_4b u_decode (
        .clk          (clk),
        .rst_n        (rst_n),
        .rx_valid_in  (rx_valid_in),
        .cmd_ready_in (cmd_ready_in),
        .op           (op),
        .a1           (a1),
        .a2           (a2),
        .b1           (b1),
        .b2           (b2),
        .alu_ready_out(alu_ready_out),
        .cmd_valid_out(cmd_valid_out),
        .ctrl         (ctrl),
        .x0           (x0),
        .x1           (x1),
        .y0           (y0),
        .y1           (y1)
    );

    // Simple clock for interactive waveform debugging (cocotb also drives clk)
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // 100 MHz if not overridden by cocotb
    end

    // Convenient VCD dump for waveform viewers
    `ifdef VCD_PATH
    initial begin
        $dumpfile(`VCD_PATH);
        $dumpvars(0, decode_tb_4b);
    end
    `endif

endmodule
