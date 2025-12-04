# End-to-end tests for the 4 bit Math Accelerator Unit via tt_um_mau_top
#
# These tests mirror the style of the individual module tests:
#   - Same CLK_NS, reset style, and SPI helpers as test_rx_4b.py / test_tx_4b.py
#   - Drive the MAU purely through the TinyTapeout IOs:
#       * ui_in[3:0] : MOSI (instruction/operand nibbles)
#       * uio_in[0]  : spi_clk (shared by RX and TX)
#       * uio_in[1]  : spi_w   (write-enable for RX)
#       * uio_in[2]  : spi_r   (read-enable for TX)
#       * uo_out[3:0]: MISO (serialized result nibbles from TX)
#       * uio_out[3] : carry_out from TX
#
# Instruction format (from rx_4b):
#   [op(4b)][a1(4b)][a2(4b)][b1(4b)][b2(4b)]
#
# Opcode mapping (from decode_module_4b.sv):
#   NOOP  = 0x0
#   DOT2  = 0x1 : x0*x1 + y0*y1  (with x0=a1, x1=a2, y0=b1, y1=b2)
#   WSUM  = 0x2
#   PROJU = 0x3
#   SUMSQ = 0x4
#   SCSUM = 0x5
#   VADD2 = 0x6 : { (a1+a2)[4:0], (b1+b2)[4:0] }
#   VSUB2 = 0x7 : { (a1-a2)[4:0], (b1-b2)[4:0] }
#   DIFF2 = 0x8
#   DET2  = 0x9
#   DIFFSQ= 0xA
#   DIST2 = 0xB
#   POLY  = 0xC
#   SCMUL = 0xD
#   LERPX = 0xE
#   LERPY = 0xF
#
# TX result packing (from tx_4b tests / add10):
#   res : 10 bit result, carry : 1 bit
#
#   Nibble0 = res[3:0]
#   Nibble1 = res[7:4]
#   Nibble2 = {res[9:8], carry, 1'b0}
#   Nibble3 = 0
#   Nibble4 = 0
#

import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, ReadOnly

CLK_NS = 10           #100MHz system clock
SPI_CLK_CYCLES = 5    #Number of system clocks per SPI clock edge

#Opcodes (mirrors decode_module_4b.sv localparams)
NOOP  = 0x0
DOT2  = 0x1
WSUM  = 0x2
PROJU = 0x3
SUMSQ = 0x4
SCSUM = 0x5
VADD2 = 0x6
VSUB2 = 0x7
DIFF2 = 0x8
DET2  = 0x9
DIFFSQ= 0xA
DIST2 = 0xB
POLY  = 0xC
SCMUL = 0xD
LERPX = 0xE
LERPY = 0xF


# ---------------------------------------------------------------------------
# Helpers (reset, SPI write/read)
# ---------------------------------------------------------------------------

async def reset(dut):
    #Reset the MAU top-level and initialise all IOs to safe values
    dut.rst_n.value = 0
    dut.ena.value   = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    await ClockCycles(dut.clk, 2)

    dut.rst_n.value = 1
    dut.ena.value   = 1

    await ClockCycles(dut.clk, 1)


def alu_model_for_mau(op, a1, a2, b1, b2):
    #Calculates the MAU output using direct formulas.
    #Takes 4 bit nibbles a1,a2,b1,b2 and a 4 bit opcode, returns:
    #       res  : 10 bit result (int 0..1023)
    #       carry: 1 bit carry (0 or 1)
    
    op &= 0xF
    a1 &= 0xF
    a2 &= 0xF
    b1 &= 0xF
    b2 &= 0xF

    # ----- NOOP (default path) ------------------------------------------
    # Default datapath packs lane-1 values into {high5, low5}:
    #   res[9:5] = a2
    #   res[4:0] = b2
    # carry = 0
    if op == NOOP:
        res = ((a2 & 0x1F) << 5) | (b2 & 0x1F)
        return res & 0x3FF, 0

    # Helper: 10 bit add/sub with 11 bit intermediate (for ops that use
    # the post adder). This mirrors the add10 behaviour.
    def add10_like(x, y, sub=False):
        x &= 0x3FF
        y &= 0x3FF
        if sub:
            tmp = (x - y) & 0x7FF  # 11 bit wrap
        else:
            tmp = (x + y) & 0x7FF
        res = tmp & 0x3FF
        carry = (tmp >> 10) & 0x1
        return res, carry

    # ----- DOT2-style ops: x0*x1 + y0*y1 -------------------------------
    # DOT2, WSUM, PROJU, SUMSQ, SCSUM currently all share the same
    # math: x0*x1 + y0*y1, with 10 bit result and a carry bit.
    if op in (DOT2, WSUM, PROJU, SUMSQ, SCSUM):
        x_prod = (a1 * a2) & 0x3FF
        y_prod = (b1 * b2) & 0x3FF
        return add10_like(x_prod, y_prod, sub=False)

    # ----- VADD2: lane-wise add and pack -------------------------------
    # x lane: a1 + a2 (5 bit)
    # y lane: b1 + b2 (5 bit)
    # res[9:5] = x_sum[4:0], res[4:0] = y_sum[4:0], carry = 0
    if op == VADD2:
        x_sum = (a1 + a2) & 0x1F
        y_sum = (b1 + b2) & 0x1F
        res = ((x_sum << 5) | y_sum) & 0x3FF
        return res, 0

    # ----- VSUB2: lane-wise subtract and pack --------------------------
    # x lane: a1 - a2 (5 bit wrap)
    # y lane: b1 - b2 (5 bit wrap)
    # res[9:5] = x_diff, res[4:0] = y_diff, carry = 0
    if op == VSUB2:
        x_diff = (a1 - a2) & 0x1F
        y_diff = (b1 - b2) & 0x1F
        res = ((x_diff << 5) | y_diff) & 0x3FF
        return res, 0

    # ----- DIFF2 / DET2 / DIFFSQ: x0x1 - y0y1 --------------------------
    # With current operand routing, all three behave as:
    #   res,carry = a1*a2 - b1*b2  (10 bit diff with carry)
    if op in (DIFF2, DET2, DIFFSQ):
        x_prod = (a1 * a2) & 0x3FF
        y_prod = (b1 * b2) & 0x3FF
        return add10_like(x_prod, y_prod, sub=True)

    # ----- DIST2: (x0−x1)^2 − (y0−y1)^2 -------------------------------
    # dx = a1 - a2 (5 bit), dy = b1 - b2 (5 bit)
    # res,carry = dx^2 - dy^2 (10 bit with carry)
    if op == DIST2:
        dx = (a1 - a2) & 0x1F
        dy = (b1 - b2) & 0x1F
        sx = (dx * dx) & 0x3FF
        sy = (dy * dy) & 0x3FF
        return add10_like(sx, sy, sub=True)

    # ----- POLY: "ax + b" style packed add -----------------------------
    # Current RTL behaviour (with default routing x0=a1,x1=a2,y0=b1,y1=b2):
    #   sx     = (a1 + a2)  (5 bit)
    #   x_prod = { sx[4:0], a2 }
    #   y_prod = { b1[4:0], b2 }
    #   res,carry = x_prod + y_prod
    if op == POLY:
        sx = (a1 + a2) & 0x1F
        x_prod = ((sx << 5) | (a2 & 0x1F)) & 0x3FF
        y_prod = (((b1 & 0x1F) << 5) | (b2 & 0x1F)) & 0x3FF
        return add10_like(x_prod, y_prod, sub=False)

    # ----- SCMUL: scalar multiply, packed lanes ------------------------
    # x lane: (a1*a2)[4:0]
    # y lane: (b1*b2)[4:0]
    # res[9:5]=x_low5, res[4:0]=y_low5, carry = 0
    if op == SCMUL:
        x_low = (a1 * a2) & 0x1F
        y_low = (b1 * b2) & 0x1F
        res = ((x_low << 5) | y_low) & 0x3FF
        return res, 0

    # ----- LERPX: x0 + c*(y0−y1), with c = a2 --------------------------
    # From current control:
    #   dy   = (b1 - b2) (5 bit)
    #   prod = a2 * dy
    #   res,carry = a1 + prod
    if op == LERPX:
        dy = (b1 - b2) & 0x1F
        prod = (a2 * dy) & 0x3FF
        return add10_like(a1, prod, sub=False)

    # ----- LERPY: y0 + c*(x0−x1), with c = b2 --------------------------
    # From current control:
    #   dx   = (a1 - a2) (5 bit)
    #   prod = b2 * dx
    #   res,carry = b1 + prod
    if op == LERPY:
        dx = (a1 - a2) & 0x1F
        prod = (b2 * dx) & 0x3FF
        return add10_like(b1, prod, sub=False)

    # Fallback
    return 0, 0


async def spi_write_nibble(dut, nibble):
    #Write one 4 bit nibble via RX SPI using ui_in[3:0] and uio_in[0]/[1]
    #Mirrors test_rx_4b.py SPI write behavior
    
    nibble &= 0xF

    #Drive MOSI on lower 4 bits of ui_in (upper bits unused)
    dut.ui_in.value = nibble

    #SPI clock low phase
    dut.uio_in[0].value = 0  #spi_clk
    await ClockCycles(dut.clk, SPI_CLK_CYCLES)

    #SPI clock high phase: RX samples MOSI here
    dut.uio_in[0].value = 1
    await ClockCycles(dut.clk, SPI_CLK_CYCLES)

    #SPI clock low phase (end on low)
    dut.uio_in[0].value = 0
    #await ClockCycles(dut.clk, 1)


async def spi_send_instruction(dut, op, a1, a2, b1, b2):
    #Send a full 20 bit RX instruction: [op, a1, a2, b1, b2].
    #Sequentially writes 5 nibbles with SPI write enabled.

    #Ensure read-enable is low while writing
    dut.uio_in[2].value = 0  #spi_r = 0

    #Assert write-enable
    dut.uio_in[1].value = 1  #spi_w = 1

    #Write all 5 nibbles sequentially
    for nib in [op, a1, a2, b1, b2]:
        await spi_write_nibble(dut, nib)

    #Deassert write-enable and ensure clock is low
    dut.uio_in[1].value = 0
    dut.uio_in[0].value = 0  # spi_clk = 0


async def spi_read_nibble(dut):
    #Read one 4 bit nibble via TX SPI using uio_in[0]/[2] and uo_out[3:0].
    #Mirrors spi_read_nibble helper in test_tx_4b.py.
    
    #SPI clock low phase
    dut.uio_in[0].value = 0
    await ClockCycles(dut.clk, SPI_CLK_CYCLES)

    #SPI clock high phase: TX drives MISO (uo_out[3:0])
    dut.uio_in[0].value = 1

    #Sample MISO value in read-only phase
    await ReadOnly()
    miso_val = int(dut.uo_out.value) & 0xF

    await ClockCycles(dut.clk, SPI_CLK_CYCLES)

    #End on low so TX sees a falling edge (increments counter)
    dut.uio_in[0].value = 0
    #await ClockCycles(dut.clk, 1)

    return miso_val


async def spi_read_result(dut):
    #Read 5 nibbles from TX and decode (res, carry).
    #Returns the full 10 bit result and carry bit.
    
    #Enable read
    dut.uio_in[2].value = 1  # spi_r = 1

    #Give TX a couple cycles to assert tx_active internally
    #await ClockCycles(dut.clk, 2)

    #Read all 5 nibbles sequentially
    nibbles = [await spi_read_nibble(dut) for _ in range(5)]

    #Deassert read and ensure clock is low
    #await ClockCycles(dut.clk, 1)
    dut.uio_in[2].value = 0
    dut.uio_in[0].value = 0

    #Decode nibbles into result and carry
    n0, n1, n2, _n3, _n4 = nibbles

    res_low = n0 | (n1 << 4)          #bits [7:0]
    #res_high = (n2 >> 2) & 0x3        #bits [9:8]
    res_high = n2 & 0b0011
    res = res_low | (res_high << 8)

    carry = (n2 >> 2) & 0x1

    return res, carry, nibbles


async def mau_transaction(dut, op, a1, a2, b1, b2):
    #End-to-end MAU transaction: write instruction then read result.
    #Handles timing between instruction send and result read.
    
    await spi_send_instruction(dut, op, a1, a2, b1, b2)

    #Allow RX/DECODE/ALU/TX pipeline to complete
    #Generous timing for safe operation
    #await ClockCycles(dut.clk, 1)

    res, carry, nibbles = await spi_read_result(dut)

    #Small idle gap before the next command
    await ClockCycles(dut.clk, 5)

    return res, carry, nibbles


# ---------------------------------------------------------------------------
# Python models for DECODE + ALU to confirm functionality with sv code
# ---------------------------------------------------------------------------

def alu_ctrl_for_op(op: int):
    #Returns a dict of control bits matching decode_module_4b.sv for a 4 bit op.
    #Maps opcodes to their corresponding control signal configurations.
    
    op &= 0xF

    #Default control values
    ctrl = {
        "pre_x_en":  0,
        "pre_x_sub": 0,
        "pre_y_en":  0,
        "pre_y_sub": 0,
        "mul_x_en":  0,
        "mul_x_sel": 1,   #default 3'd1
        "mul_y_en":  0,
        "mul_y_sel": 1,   #default 3'd1
        "post_en":   0,
        "post_sub":  0,
    }

    #DOT2, WSUM, PROJU, SUMSQ, SCSUM: x0*x1 + y0*y1
    if op in (DOT2, WSUM, PROJU, SUMSQ, SCSUM):
        ctrl["mul_x_en"] = 1
        ctrl["mul_y_en"] = 1
        ctrl["post_en"]  = 1

    #VADD2: (x0+x1, y0+y1) packed
    elif op == VADD2:
        ctrl["pre_x_en"]  = 1
        ctrl["mul_x_en"]  = 1
        ctrl["mul_x_sel"] = 4  # mul by 1

        ctrl["pre_y_en"]  = 1
        ctrl["mul_y_en"]  = 1
        ctrl["mul_y_sel"] = 4  # mul by 1

    #VSUB2: (x0-x1, y0-y1) packed
    elif op == VSUB2:
        ctrl["pre_x_en"]  = 1
        ctrl["pre_x_sub"] = 1
        ctrl["mul_x_en"]  = 1
        ctrl["mul_x_sel"] = 4

        ctrl["pre_y_en"]  = 1
        ctrl["pre_y_sub"] = 1
        ctrl["mul_y_en"]  = 1
        ctrl["mul_y_sel"] = 4

    #DIFF2/DET2/DIFFSQ: x0*x1 - y0*y1
    elif op in (DIFF2, DET2, DIFFSQ):
        ctrl["mul_x_en"]  = 1
        ctrl["mul_x_sel"] = 1
        ctrl["mul_y_en"]  = 1
        ctrl["mul_y_sel"] = 1
        ctrl["post_en"]   = 1
        ctrl["post_sub"]  = 1

    #DIST2: (x0-x1)^2 - (y0-y1)^2
    elif op == DIST2:
        ctrl["pre_x_en"]  = 1
        ctrl["pre_x_sub"] = 1
        ctrl["mul_x_en"]  = 1
        ctrl["mul_x_sel"] = 2  #square

        ctrl["pre_y_en"]  = 1
        ctrl["pre_y_sub"] = 1
        ctrl["mul_y_en"]  = 1
        ctrl["mul_y_sel"] = 2  #square

        ctrl["post_en"]   = 1
        ctrl["post_sub"]  = 1

    #POLY: "ax + b" family – uses x pre-add and post-add, no mul enable
    elif op == POLY:
        ctrl["pre_x_en"]  = 1
        ctrl["post_en"]   = 1

    #SCMUL: x0*x1 and y0*y1, packed (no post add)
    elif op == SCMUL:
        ctrl["mul_x_en"]  = 1
        ctrl["mul_x_sel"] = 1
        ctrl["mul_y_en"]  = 1
        ctrl["mul_y_sel"] = 1

    #LERPX: x0 + c(y1 - y0)-style behaviour (per decode comments)
    elif op == LERPX:
        ctrl["mul_x_en"]  = 1
        ctrl["mul_x_sel"] = 4  #mul by 1

        ctrl["pre_y_en"]  = 1
        ctrl["pre_y_sub"] = 1
        ctrl["mul_y_en"]  = 1
        ctrl["mul_y_sel"] = 3  #mul by c (x1)

        ctrl["post_en"]   = 1

    #LERPY: y0 + c(x0 - x1)-style behaviour
    elif op == LERPY:
        ctrl["pre_x_en"]  = 1
        ctrl["pre_x_sub"] = 1
        ctrl["mul_x_en"]  = 1
        ctrl["mul_x_sel"] = 3  #mul by c (y1)

        ctrl["mul_y_en"]  = 1
        ctrl["mul_y_sel"] = 4  #mul by 1

        ctrl["post_en"]   = 1

    #NOOP / unknown: keep defaults (pre disabled, mul disabled, post disabled)
    return ctrl


def alu_model_for_mau_sim(op: int, a1: int, a2: int, b1: int, b2: int):
    #Python model of decode+ALU datapath to compute expected res/carry.
    #Mirrors:
    # - decode_module_4b operand routing (x0=a1, x1=a2, y0=b1, y1=b2)
    # - decode_module_4b control generation
    # - alu_module_4b: pre_add4, mul5x5, add10, muxing behaviour.
    
    #Operand routing: hard-coded to [a1,a2,b1,b2]
    x0 = a1 & 0xF
    x1 = a2 & 0xF
    y0 = b1 & 0xF
    y1 = b2 & 0xF

    ctrl = alu_ctrl_for_op(op)

    #pre_add4: 5 bit result, pass-through when disabled
    def pre_add(en: int, sub: int, in0: int, in1: int) -> int:
        a = in0 & 0xF
        b = in1 & 0xF
        if not en:
            return a  #{0,in0} numerically = in0
        if sub:
            return (a - b) & 0x1F
        else:
            return (a + b) & 0x1F

    x_pre = pre_add(ctrl["pre_x_en"], ctrl["pre_x_sub"], x0, x1)
    y_pre = pre_add(ctrl["pre_y_en"], ctrl["pre_y_sub"], y0, y1)

    #sel_mul_in helper: selects multiplier input based on sel signal
    def sel_mul(sel: int, in0: int, in1: int, pre_res: int, c_other: int) -> int:
        in0_5 = in0 & 0x1F
        in1_5 = in1 & 0x1F
        pre   = pre_res & 0x1F
        c     = c_other & 0xF
        if sel == 0:
            return in0_5
        elif sel == 1:
            return in1_5
        elif sel == 2:
            return pre
        elif sel == 3:
            return c & 0x1F
        elif sel == 4:
            return 1
        else:
            return 0

    #m0/m1 inputs (5 bit each) for multipliers
    x_m0 = x_pre & 0x1F
    x_m1 = sel_mul(ctrl["mul_x_sel"], x0, x1, x_pre, y1)
    y_m0 = y_pre & 0x1F
    y_m1 = sel_mul(ctrl["mul_y_sel"], y0, y1, y_pre, x1)

    #mul5x5: either multiply or concatenate {m0,m1}
    def mul5x5(en: int, m0: int, m1: int) -> int:
        m0 &= 0x1F
        m1 &= 0x1F
        if not en:
            return ((m0 << 5) | m1) & 0x3FF
        else:
            return (m0 * m1) & 0x3FF

    x_prod = mul5x5(ctrl["mul_x_en"], x_m0, x_m1)
    y_prod = mul5x5(ctrl["mul_y_en"], y_m0, y_m1)

    #add10: either pack low 5 bits of each, or add/sub 10 bit values with carry
    if not ctrl["post_en"]:
        res  = (((x_prod & 0x1F) << 5) | (y_prod & 0x1F)) & 0x3FF
        carry = 0
    else:
        a = x_prod & 0x3FF
        b = y_prod & 0x3FF
        if ctrl["post_sub"]:
            tmp = (a - b) & 0x7FF   #emulate {1'b0,a} - {1'b0,b}
        else:
            tmp = (a + b) & 0x7FF   #emulate {1'b0,a} + {1'b0,b}
        res   = tmp & 0x3FF
        carry = (tmp >> 10) & 0x1

    return res, carry


# ---------------------------------------------------------------------------
# Simple Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_mau_dot2(dut):
    #DOT2 (opcode 0x1) end-to-end: (a1*a2) + (b1*b2).
    #Tests basic dot product operation with simple vectors.
    
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    #Test vectors with known results
    vectors = [
        (2, 3, 1, 4),   #2*3 + 1*4 = 10
        (5, 7, 3, 2),   #5*7 + 3*2 = 41
        (9, 2, 4, 1),   #9*2 + 4*1 = 22
    ]

    for (a1, a2, b1, b2) in vectors:
        res, carry, _ = await mau_transaction(dut, DOT2, a1, a2, b1, b2)

        expected = a1 * a2 + b1 * b2

        assert res == expected, (
            f"DOT2 mismatch for a=({a1},{a2}), b=({b1},{b2}): "
            f"got res={res}, expected {expected}"
        )
        #With 4 bit operands, the dot product fits within 10 bits => carry=0
        assert carry == 0, f"DOT2 carry should be 0, got {carry}"


@cocotb.test()
async def test_mau_vadd2(dut):
    #VADD2 (opcode 0x6) end-to-end: lane-wise add packed into 10 bits.
    #Expected MAU behaviour (from decode + ALU tests):
    # - x_sum = a1 + a2 (5 bit)
    # - y_sum = b1 + b2 (5 bit)
    # - res[9:5] = x_sum
    # - res[4:0] = y_sum
    
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    vectors = [
        (1, 2, 3, 4),   #x:3,  y:7
        (5, 6, 1, 1),   #x:11, y:2
        (8, 7, 4, 3),   #x:15, y:7
    ]

    for (a1, a2, b1, b2) in vectors:
        res, carry, _ = await mau_transaction(dut, VADD2, a1, a2, b1, b2)

        #Extract packed lane results
        x_sum_out = (res >> 5) & 0x1F
        y_sum_out = res & 0x1F

        x_expected = (a1 + a2) & 0x1F
        y_expected = (b1 + b2) & 0x1F

        assert x_sum_out == x_expected, (
            f"VADD2 X-lane mismatch for a=({a1},{a2}): "
            f"got {x_sum_out}, expected {x_expected}"
        )
        assert y_sum_out == y_expected, (
            f"VADD2 Y-lane mismatch for b=({b1},{b2}): "
            f"got {y_sum_out}, expected {y_expected}"
        )

        #Post adder is disabled in VADD2 path, carry_q should be 0
        assert carry == 0, f"VADD2 carry should be 0, got {carry}"


@cocotb.test()
async def test_mau_back_to_back_ops(dut):
    #Issue DOT2 then VADD2 back-to-back to exercise internal handshakes.
    #Tests pipeline handshaking between operations.

    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    #First operation: DOT2
    a1, a2, b1, b2 = 3, 4, 2, 1
    res_dot2, carry_dot2, _ = await mau_transaction(dut, DOT2, a1, a2, b1, b2)

    expected_dot2 = a1 * a2 + b1 * b2
    assert res_dot2 == expected_dot2, (
        f"Back-to-back DOT2 result mismatch: got {res_dot2}, expected {expected_dot2}"
    )
    assert carry_dot2 == 0, "DOT2 carry should be 0"

    #Second operation: VADD2
    a1, a2, b1, b2 = 2, 5, 1, 7
    res_vadd, carry_vadd, _ = await mau_transaction(dut, VADD2, a1, a2, b1, b2)

    x_sum_out = (res_vadd >> 5) & 0x1F
    y_sum_out = res_vadd & 0x1F

    assert x_sum_out == ((a1 + a2) & 0x1F), "Back-to-back VADD2 X-lane mismatch"
    assert y_sum_out == ((b1 + b2) & 0x1F), "Back-to-back VADD2 Y-lane mismatch"
    assert carry_vadd == 0, "VADD2 carry should be 0 in back-to-back test"


# ---------------------------------------------------------------------------
# Stress tests - wide opcode coverage + difficult edge cases
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_mau_all_ops_random_sweep(dut):
    #Randomly sweep all opcodes with many transactions, end-to-end vs model.
    #Tests:
    # - NOOP, DOT2/WSUM/... family
    # - VADD2 / VSUB2 packed-lane ops
    # - DIFF2/DET2/DIFFSQ/DIST2 (subtractions & squares)
    # - POLY / SCMUL / LERPX / LERPY with more complex mul routing.
    
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    random.seed(0x123456)
    ops = list(range(16))  #0x0 - 0xF

    num_transactions = 80  #reasonably heavy but still quick to simulate

    for i in range(num_transactions):
        #Generate random operands and opcode
        op  = random.choice(ops)
        a1  = random.randint(0, 15)
        a2  = random.randint(0, 15)
        b1  = random.randint(0, 15)
        b2  = random.randint(0, 15)

        #Get expected result from model
        exp_res, exp_carry = alu_model_for_mau(op, a1, a2, b1, b2)
        res, carry, _  = await mau_transaction(dut, op, a1, a2, b1, b2)

        assert res == exp_res, (
            f"[rand sweep #{i}] res mismatch: "
            f"op=0x{op:X}, a=({a1},{a2}), b=({b1},{b2}), "
            f"got res={res}, expected {exp_res}"
        )
        assert carry == exp_carry, (
            f"[rand sweep #{i}] carry mismatch: "
            f"op=0x{op:X}, a=({a1},{a2}), b=({b1},{b2}), "
            f"got carry={carry}, expected {exp_carry}"
        )


@cocotb.test()
async def test_mau_extreme_operands_across_ops(dut):
    #Stress extreme operand patterns across a set of 'difficult' operations.
    #Focuses on:
    # - DOT2: large products
    # - VADD2 / VSUB2: lane saturation / wraparound
    # - DIFF2 / DIST2: subtraction and square-of-differences
    # - SCMUL: packed products
    # - LERPX / LERPY / POLY: more complex cross-lane interactions
    

    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    ops_to_stress = [DOT2, VADD2, VSUB2, DIFF2, DIST2, SCMUL, LERPX, LERPY, POLY]

    #Extreme pairs to generate overflow / underflow / sign flips
    extreme_pairs = [
        (0x0, 0x0),
        (0x0, 0xF),
        (0xF, 0x0),
        (0xF, 0xF),
        (0x1, 0xE),
        (0x7, 0x8),
    ]

    case_idx = 0
    total_cases = len(ops_to_stress) * len(extreme_pairs) * len(extreme_pairs)
    for op in ops_to_stress:
        for (a1, a2) in extreme_pairs:
            for (b1, b2) in extreme_pairs:
                #Get expected results from both models for verification
                exp_res_sim, exp_carry_sim = alu_model_for_mau_sim(op, a1, a2, b1, b2)
                exp_res, exp_carry = alu_model_for_mau(op, a1, a2, b1, b2)
                res, carry, _ = await mau_transaction(dut, op, a1, a2, b1, b2)

                msg = (
                    f"[extreme #{case_idx}/{total_cases}] "
                    f"op=0x{op:X}, a=({a1},{a2}), b=({b1},{b2}), "
                    f"exp_res={exp_res}, exp_carry={exp_carry}, "
                    f"res={res}, carry={carry}"
                )
                #dut._log.info(msg)  # Uncomment to print output of every test for debug

                assert res == exp_res, msg + " <-- RES MISMATCH"
                assert carry == exp_carry, msg + "<-- CARRY MISMATCH"
                case_idx += 1

    dut._log.info("[extreme] Completed extreme operand stress successfully")


@cocotb.test()
async def test_mau_noop_and_scalar_ops_stress(dut):
    #Stress test for NOOP, DOT2, and SCMUL using randomly sampled operands.
    #NOOP uses the default ctrl path (no pre, no mul, no post).
    #DOT2 and SCMUL both involve x0*x1 and y0*y1 with different packing/post adder behaviour.
    
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    ops = [NOOP, DOT2, SCMUL]

    #Nibble set containing a range of representative values
    vals = [0x0, 0x1, 0x3, 0x7, 0x8, 0xC, 0xF]

    random.seed(0x123ABC)
    max_samples_per_op = 32  #Keep this reasonable so sim doesn't hang

    case_idx = 0
    for op in ops:
        for _ in range(max_samples_per_op):
            #Sample random operands from the value set
            a1 = random.choice(vals)
            a2 = random.choice(vals)
            b1 = random.choice(vals)
            b2 = random.choice(vals)

            #Get expected results from both models
            exp_res_sim, exp_carry_sim = alu_model_for_mau_sim(op, a1, a2, b1, b2)
            exp_res, exp_carry = alu_model_for_mau(op, a1, a2, b1, b2)
            res, carry, _ = await mau_transaction(dut, op, a1, a2, b1, b2)

            msg = (
                f"[stress #{case_idx}] "
                f"op=0x{op:X}, a=({a1},{a2}), b=({b1},{b2}), "
                f"exp_res={exp_res}, exp_carry={exp_carry}, "
                f"res={res}, carry={carry}"
            )
            #dut._log.info(msg) # Uncomment to print output of every test for debug

            assert res == exp_res, msg + " <-- RES MISMATCH"
            assert carry == exp_carry, msg + "<-- CARRY MISMATCH"
            case_idx += 1
    
    dut._log.info(f"[stress] Completed sampled sweep, total cases={case_idx}")