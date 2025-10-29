// struct containing all decode stage signals
typedef struct packed {
	// X lane
	logic		pre_x_en;	// 0:x0, 1:add
	logic		pre_x_sub;	// 0:add, 1:sub
	logic		mul_x_en;	// 0:m0,m1, 1:mul
	logic [2:0] mul_x_sel;	// 0:x0, 1:x1, 2:square, 3:c_from_y1, 4:one (skip)

	// Y lane
	logic 		pre_y_en;	// 0:y0, 1:add
	logic 		pre_y_sub;	// 0:add, 1:sub
	logic		mul_y_en;	// 0:m0m1, 1:mul
	logic [2:0] mul_y_sel;	// 0:y0, 1:y1, 2:square, 3:c_from_x1, 4:one (skip)

	// Post adder
	logic		post_en;		// 0:concat, 1:add
	logic		post_sub;		// 0:add, 1:sub
	logic		post_sel;		// 0:b, 1:zero (skip)
} alu_ctrl_t;

// takes in 8 bit op code from instruction
// outputs alu_ctrl_t containing all alu stage control signals
module decode_stage (
	input	logic [7:0]	op,
	output	alu_ctrl_t	ctrl
);
	always_comb begin
		// default signals
		// skip pre add, concat x0,x1 and y0,y1, post concat x,y lanes
		ctrl = '0;
		ctrl.mul_x_sel = 3'd1;
		ctrl.mul_y_sel = 3'd1;

		// check op code
		unique case (op)

			// x0x1 + y0y1
			// DOT2, WSUM, PROJU, SUMSQ, SCSUM
			8'h01, 8'h02, 8'h03, 8'h04 : begin
				// skip pre, mul, post add
				ctrl.mul_x_en = 1;
				ctrl.mul_x_sel = 3'd1;

				ctrl.mul_y_en = 1;
				ctrl.mul_y_sel = 3'd1;

				ctrl.post_en = 1;
			end

			// x0+x1 , y0+y1
			// VADD2
			8'h00 : begin
				// enable pre add, mul by 1, disable post
				ctrl.pre_x_en 	= 1;
				ctrl.mul_x_en 	= 1;
				ctrl.mul_x_sel 	= 3'd4;

				ctrl.pre_y_en 	= 1;
				ctrl.mul_y_en 	= 1;
				ctrl.mul_y_sel 	= 3'd4;
			end

			// x0−y0 , x1−y1
			// VSUB2, 
			8'h00 : begin
				// enable pre sub, mul by 1, disable post
				ctrl.pre_x_en 	= 1;
				ctrl.pre_x_sub 	= 1;
				ctrl.mul_x_en 	= 1;
				ctrl.mul_x_sel 	= 3'd4;

				ctrl.pre_y_en 	= 1;
				ctrl.pre_y_sub 	= 1;
				ctrl.mul_y_en 	= 1;
				ctrl.mul_y_sel 	= 3'd4;
			end

			// x0x1 - y0y1
			// DIFF2, DET2, DIFFSQ
			8'h00 : begin
				// skip pre, multiply, post sub
				ctrl.mul_x_en = 1;
				ctrl.mul_x_sel = 3'd1;

				ctrl.mul_y_en = 1;
				ctrl.mul_y_sel = 3'd1;

				ctrl.post_en = 1;
				ctrl.post_sub = 1;
			end

			// (x0−x1)² − (y0−y1)²
			// DIST2
			8'h00 : begin
				// pre sub, square, post sub
				ctrl.pre_x_en = 1;
				ctrl.pre_x_sub = 1;
				ctrl.mul_x_en = 1;
				ctrl.mul_x_sel = 3'd2;

				ctrl.pre_y_en = 1;
				ctrl.pre_y_sub = 1;
				ctrl.mul_y_en = 1;
				ctrl.mul_y_sel = 3'd2;

				ctrl.post_en = 1;
				ctrl.post_sub = 1;
			end

			// ax + b
			// POLY
			8'h00 : begin
				// x pre add y skip pre, skip mul, post add
				ctrl.pre_x_en = 1;
				ctrl.post_en = 1;
			end

			// x0x1
			// SCMULX
			8'h00 : begin
				// only X lane
				// skip pre, mul, post add 0
				ctrl.mul_x_en = 1;
				ctrl.mul_x_sel = 3'd1;

				ctrl.post_en = 1;
				ctrl.post_sel = 1;
			end

			// x0x1
			// SCMULY
			8'h10 : begin
				// wont work since post_sel = 1 will set Y lane to equal 0
				// only Y lane
				// skip pre, mul, post add 0
				ctrl.mul_y_en = 1;
				ctrl.mul_y_sel = 3'd1;

				ctrl.post_en = 1;
				ctrl.post_sel = 1;
			end

			// x0 + c(y1−y0)
			// LERPX
			8'h0E : begin
				// x skip pre y pre sub, x mul by 1 y mul x_from_x1, post add
				mul_x_en 	= 1;
				mul_x_sel 	= 3'd4;

				pre_y_en 	= 1;
				pre_y_sub 	= 1;
				mul_y_en	= 1;
				mul_y_sel	= 3'd3;

				post_en = 1;
			end

			// y0 + c(x0−x1)
			// LERPY
			8'h0F : begin
				// y skip pre x pre sub
				pre_x_en	= 1;
				pre_x_sub	= 1;
				mul_x_en 	= 1;
				mul_x_sel 	= 3'd3;

				mul_y_en	= 1;
				mul_y_sel	= 3'd4;

				post_en = 1;
			end

			// noop
			default : begin
			end
		endcase
	end
endmodule