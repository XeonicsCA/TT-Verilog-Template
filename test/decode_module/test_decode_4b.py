# SPDX-License-Identifier: Apache-2.0
# Unit tests for decode_stage via the decode_tb wrapper.
# These focus on handshake behavior and default operand routing.
# Will add opcode-specific checks in the future

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CLK_NS = 10  # 100 MHz

async def reset(dut):
    dut.rst_n.value = 0
    dut.rx_valid_in.value = 0
    dut.cmd_ready_in.value = 0
    dut.op.value = 0
    dut.a1.value = 0
    dut.a2.value = 0
    dut.b1.value = 0
    dut.b2.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

@cocotb.test()
async def test_default_routing_and_handshake(dut):
    """Validate default operand routing and handshake behavior.

    What this test verifies:
      - On a NOOP/default opcode, the decode routes a1->x0, a2->x1, b1->y0, b2->y1.
      - With rx_valid_in=1 and cmd_ready_in=1, cmd_valid_out asserts (a transfer occurs).
      - After we deassert rx_valid_in (simulate “no more instruction”), cmd_valid_out goes low
        on the following cycle (no transfer).

    Expected outcome:
      - First checked cycle after asserting valid+ready: cmd_valid_out == 1
      - Next cycle after dropping rx_valid_in:        cmd_valid_out == 0
    """
    # Drive clock (overrides the .sv initial if present)
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())

    await reset(dut)

    # Set operands and assert ready+valid in same cycle
    A1, A2, B1, B2 = 0x1, 0x2, 0x3, 0x4
    dut.a1.value = A1
    dut.a2.value = A2
    dut.b1.value = B1
    dut.b2.value = B2

    dut.cmd_ready_in.value = 1
    dut.rx_valid_in.value = 1
    dut.op.value = 0x0  # NOOP localparam in decode module

    # Advance one cycle, expect a 1-cycle pulse on cmd_valid_out
    await ClockCycles(dut.clk, 1)

    assert int(dut.alu_ready_out.value) == 1, "alu_ready_out should mirror cmd_ready_in"
    assert int(dut.cmd_valid_out.value) == 1, "cmd_valid_out should assert when valid & ready"

    # Default routing check
    assert int(dut.x0.value) == A1, "x0 should equal a1 on default routing"
    assert int(dut.x1.value) == A2, "x1 should equal a2 on default routing"
    assert int(dut.y0.value) == B1, "y0 should equal b1 on default routing"
    assert int(dut.y1.value) == B2, "y1 should equal b2 on default routing"

    # Next cycle the valid should drop (acceptance/clear)
    dut.rx_valid_in.value = 0
    await ClockCycles(dut.clk, 1)
    assert int(dut.cmd_valid_out.value) == 0, "cmd_valid_out should clear after acceptance"

@cocotb.test()
async def test_backpressure(dut):
    """Ensure decode respects downstream backpressure.

    What this test verifies:
      - When the ALU (downstream) is NOT ready (cmd_ready_in=0),
        decode must NOT assert cmd_valid_out, even if rx_valid_in=1.
      - When backpressure is released (set cmd_ready_in=1),
        decode asserts cmd_valid_out on the next cycle.

    Expected outcome:
      - During backpressure window: cmd_valid_out == 0
      - After release (next cycle):  cmd_valid_out == 1
    """
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    dut.op.value = 0x0  # NOOP
    dut.a1.value = 0xA
    dut.a2.value = 0xB
    dut.b1.value = 0xC
    dut.b2.value = 0xD

    dut.rx_valid_in.value = 1
    dut.cmd_ready_in.value = 0  # backpressure from ALU

    await ClockCycles(dut.clk, 2)
    assert int(dut.cmd_valid_out.value) == 0, "cmd_valid_out must remain low if ALU not ready"
    assert int(dut.alu_ready_out.value) == 0, "alu_ready_out should mirror cmd_ready_in=0"

    # Release backpressure, expect valid to pulse
    dut.cmd_ready_in.value = 1
    await ClockCycles(dut.clk, 1)
    assert int(dut.cmd_valid_out.value) == 1, "cmd_valid_out should assert once ready is high"

@cocotb.test()
async def test_opcode_changes_ctrl(dut):
    """Sanity-check that ctrl (control word) changes with opcode.

    What this test verifies:
      - Capture a baseline control word (ctrl_flat) while issuing a NOOP.
      - Change the opcode to a non-NOOP (VADD2 = 0x6).
      - The packed control bits should differ from the NOOP baseline.

    Expected outcome:
      - ctrl_flat differs between NOOP (0x0) and the non-NOOP opcode.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    # Capture baseline ctrl on NOOP
    dut.op.value = 0x0  # NOOP
    dut.rx_valid_in.value = 1
    dut.cmd_ready_in.value = 1
    await ClockCycles(dut.clk, 1)
    baseline = int(dut.ctrl_flat.value)

    # Try any non-zero opcode
    dut.op.value = 0x6 # VADD2 (0x6)
    await ClockCycles(dut.clk, 1)
    changed = int(dut.ctrl_flat.value)

    assert changed != baseline, (
        "Expected ctrl_flat to change for a non-NOOP opcode. "
    )
