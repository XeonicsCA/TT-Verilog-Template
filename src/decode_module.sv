// switched from definitions to localparams
// `define NOOP 0x00
// `define DOT2 0x01
// `define WSUM 0x02
// `define PROJU 0x03
// `define SUMSQ 0x04
// `define SCSUM 0x05
// `define VADD2 0x06
// `define VSUB2 0x07
// `define DIFF2 0x08
// `define DET2 0x09
// `define DIFFSQ 0x0A
// `define DIST2 0x0B
// `define POLY 0x0C
// `define SCMUL 0x0D
// `define LERPX 0x0E
// `define LERPY 0x0F

// moved to mua_top.sv
// struct containing all decode stage signals
// typedef struct packed {
// 	// X lane
// 	logic		pre_x_en;	// 0:x0, 1:add
// 	logic		pre_x_sub;	// 0:add, 1:sub
// 	logic		mul_x_en;	// 0:m0,m1, 1:mul
// 	logic [2:0] mul_x_sel;	// 0:x0, 1:x1, 2:square, 3:c_from_y1, 4:one (skip)

// 	// Y lane
// 	logic 		pre_y_en;	// 0:y0, 1:add
// 	logic 		pre_y_sub;	// 0:add, 1:sub
// 	logic		mul_y_en;	// 0:m0m1, 1:mul
// 	logic [2:0] mul_y_sel;	// 0:y0, 1:y1, 2:square, 3:c_from_x1, 4:one (skip)

// 	// Post adder
// 	logic		post_en;		// 0:concat, 1:add
// 	logic		post_sub;		// 0:add, 1:sub
// 	logic		post_sel;		// 0:b, 1:zero (skip)
// } alu_ctrl_t;

// takes in 8 bit op code from instruction and operands
// outputs alu_ctrl_t containing all alu stage control signals
// and routes operands to appropriate ALU lanes
module decode_stage (
	input	logic 		clk,           // System clock
	input	logic 		rst_n,         // Active low reset
	input	logic		rx_valid_in,      // Valid instruction from RX stage
	input	logic		cmd_ready_in,     // ALU ready to accept new instruction (from ALU)
	input	logic [7:0]	op,            // Opcode from RX stage
	input	logic [7:0]	a1,            // Operand a1 from RX stage
	input	logic [7:0]	a2,            // Operand a2 from RX stage
	input	logic [7:0]	b1,            // Operand b1 from RX stage
	input	logic [7:0]	b2,            // Operand b2 from RX stage
	
	output	logic		alu_ready_out,     // Pass cmd_ready_in back to RX stage
	output	logic		cmd_valid_out,     // Valid command to ALU (was decode_valid)
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
		
        // not using operation specific routing, will use hard coded operand positions instead
		// // Operation-specific routing based on opcode
		// // Using full opcode for now (can be modified for flags)
		// case (op)
		// 	// DET2: Need x0*y1 - y0*x1 instead of x0*x1 - y0*y1
		// 	`DET2 : begin  
		// 		x0 = a1;
		// 		x1 = b2;  // Swap for determinant calculation
		// 		y0 = b1;
		// 		y1 = a2;  // Swap for determinant calculation
		// 	end
	
		// 	// Standard routing for all other operations
		// 	default : begin
		// 		x0 = a1;
		// 		x1 = a2;
		// 		y0 = b1;
		// 		y1 = b2;
		// 	end
		// endcase
	end

    localparam logic [7:0] NOOP = 8'h00;
    localparam logic [7:0] DOT2 = 8'h01;
    localparam logic [7:0] WSUM = 8'h02;
    localparam logic [7:0] PROJU = 8'h03;
    localparam logic [7:0] SUMSQ = 8'h04;
    localparam logic [7:0] SCSUM = 8'h05;
    localparam logic [7:0] VADD2 = 8'h06;
    localparam logic [7:0] VSUB2 = 8'h07;
    localparam logic [7:0] DIFF2 = 8'h08;
    localparam logic [7:0] DET2 = 8'h09;
    localparam logic [7:0] DIFFSQ = 8'h0A;
    localparam logic [7:0] DIST2 = 8'h0B;
    localparam logic [7:0] POLY = 8'h0C;
    localparam logic [7:0] SCMUL = 8'h0D;
    localparam logic [7:0] LERPX = 8'h0E;
    localparam logic [7:0] LERPY = 8'h0F;
	
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
			DOT2, WSUM, PROJU, SUMSQ, SCSUM : begin
				// skip pre, mul, post add
				ctrl.mul_x_en = 1;
				ctrl.mul_x_sel = 3'd1; // mul by x1

				ctrl.mul_y_en = 1;
				ctrl.mul_y_sel = 3'd1; // mul by y1

				ctrl.post_en = 1;
			end

			// x0+x1 , y0+y1
			// VADD2
			VADD2 : begin
				// enable pre add, mul by 1, disable post
				ctrl.pre_x_en 	= 1;
				ctrl.mul_x_en 	= 1;
				ctrl.mul_x_sel 	= 3'd4; // mul by one

				ctrl.pre_y_en 	= 1;
				ctrl.mul_y_en 	= 1;
				ctrl.mul_y_sel 	= 3'd4; // mul by one
			end

			// x0−y0 , x1−y1
			// VSUB2
			VSUB2 : begin
				// enable pre sub, mul by 1, disable post
				ctrl.pre_x_en 	= 1;
				ctrl.pre_x_sub 	= 1; // sub
				ctrl.mul_x_en 	= 1;
				ctrl.mul_x_sel 	= 3'd4; // mul by 1

				ctrl.pre_y_en 	= 1;
				ctrl.pre_y_sub 	= 1; // sub
				ctrl.mul_y_en 	= 1;
				ctrl.mul_y_sel 	= 3'd4; // mul by 1
			end

			// x0x1 - y0y1
			// DIFF2, DET2 (special routing), DIFFSQ
			DIFF2, DET2, DIFFSQ : begin
				// skip pre, multiply, post sub
				ctrl.mul_x_en = 1;
				ctrl.mul_x_sel = 3'd1; // mul by x1

				ctrl.mul_y_en = 1;
				ctrl.mul_y_sel = 3'd1; // mul by y1

				ctrl.post_en = 1;
				ctrl.post_sub = 1;	// sub
			end

			// (x0−x1)² − (y0−y1)²
			// DIST2
			DIST2 : begin
				// pre sub, square, post sub
				ctrl.pre_x_en = 1;
				ctrl.pre_x_sub = 1; // sub
				ctrl.mul_x_en = 1;
				ctrl.mul_x_sel = 3'd2;	// square

				ctrl.pre_y_en = 1;
				ctrl.pre_y_sub = 1; // sub
				ctrl.mul_y_en = 1;
				ctrl.mul_y_sel = 3'd2; // square

				ctrl.post_en = 1;
				ctrl.post_sub = 1; // sub
			end

			// ax + b
			// POLY
			POLY : begin
				// x pre add y skip pre, skip mul, post add
				ctrl.pre_x_en = 1;
				ctrl.post_en = 1;
			end

			// x0x1 , y0y1
			// SCMUL - scalar multiplication, concat cuts result for both lanes to 9 bits
			SCMUL : begin
				// skip pre, mul, post skip (concatenate results)
				ctrl.mul_x_en = 1;
				ctrl.mul_x_sel = 3'd1; // mul by x1

				ctrl.mul_y_en = 1;
				ctrl.mul_y_sel = 3'd1; // mul by y1
			end

			// x0 + c(y1−y0)
			// LERPX
			LERPX : begin
				// x skip pre y pre sub, x mul by 1 y mul x_from_x1, post add
				ctrl.mul_x_en 	= 1;
				ctrl.mul_x_sel 	= 3'd4;	// mul by 1

				ctrl.pre_y_en 	= 1;
				ctrl.pre_y_sub 	= 1;
				ctrl.mul_y_en	= 1;
				ctrl.mul_y_sel	= 3'd3;	// mul by c (x1)

				ctrl.post_en = 1;
			end

			// y0 + c(x0−x1)
			// LERPY
			LERPY : begin
				// y skip pre x pre sub
				ctrl.pre_x_en	= 1;
				ctrl.pre_x_sub	= 1;
				ctrl.mul_x_en 	= 1;
				ctrl.mul_x_sel 	= 3'd3;	// mul by c (y1)

				ctrl.mul_y_en	= 1;
				ctrl.mul_y_sel	= 3'd4;	// mul by 1

				ctrl.post_en = 1;
			end

			// noop
			default : begin
			end
		endcase
	end
	
	// Minimal handshaking logic
	// Pass through cmd_ready_in from ALU to RX stage
	assign alu_ready_out = cmd_ready_in;
	
	// Generate cmd_valid_out to ALU based on rx_valid_in and cmd_ready_in
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			cmd_valid_out <= 1'b0;
		end else begin
			// Pass through rx_valid_in when ALU is ready
			if (rx_valid_in && cmd_ready_in) begin
				cmd_valid_out <= 1'b1;
			end
			else if (cmd_valid_out && cmd_ready_in) begin
				// Clear valid after ALU accepts (when both valid and ready)
				cmd_valid_out <= 1'b0;
			end
		end
	end
	
endmodule