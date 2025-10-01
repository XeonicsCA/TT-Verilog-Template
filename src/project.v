/*
 * Copyright (c) 2024 MZ
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_8_prog_counter (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // control loading/high-z using uio_in as inputs
  wire en = uio_in[0];
  wire load = uio_in[1];
  wire oe = uio[2];
  assign uio_oe = 8'h00;  // set uio to input

  // variable to hold counter val
  logic [7:0] count;

  // counter
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count <= 8'h00;           // reset to 0
    end else if (load) begin
      count <= uio_in;          // load in value on rising edge
    end else if (en) begin
      count <= count + 8'h01;   // increment count by 1 bit
  end

  // output
  assign uo_out = oe ? count : 1'bz;      // high-z output if oe not enabled

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, uio_in[7:3], 1'b0};     // concat and takes bitwise & (last bit set to 0, so always 0)

endmodule