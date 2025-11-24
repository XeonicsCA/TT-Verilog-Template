`default_nettype none
`timescale 1ns / 1ps

/* Top-level testbench for the TinyTapeout Math Accelerator Unit (MAU).
 * This just instantiates tt_um_mau_top and exposes the TinyTapeout IOs
 * for cocotb to drive.
 *
 * TOPLEVEL = mau_top_tb
 */

module mau_top_tb_4b ();
    // Wire up the inputs and outputs:
    reg        clk;
    reg        rst_n;
    reg        ena;
    reg  [7:0] ui_in;
    reg  [7:0] uio_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    `ifdef GL_TEST
    wire VPWR = 1'b1;
    wire VGND = 1'b0;
    `endif

    // TinyTapeout user module
    tt_um_mau_top_4b user_project (
        `ifdef GL_TEST
        .VPWR (VPWR),
        .VGND (VGND),
        `endif
        .ui_in  (ui_in),    // Dedicated inputs
        .uo_out (uo_out),   // Dedicated outputs
        .uio_in (uio_in),   // IOs: Input path
        .uio_out(uio_out),  // IOs: Output path
        .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
        .ena    (ena),      // enable - goes high when design is selected
        .clk    (clk),      // clock
        .rst_n  (rst_n)     // active-low reset
    );

    // Convenient VCD dump for waveform viewers
    `ifdef VCD_PATH
    initial begin
        $dumpfile(`VCD_PATH);
        $dumpvars(0, mau_top_tb_4b);
    end
    `endif

endmodule

`default_nettype wire
