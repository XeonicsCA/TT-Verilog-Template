/*
 * Copyright (c) 2024 MZ
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_8_prog_counter (clk, rst_n, en, load, load_val, out_en, count, bus);
  parameter WIDTH = 8;

  input   clk, reset_n, en, load, output_en;
  input   [WIDTH-1:0] load_val;
  output  [WIDTH-1:0] count;
  inout   [WIDTH-1:0] bus;
  
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count <= '0;        // reset
    end else if (load) begin
      count <= load_val;      // load in value on rising edge
    end else if (en) begin
      count <= count + 1'b1;    // increment count by 1 bit
  end

  // tristate output driver
  assign bus = out_en ? count : 'z;

  // List all unused inputs to prevent warnings

end module