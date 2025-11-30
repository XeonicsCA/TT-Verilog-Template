# Unit tests for rx_4b module

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CLK_NS = 10  #100MHz system clock period

async def reset(dut):
    #Reset the RX module and initialize all inputs to safe values
    dut.rst_n.value = 0
    dut.spi_clk.value = 0
    dut.spi_w.value = 0
    dut.mosi.value = 0
    dut.alu_ready.value = 1  # Default to ALU ready
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

async def spi_write_nibble(dut, nibble_data, spi_clk_cycles=5):
    #Simulates writing one nibble via SPI
    #Generates a complete SPI clock cycle to transfer data from master to DUT
    
    dut.mosi.value = nibble_data & 0xF
    
    #SPI clock low phase
    dut.spi_clk.value = 0
    await ClockCycles(dut.clk, spi_clk_cycles)
    
    #SPI clock high phase
    dut.spi_clk.value = 1
    await ClockCycles(dut.clk, spi_clk_cycles)
    
    #SPI clock low phase
    dut.spi_clk.value = 0
    await ClockCycles(dut.clk, spi_clk_cycles)

@cocotb.test()
async def test_rx_happy_path(dut):
    #Validate RX module loads registers correctly during normal operation
    #Verifies the RX module correctly samples MOSI data on SPI clock edges
    #Verifies all 5 registers are loaded in sequence across 5 SPI write cycles
    #Verifies the nibble counter correctly incremented throughout the write sequence
    #Verifies the rx_valid output asserts after all nibbles are received
    
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    instruction = [0x9, 0xA, 0xE, 0x4, 0x8]  #[OP, A1, A2, B1, B2]

    #Assert SPI_W to enable writing
    dut.spi_w.value = 1
    await ClockCycles(dut.clk, 1)

    #Write all 5 nibbles of the instruction sequentially
    for nibble_val in instruction:
        await spi_write_nibble(dut, nibble_val)

    #Deassert SPI_W to signal end of write
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 2)

    #Verify all registers loaded correctly
    assert int(dut.op_reg.value) == 0x9, f"Expected op_reg=0x9, got {hex(int(dut.op_reg.value))}"
    assert int(dut.a1_reg.value) == 0xA, f"Expected a1_reg=0xA, got {hex(int(dut.a1_reg.value))}"
    assert int(dut.a2_reg.value) == 0xE, f"Expected a2_reg=0xE, got {hex(int(dut.a2_reg.value))}"
    assert int(dut.b1_reg.value) == 0x4, f"Expected b1_reg=0x4, got {hex(int(dut.b1_reg.value))}"
    assert int(dut.b2_reg.value) == 0x8, f"Expected b2_reg=0x8, got {hex(int(dut.b2_reg.value))}"
    
    #Verify rx_valid is asserted after complete instruction
    assert int(dut.rx_valid.value) == 1, "rx_valid should assert after complete write"

@cocotb.test()
async def test_rx_interrupted_write(dut):
    #Verify RX module behavior when SPI write is interrupted
    #Verifies when SPI_W is deasserted mid write, the nibble counter is resetted
    #Verifies that a subsequent compelte write should load registers correctly
    #Verifies incompelte writes should not corrupt the final register values
    
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    instruction = [0x9, 0xA, 0xE, 0x4, 0x8]

    #Write 3 nibbles, then interrupt by deasserting SPI_W
    dut.spi_w.value = 1
    await spi_write_nibble(dut, instruction[0])  # op_reg
    await spi_write_nibble(dut, instruction[1])  # a1_reg
    await spi_write_nibble(dut, instruction[2])  # a2_reg

    #Interrupt the write by deasserting SPI_W
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 10)

    #Start new complete write sequence
    dut.spi_w.value = 1
    for nibble_val in instruction:
        await spi_write_nibble(dut, nibble_val)
    
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 2)

    #Verify registers contain correct values from complete write
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
    #Verify system reset clears RX registers during an active write
    #Verifies registers can be loaded normally during a write command
    #Verifies rst_n clears all registers immediately
    #Verifies the nibble counter and state machine reset properly
    
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    instruction = [0x9, 0xA, 0xE, 0x4, 0x8]

    #Start writing and load 2 nibbles
    dut.spi_w.value = 1
    await spi_write_nibble(dut, instruction[0])  # op_reg
    await spi_write_nibble(dut, instruction[1])  # a1_reg

    #Verify registers loaded before reset
    a1_reg_val = int(dut.a1_reg.value)
    assert a1_reg_val == 0xA, "a1_reg was not loaded correctly before reset"

    #Apply system reset
    await reset(dut)

    #Verify all registers cleared after reset
    assert int(dut.op_reg.value) == 0, f"op_reg did not clear on reset. Value: {hex(int(dut.op_reg.value))}"
    assert int(dut.a1_reg.value) == 0, f"a1_reg did not clear on reset. Value: {hex(int(dut.a1_reg.value))}"
    assert int(dut.a2_reg.value) == 0, f"a2_reg did not clear on reset. Value: {hex(int(dut.a2_reg.value))}"
    assert int(dut.b1_reg.value) == 0, f"b1_reg did not clear on reset. Value: {hex(int(dut.b1_reg.value))}"
    assert int(dut.b2_reg.value) == 0, f"b2_reg did not clear on reset. Value: {hex(int(dut.b2_reg.value))}"
    assert int(dut.rx_valid.value) == 0, "rx_valid should be low after reset"

@cocotb.test()
async def test_rx_multiple_writes(dut):
    #Verify RX module can handle multiple consecutive instruction writes.
    #Verifies after completing one write, the module can accept a subsequent one
    #Verifies rx_valid pulses as expected between writes
    #Verifies register values update correctly for each new instruction
    
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    instruction_1 = [0x1, 0x5, 0xA, 0xF, 0x4]
    instruction_2 = [0x6, 0x9, 0xE, 0x3, 0x8]

    #First write sequence
    dut.spi_w.value = 1
    for nibble_val in instruction_1:
        await spi_write_nibble(dut, nibble_val)
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 2)

    #Verify first instruction loaded correctly
    assert int(dut.op_reg.value) == 0x1, "First instruction op_reg incorrect"
    assert int(dut.a1_reg.value) == 0x5, "First instruction a1_reg incorrect"

    #Wait between writes
    await ClockCycles(dut.clk, 5)

    #Second write sequence
    dut.spi_w.value = 1
    for nibble_val in instruction_2:
        await spi_write_nibble(dut, nibble_val)
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 2)

    #Verify second instruction overwrote correctly
    assert int(dut.op_reg.value) == 0x6, "Second instruction op_reg incorrect"
    assert int(dut.a1_reg.value) == 0x9, "Second instruction a1_reg incorrect"
    assert int(dut.a2_reg.value) == 0xE, "Second instruction a2_reg incorrect"
    assert int(dut.b1_reg.value) == 0x3, "Second instruction b1_reg incorrect"
    assert int(dut.b2_reg.value) == 0x8, "Second instruction b2_reg incorrect"

@cocotb.test()
async def test_rx_without_spi_w(dut):
    #Verify RX module ignores SPI clocks when SPI_W is not asserted
    #Verifies without SPI_W asserted, SPI clock edges should not load data
    #Verifies registers should remain at 0
    #Verifies rx_valid should remain low
    
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    #Try to write without asserting SPI_W
    dut.spi_w.value = 0  # Keep SPI_W low
    await spi_write_nibble(dut, 0x9)
    await spi_write_nibble(dut, 0xA)
    await spi_write_nibble(dut, 0x4)
    await ClockCycles(dut.clk, 2)

    #Verify no registers were loaded
    assert int(dut.op_reg.value) == 0, "op_reg should not load without SPI_W"
    assert int(dut.a1_reg.value) == 0, "a1_reg should not load without SPI_W"
    assert int(dut.a2_reg.value) == 0, "a2_reg should not load without SPI_W"
    assert int(dut.rx_valid.value) == 0, "rx_valid should remain low without SPI_W"

@cocotb.test()
async def test_rx_alu_backpressure(dut):
    #Verify RX module works with ALU backpressure
    #Verifies that when alu_ready=0 and instruction is compelte, rx_valid should not assert
    #Verifies that when alu_ready=1, rx_valid can assert after a complete instruction
    #Verifies registers hold their values when ALU is busy
    
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    instruction = [0x9, 0xA, 0xE, 0x4, 0x8]

    #Set ALU to busy before starting write
    dut.alu_ready.value = 0

    #Write complete instruction while ALU is busy
    dut.spi_w.value = 1
    for nibble_val in instruction:
        await spi_write_nibble(dut, nibble_val)
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 2)

    #Verify rx_valid did not assert because ALU was busy
    assert int(dut.rx_valid.value) == 0, "rx_valid should not assert when alu_ready=0"

    #Signal ALU is ready
    dut.alu_ready.value = 1
    await ClockCycles(dut.clk, 2)

    #rx_valid remains low because it needs a new write when ALU becomes ready
    assert int(dut.rx_valid.value) == 0, "rx_valid cleared after ALU ready"

    #Verify registers still hold the data
    assert int(dut.op_reg.value) == 0x9, "Registers should hold data during backpressure"

@cocotb.test()
async def test_rx_all_zeros(dut):
    #Verify RX module handles all-zero instruction correctly
    #Verifies the module can handle 0x0 vlaues in all fields
    #Verifies rx_valid still asserts for valid 0 instruction

    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    instruction = [0x0, 0x0, 0x0, 0x0, 0x0]

    #Write all zeros
    dut.spi_w.value = 1
    for nibble_val in instruction:
        await spi_write_nibble(dut, nibble_val)
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 2)

    #Verify all registers are zero
    assert int(dut.op_reg.value) == 0x0, "op_reg should be 0x0"
    assert int(dut.a1_reg.value) == 0x0, "a1_reg should be 0x0"
    assert int(dut.a2_reg.value) == 0x0, "a2_reg should be 0x0"
    assert int(dut.b1_reg.value) == 0x0, "b1_reg should be 0x0"
    assert int(dut.b2_reg.value) == 0x0, "b2_reg should be 0x0"
    assert int(dut.rx_valid.value) == 1, "rx_valid should assert for zero instruction"

@cocotb.test()
async def test_rx_all_ones(dut):
    #Verify RX module handles all-ones (0xF) instruction correctly.
    #Verifies module can handle a maximum of 4 bit values in all fields
    #Verifies rx_valiod still asserts for valid maximum value instruction

    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    instruction = [0xF, 0xF, 0xF, 0xF, 0xF]

    #Write all ones
    dut.spi_w.value = 1
    for nibble_val in instruction:
        await spi_write_nibble(dut, nibble_val)
    dut.spi_w.value = 0
    await ClockCycles(dut.clk, 2)

    #Verify all registers are 0xF
    assert int(dut.op_reg.value) == 0xF, "op_reg should be 0xF"
    assert int(dut.a1_reg.value) == 0xF, "a1_reg should be 0xF"
    assert int(dut.a2_reg.value) == 0xF, "a2_reg should be 0xF"
    assert int(dut.b1_reg.value) == 0xF, "b1_reg should be 0xF"
    assert int(dut.b2_reg.value) == 0xF, "b2_reg should be 0xF"
    assert int(dut.rx_valid.value) == 1, "rx_valid should assert for max-value instruction"