# SPDX-License-Identifier: Apache-2.0
#
# ALU 4-bit unit tests for alu_stage_4b via alu_tb_4b wrapper.
#
# Tests:
#   - VADD2 (opcode 0x06): lane-wise add, result concatenation (lower 5b per lane)
#   - DOT2  (opcode 0x01): (x0*x1) + (y0*y1) using lane multipliers and post add
#   - Backpressure behavior on the result channel
#
# These tests drive control bits directly (alu_ctrl_t), not opcodes
# Mapping to the opcode table:
#   VADD2: pre_x_en=1 (add), pre_y_en=1 (add), mul_*_en=1 with sel=ONE (x*1, y*1 as pass-through),
#          post_en=0 (concat lanes). Expected: {pre_x[4:0], pre_y[4:0]}.
#   DOT2:  pre_*_en=0 (pass in0), mul_*_en=1, mul_*_sel=1 (select in1), post_en=1 (add lanes).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.result import TestFailure

CLK_NS = 10

async def reset(dut):
    dut.rst_n.value = 0
    # clear I/O
    dut.cmd_valid.value = 0
    dut.res_ready.value = 0
    dut.x0.value = 0; dut.x1.value = 0
    dut.y0.value = 0; dut.y1.value = 0

    # ctrl defaults
    dut.pre_x_en.value = 0; dut.pre_x_sub.value = 0; dut.mul_x_en.value = 0; dut.mul_x_sel.value = 0
    dut.pre_y_en.value = 0; dut.pre_y_sub.value = 0; dut.mul_y_en.value = 0; dut.mul_y_sel.value = 0
    dut.post_en.value = 0;  dut.post_sub.value = 0;  dut.post_sel.value = 0

    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

def pre_lane(en: int, sub: int, a0: int, a1: int) -> int:
    """Compute the 5-bit pre-adder result per RTL: pass a0 if en==0; else a0 (+|-) a1 (wrap to 5b)."""
    a0 &= 0xF; a1 &= 0xF
    if not en:
        return a0  # implicit zero-extend to 5b
    if sub:
        return (a0 - a1) & 0x1F
    else:
        return (a0 + a1) & 0x1F

async def issue_and_wait(dut, max_cycles=20):
    """Assert cmd_valid, wait for a cmd_valid&cmd_ready handshake on a clock edge,
    then wait for res_valid."""
    dut.cmd_valid.value = 1

    # Wait for first cycle where ready is high (handshake)
    for i in range(max_cycles):
        await RisingEdge(dut.clk)
        cmd_v = int(dut.cmd_valid.value)
        cmd_r = int(dut.cmd_ready.value)
        dut._log.info(f"[issue_and_wait] handshake cycle {i}: cmd_valid={cmd_v} cmd_ready={cmd_r}")
        if cmd_v and cmd_r:
            break
    else:
        raise TestFailure("cmd_ready never went high while cmd_valid asserted")

    # Drop valid after handshake
    dut.cmd_valid.value = 0

    # Wait for result
    for i in range(max_cycles):
        await RisingEdge(dut.clk)
        res_v = int(dut.res_valid.value)
        dut._log.info(f"[issue_and_wait] wait result cycle {i}: res_valid={res_v}")
        if res_v:
            return

    raise TestFailure(
        f"res_valid never went high within {max_cycles} cycles, "
        f"res_valid={int(dut.res_valid.value)}, cmd_ready={int(dut.cmd_ready.value)}"
    )

@cocotb.test()
async def test_vadd2_concat(dut):
    """VADD2 (0x06): lane-wise add, concat lower 5 bits per lane into res_q[9:5]|res_q[4:0]."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    # Log state after reset
    dut._log.info(
        f"after reset: rst_n={int(dut.rst_n.value)} "
        f"cmd_ready={int(dut.cmd_ready.value)} "
        f"res_valid={int(dut.res_valid.value)}"
    )
    # Try to peek at 'res_full' (not currently being used)
    try:
        dut._log.info(f"after reset: u_alu.res_full={int(dut.u_alu.full.value)}")
    except AttributeError:
        dut._log.info("u_alu.res_full not visible from cocotb (check instance name)")

    # Operands (4-bit)
    x0, x1, y0, y1 = 0x3, 0x4, 0x5, 0x6
    dut.x0.value = x0; dut.x1.value = x1
    dut.y0.value = y0; dut.y1.value = y1

    # Control for VADD2-like behavior
    dut.pre_x_en.value = 1; dut.pre_x_sub.value = 0
    dut.pre_y_en.value = 1; dut.pre_y_sub.value = 0
    # Use multiplier as pass-through by multiplying by 1
    dut.mul_x_en.value = 1; dut.mul_x_sel.value = 4
    dut.mul_y_en.value = 1; dut.mul_y_sel.value = 4
    # Post concat
    dut.post_en.value  = 0; dut.post_sub.value = 0

    # Handshake
    """Perofmring handshake..."""
    dut.res_ready.value = 1
    await issue_and_wait(dut)

    # Result should be ready next cycle
    assert int(dut.cmd_ready.value) == 1, "ALU should accept command"
    assert int(dut.res_valid.value) == 1, "ALU should present a result"

    prex = pre_lane(1, 0, x0, x1)  # 5-bit
    prey = pre_lane(1, 0, y0, y1)  # 5-bit
    exp  = ((prex & 0x1F) << 5) | (prey & 0x1F)

    got = int(dut.res_q.value)
    assert got == exp, f"Concat expected 0x{exp:03x} got 0x{got:03x}"
    assert int(dut.carry_q.value) == 0, "Carry must be 0 in concat mode"


@cocotb.test()
async def test_dot2_post_add(dut):
    """DOT2 (0x01): (x0*x1) + (y0*y1) using lane multipliers and post add."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    x0, x1, y0, y1 = 0x2, 0x3, 0x1, 0x4  # 2*3 + 1*4 = 10
    dut.x0.value = x0; dut.x1.value = x1
    dut.y0.value = y0; dut.y1.value = y1

    # Pre pass-through (use in0 directly into multiplier)
    dut.pre_x_en.value = 0
    dut.pre_y_en.value = 0

    # Multiply by in1 on each lane
    dut.mul_x_en.value = 1; dut.mul_x_sel.value = 1  # select x1
    dut.mul_y_en.value = 1; dut.mul_y_sel.value = 1  # select y1

    # Post add lanes
    dut.post_en.value  = 1; dut.post_sub.value = 0

    dut.res_ready.value = 1
    await issue_and_wait(dut)

    exp = (x0 * x1) + (y0 * y1)
    exp &= 0x3FF  # 10-bit

    got = int(dut.res_q.value) & 0x3FF
    assert got == exp, f"DOT2 expected {exp} got {got}"
    assert int(dut.res_valid.value) == 1, "Result should be valid"

@cocotb.test()
async def test_result_backpressure(dut):
    """Hold res_ready=0 and ensure cmd_ready drops while res_valid stays asserted until release."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    # Pass-through via multiply-by-1, concat
    dut.pre_x_en.value = 1; dut.pre_x_sub.value = 0; dut.mul_x_en.value = 1; dut.mul_x_sel.value = 4
    dut.pre_y_en.value = 1; dut.pre_y_sub.value = 0; dut.mul_y_en.value = 1; dut.mul_y_sel.value = 4
    dut.post_en.value  = 0; dut.post_sub.value = 0

    dut.x0.value = 0x1; dut.x1.value = 0x1
    dut.y0.value = 0x2; dut.y1.value = 0x2

    # Backpressure, not ready to take result
    dut.res_ready.value = 0
    dut.cmd_valid.value = 1
    while int(dut.cmd_ready.value) == 0: # wait until ALU accepts handshake
        await ClockCycles(dut.clk, 1)
    await ClockCycles(dut.clk, 1) # advance one cycle for registered result to appear
    dut.cmd_valid.value = 0 # drop CMD valid, ALU has value latched
    # await ClockCycles(dut.clk, 1) # wait one cycle for values to settle

    assert int(dut.res_valid.value) == 1, "Result must be held valid under backpressure"
    assert int(dut.cmd_ready.value) == 0, "cmd_ready should be low while holding a result"

    # Release backpressure, result should be consumed and ready returns high
    dut.res_ready.value = 1
    dut._log.info(
        f"before consume: res_valid={int(dut.res_valid.value)} "
        f"dbg_res_valid={int(dut.u_alu.dbg_res_valid.value)}"
    )
    await ClockCycles(dut.clk, 1)
    dut._log.info(
        f"after consume: res_valid={int(dut.res_valid.value)} "
        f"dbg_res_valid={int(dut.u_alu.dbg_res_valid.value)}"
    )
    assert int(dut.res_valid.value) == 0, "Result should be consumed when res_ready goes high"
    assert int(dut.cmd_ready.value) == 1, "ALU should become ready again"
