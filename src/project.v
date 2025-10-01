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
  // sync ui_in controls to clk
  logic [2:0] ctrl_q;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) ctrl_q <= '0;
    else ctrl_q <= ui_in[2:0];
  end

  wire en = ctrl_q[0];
  wire load = ctrl_q[1];
  wire oe = ctrl_q[2];

  // detect one cycle pulse of load
  logic load_q;
  wire load_pulse = load & ~load_q;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) load_q <= 1'b0;
    else load_q <= load;
  end

  // 3 state FSM sequence, 0=DRIVE, 1=RELEASE, 2=CAPTURE, then back to 0
  logic [1:0] seq;  // 0,1,2

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) seq <= 2'd0;
    else if (load_pulse) seq <= 2'd1;
    else if (seq != 2'd0) seq <= (seq == 2'd2) ? 2'd0 : seq + 2'd1; // if in seq 2, bring back to seq 0. otherwise increment 1 to 2
  end

  // counter
  logic [7:0] count;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) count <= 8'h00;            // reset counter
    else if (seq == 2'd2) count <= uio_in; // if in capture state, read in uio_in
    else if (en) count <= count + 8'h01;   // increment counter
  end

  // output
  assign uo_out = count;
  assign uio_out = count;
  // drive output only when in drive state and output is enabled
  wire driving = (seq == 2'd0) & oe;
  assign uio_oe = {8{driving}};

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, ui_in[7:3], 1'b0};     // concat and takes bitwise & (last bit set to 0, so always 0)

endmodule