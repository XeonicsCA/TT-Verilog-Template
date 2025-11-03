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

// takes in 8 bit op code from instruction and operands
// outputs alu_ctrl_t containing all alu stage control signals
// and routes operands to appropriate ALU lanes
module decode_stage (
	input	logic 		clk,           // System clock
	input	logic 		rst_n,         // Active low reset
	input	logic		rx_valid,      // Valid instruction from RX stage
	input	logic		cmd_ready,     // ALU ready to accept new instruction (from ALU)
	input	logic [7:0]	op,            // Opcode from RX stage
	input	logic [7:0]	a1,            // Operand a1 from RX stage
	input	logic [7:0]	a2,            // Operand a2 from RX stage
	input	logic [7:0]	b1,            // Operand b1 from RX stage
	input	logic [7:0]	b2,            // Operand b2 from RX stage
	
	output	logic		alu_ready,     // Pass cmd_ready back to RX stage
	output	logic		cmd_valid,     // Valid command to ALU (was decode_valid)
	output	alu_ctrl_t	ctrl,          // Control signals to ALU
	output	logic [7:0]	x0,            // X lane operand 0 to ALU
	output	logic [7:0]	x1,            // X lane operand 1 to ALU
	output	logic [7:0]	y0,            // Y lane operand 0 to ALU
	output	logic [7:0]	y1             // Y lane operand 1 to ALU
);
	
	// Operand Router - routes operands based on operation
	// Default routing: a1->x0, a2->x1, b1->y0, b2->y1
	always_comb begin
		// Default direct mapping
		x0 = a1;
		x1 = a2;
		y0 = b1;
		y1 = b2;
		
		// Operation-specific routing based on opcode
		// Using full opcode for now (can be modified for flags)
		case (op)
			// DET2: Need x0*y1 - y0*x1 instead of x0*x1 - y0*y1
			8'h0D: begin  
				x0 = a1;
				x1 = b2;  // Swap for determinant calculation
				y0 = b1;
				y1 = a2;  // Swap for determinant calculation
			end
			
			// SCALE2: x0*c, x1*c (both use same scalar)
			8'h0B: begin
				x0 = a1;
				x1 = a2;  // scalar c
				y0 = b1;  
				y1 = a2;  // same scalar c for both lanes
			end
			
			// Standard routing for all other operations
			default: begin
				x0 = a1;
				x1 = a2;
				y0 = b1;
				y1 = b2;
			end
		endcase
	end
	
	// Control signal generation based on opcode
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
			8'h05 : begin
				// enable pre add, mul by 1, disable post
				ctrl.pre_x_en 	= 1;
				ctrl.mul_x_en 	= 1;
				ctrl.mul_x_sel 	= 3'd4;

				ctrl.pre_y_en 	= 1;
				ctrl.mul_y_en 	= 1;
				ctrl.mul_y_sel 	= 3'd4;
			end

			// x0−y0 , x1−y1
			// VSUB2
			8'h06 : begin
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
			// DIFF2, DET2 (DET2 needs special routing)
			8'h07 : begin
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
			8'h08 : begin
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
			8'h09 : begin
				// x pre add y skip pre, skip mul, post add
				ctrl.pre_x_en = 1;
				ctrl.post_en = 1;
			end

			// x0x1 , y0y1
			// SCMUL - Scalar multiplication (both lanes)
			8'h0A : begin
				// skip pre, mul, post skip (concatenate results)
				ctrl.mul_x_en = 1;
				ctrl.mul_x_sel = 3'd1;

				ctrl.mul_y_en = 1;
				ctrl.mul_y_sel = 3'd1;
				
				// post_en = 0 means concatenate, not add
			end

			// x0c , x1c
			// SCALE2 - Scale a 2x1 vector by scalar c
			8'h0B : begin
				// Both X lane values multiplied by same scalar (needs routing)
				ctrl.mul_x_en = 1;
				ctrl.mul_x_sel = 3'd1;

				ctrl.mul_y_en = 1;
				ctrl.mul_y_sel = 3'd1;
			end

			// x0c + x1c
			// SCSUM - Scaled sum
			8'h0C : begin
				// Scale and sum
				ctrl.mul_x_en = 1;
				ctrl.mul_x_sel = 3'd1;

				ctrl.mul_y_en = 1;
				ctrl.mul_y_sel = 3'd1;

				ctrl.post_en = 1;
			end

			// x0y1 - y0x1  
			// DET2 - 2x2 determinant (needs special routing)
			8'h0D : begin
				// skip pre, multiply with swapped operands, post sub
				ctrl.mul_x_en = 1;
				ctrl.mul_x_sel = 3'd1;

				ctrl.mul_y_en = 1;
				ctrl.mul_y_sel = 3'd1;

				ctrl.post_en = 1;
				ctrl.post_sub = 1;
			end

			// x0 + c(y1−y0)
			// LERPX
			8'h0E : begin
				// x skip pre y pre sub, x mul by 1 y mul x_from_x1, post add
				ctrl.mul_x_en 	= 1;
				ctrl.mul_x_sel 	= 3'd4;

				ctrl.pre_y_en 	= 1;
				ctrl.pre_y_sub 	= 1;
				ctrl.mul_y_en	= 1;
				ctrl.mul_y_sel	= 3'd3;

				ctrl.post_en = 1;
			end

			// y0 + c(x0−x1)
			// LERPY
			8'h0F : begin
				// y skip pre x pre sub
				ctrl.pre_x_en	= 1;
				ctrl.pre_x_sub	= 1;
				ctrl.mul_x_en 	= 1;
				ctrl.mul_x_sel 	= 3'd3;

				ctrl.mul_y_en	= 1;
				ctrl.mul_y_sel	= 3'd4;

				ctrl.post_en = 1;
			end

			// noop
			default : begin
			end
		endcase
	end
	
	// Minimal handshaking logic
	// Pass through cmd_ready from ALU to RX stage
	assign alu_ready = cmd_ready;
	
	// Generate cmd_valid to ALU based on rx_valid and cmd_ready
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			cmd_valid <= 1'b0;
		end else begin
			// Pass through rx_valid when ALU is ready
			if (rx_valid && cmd_ready) begin
				cmd_valid <= 1'b1;
			end else if (cmd_valid && cmd_ready) begin
				// Clear valid after ALU accepts (when both valid and ready)
				cmd_valid <= 1'b0;
			end
		end
	end
	
endmodule