// ALU Stage Module
// Contains submodules for pre-adder, multiplier, and post adder
// alu_stage_4b passes operands and control signals into each module creating the final 10-bit result
// result is registered until handshake with tx-stage signals its been outputted

`timescale 1ns/1ps
`default_nettype none

// adds two 4 bit values together, 5 bit output
// supports subtraction
module pre_add4 (
	input 	logic			en,
	input 	logic			sub,		// 0 to add, 1 to sub
	input 	logic [3:0]		in0, in1,	// 4 bit inputs
	output 	logic [4:0]		out5		// 5 bit output (going to multiplier)
);
	// concat in0 and in1 with 0 in MSB for 5 bit inputs
	logic [4:0] a, b;
	assign a = {1'b0, in0};
	assign b = {1'b0, in1};
	always_comb begin
		// if not enabled, pass through in0
		if (!en) begin
			out5 = a;
		end
		// if enabled, output add or sub
		else begin
			out5 = sub ? (a-b) : (a+b);
		end
	end
endmodule

// multiplies two 5 bit values together, 10 bit output
module mul5x5 (
	input 	logic			en,
	input 	logic [4:0]		m0, m1,		// 5 bit inputs
	output 	logic [9:0]	p 			// 10 bit outputs
);
	always_comb begin
		// if not enabled, pass through concat m0 and m1
		if (!en) begin
			p = {m0, m1};
		end
		// if enabled, output multiplication
		else begin
			p = m0 * m1;
		end
	end
endmodule

// adds two 10 bit values together, 10 bit output with carry signal
// supports sub
module add10 (
	input 	logic			en,
	input 	logic			sub,	// 0 to add, 1 to sub
	input 	logic [9:0] 	a, b,
	output 	logic [9:0] 	res,
	output 	logic 			carry
);
	logic [10:0] tmp;
	logic [4:0] a_5;
	logic [4:0] b_5;
	logic [10:0] a_11;
	logic [10:0] b_11;

	always_comb begin
		// default values
		tmp = '0;
		res = '0;
		carry = 1'b0;
		a_5 = '0;
		b_5 = '0;
		a_11 = '0;
		b_11 = '0;
		
		// if not enabled, concat lower 5 bits of a and b
		if (!en) begin
			a_5 = a[4:0];
			b_5 = b[4:0];
			res = {a_5, b_5};
			carry = 1'b0;				// set carry bit to 0
		end
		// if enabled, output add or sub
		else begin
			a_11 = {1'b0, a};
			b_11 = {1'b0, b};
			tmp = sub ? (a_11 - b_11) : (a_11 + b_11);
			res = tmp[9:0];
			carry = tmp[10];
		end
	end
endmodule

// ALU module that takes in 4 operands
// passes to required sub modules based on control signaling
// and registers 10-bit result (holds until handshake complete)
module alu_stage_4b (
	input	logic			clk, rst_n,
	input	logic [3:0]		x0, x1,		// inputs from operand router
	input	logic [3:0] 	y0, y1,
	input 	alu_pkg::alu_ctrl_t 		ctrl, 		// control from decode

	// handshake logic with op decode/tx stage
	input	logic			cmd_valid,	// rx command in is valid
	output	logic			cmd_ready,	// alu is ready for command, 1 if not full
	output	logic			res_valid,	// alu result out is valid
	input	logic			res_ready,	// tx is ready for a result

	output	logic [9:0]		res_q,
	output	logic			carry_q
);
	// single-cycle, consumes when both sides ready
	// determine when to perform a new command
	logic fire;
	assign fire = cmd_valid && cmd_ready;

	// preadders
	logic [4:0] x_pre, y_pre;
	pre_add4 u_px ( .en(ctrl.pre_x_en),
					.sub(ctrl.pre_x_sub),
					.in0(x0),
					.in1(x1),
					.out5(x_pre));
	pre_add4 u_py ( .en(ctrl.pre_y_en),
					.sub(ctrl.pre_y_sub),
					.in0(y0),
					.in1(y1),
					.out5(y_pre));

	// mul input select
	// takes in select, both inputs, and c from other lane
	// returns 5 bit value to be fed into m1
	function automatic logic [4:0] sel_mul_in (
		input logic [2:0] sel,
		input logic [4:0] in0, in1, pre_res,
		input logic [3:0] c_other
	);
		case (sel)
			3'd0 : sel_mul_in = in0;
			3'd1 : sel_mul_in = in1;
			3'd2 : sel_mul_in = pre_res;
			3'd3 : sel_mul_in = {1'b0, c_other};
			3'd4 : sel_mul_in = 5'b1;
			default : sel_mul_in = 5'd0;
		endcase
	endfunction

	logic [4:0] x_m0, x_m1, y_m0, y_m1;

	assign x_m0 = x_pre;
	assign x_m1 = sel_mul_in(ctrl.mul_x_sel, {1'b0, x0}, {1'b0, x1}, x_pre, y1);
	assign y_m0 = y_pre;
	assign y_m1 = sel_mul_in(ctrl.mul_y_sel, {1'b0, y0}, {1'b0, y1}, y_pre, x1);

	// muls
	logic [9:0] x_prod, y_prod;
	mul5x5 u_mx (.en(ctrl.mul_x_en),
					.m0(x_m0),
					.m1(x_m1),
					.p(x_prod));
	mul5x5 u_my (.en(ctrl.mul_y_en),
					.m0(y_m0),
					.m1(y_m1),
					.p(y_prod));

	// post adder ctrl
	logic [9:0] res_d;
	logic carry_d;
	add10 u_post (.en(ctrl.post_en),
					.sub(ctrl.post_sub),
					.a(x_prod),
					.b(y_prod),
					.res(res_d),
					.carry(carry_d));

	// internal registered valid flag
	logic res_valid_q;

	// Handshake: stage is ready when it is not holding a result,
	// or when the result will be consumed this cycle.
	assign cmd_ready = ~res_valid_q || res_ready;

	// Drive port from internal flop
	assign res_valid = res_valid_q;

	// Handshake condition for consumption
	logic consume /* verilator public_flat_rw */;
	assign consume = res_valid_q && res_ready;

	// Result / carry registers and valid flop
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			res_q       <= '0;
			carry_q     <= 1'b0;
			res_valid_q <= 1'b0;
		end else begin
			// Handle both producing and consuming
			if (fire) begin
				// Producing a new result (possibly also consuming old one)
				res_q       <= res_d;
				carry_q     <= carry_d;
				res_valid_q <= 1'b1;
			end else if (consume) begin
				// Only consuming (no new result)
				res_valid_q <= 1'b0;
			end
			// else: hold state
		end
	end

	// --------------------------------------------------------------------
	// Debug: mirror internal valid for cocotb visibility
	// --------------------------------------------------------------------
	logic dbg_res_valid /* verilator public_flat_rw */;

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			dbg_res_valid <= 1'b0;
		end else begin
			dbg_res_valid <= res_valid_q;
		end
	end

endmodule