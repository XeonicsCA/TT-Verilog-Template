// ALU control structure definition
package alu_pkg;
    typedef struct packed {
        // X lane
        logic       pre_x_en;    // 0:x0, 1:add
        logic       pre_x_sub;   // 0:add, 1:sub
        logic       mul_x_en;    // 0:m0,m1, 1:mul
        logic [2:0] mul_x_sel;   // 0:x0, 1:x1, 2:square, 3:c_from_y1, 4:one (skip)

        // Y lane
        logic       pre_y_en;    // 0:y0, 1:add
        logic       pre_y_sub;   // 0:add, 1:sub
        logic       mul_y_en;    // 0:m0m1, 1:mul
        logic [2:0] mul_y_sel;   // 0:y0, 1:y1, 2:square, 3:c_from_x1, 4:one (skip)

        // Post adder
        logic       post_en;     // 0:concat, 1:add
        logic       post_sub;    // 0:add, 1:sub
        logic       post_sel;    // 0:b, 1:zero (skip)
    } alu_ctrl_t;
endpackage