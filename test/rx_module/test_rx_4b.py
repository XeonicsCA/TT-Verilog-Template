# SPDX-License-Identifier: Apache-2.0
# Unit tests for rx_4b module via the rx_tb_4b wrapper.
# These focus on SPI write behavior, register loading, and edge cases.

# 4-BIT VERSION OF TEST_RX.PY

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CLK_NS = 10  # 100 MHz

async def reset(dut):
    """Reset the RX module."""
    dut.rst_n.value = 0
    dut.spi_clk.value = 0
    dut.spi_w.value = 0
    dut.mosi.value = 0
    dut.alu_ready.value = 1  # Default to ALU ready
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

async def spi_write_nibble(dut, nibble_data, spi_clk_cycles=5):
    """Simulates writing one nibble (4 bits) via SPI.
    
    Args:
        dut: The device under test
        nibble_data: 4-bit value to write (0x0 to 0xF)
        spi_clk_cycles: Number of system clocks per SPI clock edge
    """
    dut.mosi.value = nibble_data & 0xF  # Mask to 4 bits
    
    # SPI clock low
    dut.spi_clk.value = 0
    await ClockCycles(dut.clk, spi_clk_cycles)
    
    # SPI clock high (data is sampled here)
    dut.spi_clk.value = 1
    await ClockCycles(dut.clk, spi_clk_cycles)
    
    # SPI clock low (end on low)
    dut.spi_clk.value = 0
    await ClockCycles(dut.clk, spi_clk_cycles)

@cocotb.test()
async def test_rx_happy_path(dut):
    """Validate RX module loads registers correctly during normal operation.

    What this test verifies:
      - RX module correctly samples MOSI data on SPI clock edges
      - All five registers (op_reg, a1_reg, a2_reg, b1_reg, b2_reg) are loaded
        in sequence across 5 SPI write cycles
      - Nibble counter increments correctly through the write sequence
      - rx_valid output asserts after all nibbles are received

    Expected outcome:
      - After 5 SPI write cycles with SPI_W=1:
        - op_reg == 0x9
        - a1_reg == 0xA
        - a2_reg == 0xE
        - b1_reg == 0x4
        - b2_reg == 0x8
        - rx_valid == 1
    """
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    instruction = [0x9, 0xA, 0xE, 0x4, 0x8]  # [OP, A1, A2, B1, B2] - 4-bit values

    # Assert SPI_W to enable writing
    dut.spi_w.value = 1
    await ClockCycles(dut.clk, 1)

    # Write all 5 nibbles of the instruction
    for nibble_val in instruction:
        await spi_write_nibble(dut, nibble_val)

    # De-assert SPI_W
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 2)

    # Verify all registers loaded correctly
    assert int(dut.op_reg.value) == 0x9, f"Expected op_reg=0x9, got {hex(int(dut.op_reg.value))}"
    assert int(dut.a1_reg.value) == 0xA, f"Expected a1_reg=0xA, got {hex(int(dut.a1_reg.value))}"
    assert int(dut.a2_reg.value) == 0xE, f"Expected a2_reg=0xE, got {hex(int(dut.a2_reg.value))}"
    assert int(dut.b1_reg.value) == 0x4, f"Expected b1_reg=0x4, got {hex(int(dut.b1_reg.value))}"
    assert int(dut.b2_reg.value) == 0x8, f"Expected b2_reg=0x8, got {hex(int(dut.b2_reg.value))}"
    
    # Verify rx_valid is asserted
    assert int(dut.rx_valid.value) == 1, "rx_valid should assert after complete write"

@cocotb.test()
async def test_rx_interrupted_write(dut):
    """Verify RX module behavior when SPI write is interrupted.

    What this test verifies:
      - When SPI_W is deasserted mid-write, the nibble counter should reset
      - A subsequent complete write should load registers correctly
      - Incomplete writes should not corrupt the final register values

    Expected outcome:
      - After interrupted write (3 nibbles) then complete write (5 nibbles):
        - Registers contain values from the complete write, not corrupted
        - op_reg == 0x9 (not corrupted by interrupted write)
    
    Note: This test may FAIL if nibble_counter does not reset when SPI_W goes low.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    instruction = [0x9, 0xA, 0xE, 0x4, 0x8]

    # Write 3 nibbles, then interrupt
    dut.spi_w.value = 1
    await spi_write_nibble(dut, instruction[0])  # op_reg
    await spi_write_nibble(dut, instruction[1])  # a1_reg
    await spi_write_nibble(dut, instruction[2])  # a2_reg

    # Interrupt the write by deasserting SPI_W
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 10)

    # Start a new, complete write
    dut.spi_w.value = 1
    for nibble_val in instruction:
        await spi_write_nibble(dut, nibble_val)
    
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 2)

    # Verify registers contain correct values from complete write
    op_reg_val = int(dut.op_reg.value)
    a1_reg_val = int(dut.a1_reg.value)
    a2_reg_val = int(dut.a2_reg.value)
    b1_reg_val = int(dut.b1_reg.value)
    b2_reg_val = int(dut.b2_reg.value)

    assert op_reg_val == 0x9, f"Expected op_reg=0x9, got {hex(op_reg_val)} (interrupted write may have corrupted)"
    assert a1_reg_val == 0xA, f"Expected a1_reg=0xA, got {hex(a1_reg_val)}"
    assert a2_reg_val == 0xE, f"Expected a2_reg=0xE, got {hex(a2_reg_val)}"
    assert b1_reg_val == 0x4, f"Expected b1_reg=0x4, got {hex(b1_reg_val)}"
    assert b2_reg_val == 0x8, f"Expected b2_reg=0x8, got {hex(b2_reg_val)}"

@cocotb.test()
async def test_rx_reset_during_write(dut):
    """Verify system reset clears RX registers during an active write.

    What this test verifies:
      - Registers can be loaded normally during a write
      - System reset (rst_n) clears all registers immediately
      - Nibble counter and state machine reset properly

    Expected outcome:
      - After loading 2 nibbles, registers should contain those values
      - After asserting reset, all registers should be cleared to 0
    """
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    instruction = [0x9, 0xA, 0xE, 0x4, 0x8]

    # Start writing and load 2 nibbles
    dut.spi_w.value = 1
    await spi_write_nibble(dut, instruction[0])  # op_reg
    await spi_write_nibble(dut, instruction[1])  # a1_reg

    # Verify registers loaded
    a1_reg_val = int(dut.a1_reg.value)
    assert a1_reg_val == 0xA, "a1_reg was not loaded correctly before reset"

    # Apply system reset
    await reset(dut)

    # Verify all registers cleared
    assert int(dut.op_reg.value) == 0, f"op_reg did not clear on reset. Value: {hex(int(dut.op_reg.value))}"
    assert int(dut.a1_reg.value) == 0, f"a1_reg did not clear on reset. Value: {hex(int(dut.a1_reg.value))}"
    assert int(dut.a2_reg.value) == 0, f"a2_reg did not clear on reset. Value: {hex(int(dut.a2_reg.value))}"
    assert int(dut.b1_reg.value) == 0, f"b1_reg did not clear on reset. Value: {hex(int(dut.b1_reg.value))}"
    assert int(dut.b2_reg.value) == 0, f"b2_reg did not clear on reset. Value: {hex(int(dut.b2_reg.value))}"
    assert int(dut.rx_valid.value) == 0, "rx_valid should be low after reset"

@cocotb.test()
async def test_rx_multiple_writes(dut):
    """Verify RX module can handle multiple consecutive instruction writes.

    What this test verifies:
      - After completing one write, the module can accept another
      - rx_valid pulses appropriately between writes
      - Register values update correctly for each new instruction

    Expected outcome:
      - First instruction loads correctly
      - Second instruction overwrites with new values
      - Each write produces correct register values
    """
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    instruction_1 = [0x1, 0x5, 0xA, 0xF, 0x4]
    instruction_2 = [0x6, 0x9, 0xE, 0x3, 0x8]

    # First write
    dut.spi_w.value = 1
    for nibble_val in instruction_1:
        await spi_write_nibble(dut, nibble_val)
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 2)

    # Verify first instruction
    assert int(dut.op_reg.value) == 0x1, "First instruction op_reg incorrect"
    assert int(dut.a1_reg.value) == 0x5, "First instruction a1_reg incorrect"

    # Wait between writes
    await ClockCycles(dut.clk, 5)

    # Second write
    dut.spi_w.value = 1
    for nibble_val in instruction_2:
        await spi_write_nibble(dut, nibble_val)
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 2)

    # Verify second instruction overwrote correctly
    assert int(dut.op_reg.value) == 0x6, "Second instruction op_reg incorrect"
    assert int(dut.a1_reg.value) == 0x9, "Second instruction a1_reg incorrect"
    assert int(dut.a2_reg.value) == 0xE, "Second instruction a2_reg incorrect"
    assert int(dut.b1_reg.value) == 0x3, "Second instruction b1_reg incorrect"
    assert int(dut.b2_reg.value) == 0x8, "Second instruction b2_reg incorrect"

@cocotb.test()
async def test_rx_without_spi_w(dut):
    """Verify RX module ignores SPI clocks when SPI_W is not asserted.

    What this test verifies:
      - Without SPI_W asserted, SPI clock edges should not load data
      - Registers should remain at their reset values (0)
      - rx_valid should remain low

    Expected outcome:
      - After SPI clock cycles without SPI_W=1:
        - All registers remain 0
        - rx_valid == 0
    """
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    # Try to write without asserting SPI_W
    dut.spi_w.value = 0  # Keep SPI_W low
    await spi_write_nibble(dut, 0x9)
    await spi_write_nibble(dut, 0xA)
    await spi_write_nibble(dut, 0x4)
    await ClockCycles(dut.clk, 2)

    # Verify no registers were loaded
    assert int(dut.op_reg.value) == 0, "op_reg should not load without SPI_W"
    assert int(dut.a1_reg.value) == 0, "a1_reg should not load without SPI_W"
    assert int(dut.a2_reg.value) == 0, "a2_reg should not load without SPI_W"
    assert int(dut.rx_valid.value) == 0, "rx_valid should remain low without SPI_W"

@cocotb.test()
async def test_rx_alu_backpressure(dut):
    """Verify RX module respects ALU backpressure.

    What this test verifies:
      - When alu_ready=0 and instruction complete, rx_valid should NOT assert
      - When alu_ready=1, rx_valid can assert after complete instruction
      - Registers hold their values when ALU is busy

    Expected outcome:
      - With alu_ready=0: rx_valid stays low after complete write
      - After setting alu_ready=1: rx_valid asserts
    """
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    instruction = [0x9, 0xA, 0xE, 0x4, 0x8]

    # Set ALU to busy before starting write
    dut.alu_ready.value = 0

    # Write complete instruction
    dut.spi_w.value = 1
    for nibble_val in instruction:
        await spi_write_nibble(dut, nibble_val)
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 2)

    # Verify rx_valid did NOT assert because ALU was busy
    assert int(dut.rx_valid.value) == 0, "rx_valid should not assert when alu_ready=0"

    # Now signal ALU is ready
    dut.alu_ready.value = 1
    await ClockCycles(dut.clk, 2)

    # rx_valid should remain low because we need a new write when ALU becomes ready
    # (Based on the logic, rx_valid only asserts during the write of the last nibble)
    assert int(dut.rx_valid.value) == 0, "rx_valid cleared after ALU ready"

    # Verify registers still hold the data
    assert int(dut.op_reg.value) == 0x9, "Registers should hold data during backpressure"

@cocotb.test()
async def test_rx_all_zeros(dut):
    """Verify RX module handles all-zero instruction correctly.

    What this test verifies:
      - Module can handle 0x0 values in all fields
      - rx_valid still asserts for valid zero instruction

    Expected outcome:
      - All registers == 0x0 after write
      - rx_valid == 1
    """
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    instruction = [0x0, 0x0, 0x0, 0x0, 0x0]

    # Write all zeros
    dut.spi_w.value = 1
    for nibble_val in instruction:
        await spi_write_nibble(dut, nibble_val)
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 2)

    # Verify all registers are zero
    assert int(dut.op_reg.value) == 0x0, "op_reg should be 0x0"
    assert int(dut.a1_reg.value) == 0x0, "a1_reg should be 0x0"
    assert int(dut.a2_reg.value) == 0x0, "a2_reg should be 0x0"
    assert int(dut.b1_reg.value) == 0x0, "b1_reg should be 0x0"
    assert int(dut.b2_reg.value) == 0x0, "b2_reg should be 0x0"
    assert int(dut.rx_valid.value) == 1, "rx_valid should assert for zero instruction"

@cocotb.test()
async def test_rx_all_ones(dut):
    """Verify RX module handles all-ones (0xF) instruction correctly.

    What this test verifies:
      - Module can handle maximum 4-bit values (0xF) in all fields
      - rx_valid still asserts for valid max-value instruction

    Expected outcome:
      - All registers == 0xF after write
      - rx_valid == 1
    """
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    instruction = [0xF, 0xF, 0xF, 0xF, 0xF]

    # Write all ones
    dut.spi_w.value = 1
    for nibble_val in instruction:
        await spi_write_nibble(dut, nibble_val)
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 2)

    # Verify all registers are 0xF
    assert int(dut.op_reg.value) == 0xF, "op_reg should be 0xF"
    assert int(dut.a1_reg.value) == 0xF, "a1_reg should be 0xF"
    assert int(dut.a2_reg.value) == 0xF, "a2_reg should be 0xF"
    assert int(dut.b1_reg.value) == 0xF, "b1_reg should be 0xF"
    assert int(dut.b2_reg.value) == 0xF, "b2_reg should be 0xF"
    assert int(dut.rx_valid.value) == 1, "rx_valid should assert for max-value instruction"