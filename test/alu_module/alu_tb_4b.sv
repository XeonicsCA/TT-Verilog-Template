`timescale 1ns/1ps
`default_nettype none

// 4-bit ALU unit test wrapper
// - Drives alu_stage_4b
// - Fans out control fields for easy driving from Python and repacks into alu_ctrl_t


module alu_tb_4b;

    logic clk; // TB drives free-running clock (10 ns period)
    logic rst_n = 1'b1; // start deasserted, Python pulls it low

    logic [3:0] x0; // X lane operands (4-bit)
    logic [3:0] x1;
    logic [3:0] y0; // Y lane operands (4-bit)
    logic [3:0] y1;

    logic cmd_valid; // TB -> DUT: command is valid this cycle
    logic cmd_ready; // DUT -> TB: ALU ready to accept a command
    logic res_valid; // DUT -> TB: ALU result is valid this cycle
    logic res_ready; // TB -> DUT: consumer is ready for result

    // using "verilator public_flat_rw" for internal inputs probing
    // X lane
    logic pre_x_en /* verilator public_flat_rw */;
    logic pre_x_sub /* verilator public_flat_rw */;
    logic mul_x_en /* verilator public_flat_rw */;
    logic [2:0] mul_x_sel /* verilator public_flat_rw */;

    // Y lane
    logic pre_y_en /* verilator public_flat_rw */;
    logic pre_y_sub /* verilator public_flat_rw */;
    logic mul_y_en /* verilator public_flat_rw */;
    logic [2:0] mul_y_sel /* verilator public_flat_rw */;

    // Post
    logic post_en /* verilator public_flat_rw */;
    logic post_sub /* verilator public_flat_rw */;
    logic post_sel /* verilator public_flat_rw */;

    // Results
    logic [9:0] res_q;  // 10-bit result
    logic carry_q;  // 1-bit carry flag

    // Pack into struct expected by DUT (keep field order consistent with alu_pkg)
    alu_pkg::alu_ctrl_t ctrl;
    always_comb begin
        ctrl = '{ pre_x_en, pre_x_sub, mul_x_en, mul_x_sel,
                pre_y_en, pre_y_sub, mul_y_en, mul_y_sel,
                post_en,  post_sub,  post_sel };
    end

    // Flattened view for waves/debug (MSB..LSB follows the order above)
    logic [14:0] ctrl_flat;
    assign ctrl_flat = {
        pre_x_en, pre_x_sub, mul_x_en, mul_x_sel,
        pre_y_en, pre_y_sub, mul_y_en, mul_y_sel,
        post_en,  post_sub,  post_sel
    };

    // DUT
    alu_stage_4b u_alu (
        .clk       (clk),
        .rst_n     (rst_n),
        .x0        (x0),
        .x1        (x1),
        .y0        (y0),
        .y1        (y1),
        .ctrl      (ctrl),
        .cmd_valid (cmd_valid),
        .cmd_ready (cmd_ready),
        .res_valid (res_valid),
        .res_ready (res_ready),
        .res_q     (res_q),
        .carry_q   (carry_q)
    );

    // Free-running clock (10 ns period)
    // initial begin
    //     clk = 1'b0;
    //     forever #5 clk = ~clk;
    // end
    
    // Convenient VCD dump for waveform viewers
    `ifdef VCD_PATH
    initial begin
        $dumpfile(`VCD_PATH);
        $dumpvars(0, alu_tb_4b);
    end
    `endif
endmodule
