// adds two 8 bit values together, 9 bit output
// supports subtraction
module pre_add8 (
	input 	logic			en,
	input 	logic			sub,		// 0 to add, 1 to sub
	input 	logic [7:0]		in0, in1,	// 8 bit inputs
	output 	logic [8:0]		out9		// 9 bit output (going to multiplier)
);
	// concat in0 and in1 with 0 in MSB for 9 bit values
	logic [8:0] a, b;
	assign a = {1'b0, in0};
	assign b = {1'b0, in1};
	always_comb begin
		// if not enabled, pass through in0
		if (!en) begin
			out9 = a;
		end
		// if enabled, output add or sub
		else begin
			out9 = sub ? (a-b) : (a+b);
		end
	end
endmodule

// multiplies two 9 bit values together, 18 bit output
module mul9x9 (
	input 	logic			en,
	input 	logic [8:0]		m0, m1,		// 9 bit inputs
	output 	logic [17:0]	p 			// 18 bit outputs
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

// adds two 18 bit values together, 18 bit output with carry signal
// supports sub
module add18 (
	input 	logic			en,
	input 	logic			sub,	// 0 to add, 1 to sub
	input 	logic [17:0] 	a, b,
	output 	logic [17:0] 	res,
	output 	logic 			carry
);
	logic [18:0] tmp;
	always_comb begin
		// default values
		tmp = '0;
		res = '0;
		carry = 1'b0;
		
		// if not enabled, concat lower 9 bits of a and b
		if (!en) begin
			res = {a[8:0], b[8:0]};
			carry = 1'b0;				// set carry bit to 0
		end
		// if enabled, output add or sub
		else begin
			tmp = sub ? ({1'b0, a} - {1'b0, b}) : ({1'b0, a} + {1'b0, b});
			res = tmp[17:0];
			carry = tmp[18];
		end
	end
endmodule

module alu_stage (
	input	logic			clk, rst_n,
	input	logic [7:0]		x0, x1,		// inputs from operand router
	input	logic [7:0] 	y0, y1,
	input 	alu_ctrl_t 		ctrl, 		// control from decode

	// handshake logic with op decode/tx stage
	input	logic			cmd_valid,	// tx command in is valid
	output	logic			cmd_ready,	// alu is ready for command, 1 if not full
	output	logic			res_valid,	// alu result out is valid
	input	logic			res_ready,	// rx is ready for a result

	output	logic [17:0]	res_q,
	output	logic			carry_q
);
	// single-cycle, consumes when both sides ready
	// determine when to perform a new command
	logic fire = cmd_valid & cmd_ready;

	// preadders
	logic [8:0] x_pre, y_pre;
	pre_add8 u_px ( .en(ctrl.pre_x_en),
					.sub(ctrl.pre_x_sub),
					.in0(x0),
					.in1(x1),
					.out9(x_pre));
	pre_add8 u_py ( .en(ctrl.pre_y_en),
					.sub(ctrl.pre_y_sub),
					.in0(y0),
					.in1(y1),
					.out9(y_pre));

	// mul input select
	// takes in select, both inputs, and c from other lane
	// returns 9 bit value to be fed into m1
	function automatic logic [8:0] sel_mul_in (
		input logic [2:0] sel,
		input logic [8:0] in0, in1, pre_res,
		input logic [7:0] c_other
	);
		case (sel)
			3'd0 : sel_mul_in = in0;
			3'd1 : sel_mul_in = in1;
			3'd2 : sel_mul_in = pre_res;
			3'd3 : sel_mul_in = {1'b0, c_other};
			3'd4 : sel_mul_in = 9'b1;
			default : sel_mul_in = 9'd0;
		endcase
	endfunction

	logic [8:0] x_m0 = x_pre;
	logic [8:0] x_m1 = sel_mul_in(ctrl.mul_x_sel, {1'b0, x0}, {1'b0, x1}, x_pre, y1);
	logic [8:0] y_m0 = y_pre;
	logic [8:0] y_m1 = sel_mul_in(ctrl.mul_y_sel, {1'b0, y0}, {1'b0, y1}, y_pre, x1);

	// muls
	logic [17:0] x_prod, y_prod;
	mul9x9 u_mx (.en(ctrl.pre_x_en),
					.m0(x_m0),
					.m1(x_m1),
					.p(x_prod));
	mul9x9 u_my (.en(ctrl.pre_y_en),
					.m0(y_m0),
					.m1(y_m1),
					.p(y_prod));

	// post addercltr
	logic [17:0] res_d;
	logic carry_d;
	add18 u_post (.en(ctrl.post_en),
					.sub(ctrl.post_sub),
					.a(x_prod),
					.b(y_prod),
					.res(res_d),
					.carry(carry_d));

	// register result and ready/valid logic
	logic full;
	assign cmd_ready = ~full | (res_ready & res_valid); // ready for command if not full or completed previous operation successfully (rx ready to receive and result is valid)
	always_ff @(posedge clk or negedge rst_n) begin
		// reset
		if (!rst_n) begin
			full		<= 1'b0;
			res_q		<= '0;
			carry_q		<= 1'b0;
			res_valid 	<= 1'b0;
		end
		// normal behavior
		else begin
			// accepting new command, latch previous, set full, and set result valid
			if (fire) begin
				res_q 		<= res_d;
				carry_q 	<= carry_d;
				full 		<= 1'b1;
				res_valid 	<= 1'b1;
			end
			// result is valid and rx is ready, reset full and valid
			if (res_valid && res_ready) begin
				full 		<= 1'b0;
				res_valid 	<= 1'b0;
			end
		end
	end
endmodule