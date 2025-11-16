# SPDX-License-Identifier: Apache-2.0
# Unit tests for tx_4b module via the tx_tb_4b wrapper.
# These focus on SPI read behavior, result serialization, and handshaking.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, ReadOnly

CLK_NS = 10  # 100 MHz
SPI_CLK_CYCLES = 5  # Number of system clocks per half SPI clock period

async def reset(dut):
    """Reset the TX module."""
    dut.rst_n.value = 0
    dut.spi_clk.value = 0
    dut.spi_r.value = 0
    dut.res_data.value = 0
    dut.carry_in.value = 0
    dut.res_valid.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

async def send_result_to_dut(dut, data, carry):
    """Simulates the ALU sending a new result to the TX module."""
    dut.res_data.value = data
    dut.carry_in.value = carry
    
    # Wait until TX module is ready to accept data
    while int(dut.res_ready.value) == 0:
        await RisingEdge(dut.clk)
        
    # Send the data for one cycle
    dut.res_valid.value = 1
    await RisingEdge(dut.clk)
    dut.res_valid.value = 0

async def spi_read_nibble(dut):
    """Simulates the SPI master clocking out one nibble and returns MISO."""
    
    # SPI clock low
    dut.spi_clk.value = 0
    await ClockCycles(dut.clk, SPI_CLK_CYCLES)
    
    # SPI clock high (DUT reads this as rising edge)
    dut.spi_clk.value = 1
    
    await ReadOnly()
    miso_val = int(dut.miso.value)
    
    await ClockCycles(dut.clk, SPI_CLK_CYCLES) 
    
    # End on SPI clock low (DUT reads this as falling edge)
    dut.spi_clk.value = 0
    
    # Wait just one cycle for the DUT's registered logic to see the falling edge
    await ClockCycles(dut.clk, 1) 
    
    return miso_val

@cocotb.test()
async def test_tx_happy_path(dut):
    """Validate TX module correctly serializes a result.
    
    Expected packing:
    Data = 0x3A5 (0b11 1010 0101)
    Carry = 1
    
    Nibble 0: res[3:0]  = 0b0101 = 0x5
    Nibble 1: res[7:4]  = 0b1010 = 0xA
    Nibble 2: {res[9:8], carry, 1'b0} = {0b11, 1, 0} = 0b1110 = 0xE
    Nibble 3: 0x0 (Reserved)
    Nibble 4: 0x0 (Reserved)
    """
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await reset(dut)
    
    # Check that res_ready is high after reset
    assert int(dut.res_ready.value) == 1, "res_ready should be high after reset"

    # Send result from "ALU"
    await send_result_to_dut(dut, 0x3A5, 1)
    
    # After capturing, res_ready should go low (if not already reading)
    await RisingEdge(dut.clk)
    assert int(dut.res_ready.value) == 0, "res_ready should go low after capturing result"

    # Start SPI read
    dut.spi_r.value = 1
    
    # After spi_r=1, tx_active goes high, which should make res_ready high again
    await RisingEdge(dut.clk)
    assert int(dut.res_ready.value) == 1, "res_ready should go high once tx_active"
    
    # Read all 5 nibbles
    n0 = await spi_read_nibble(dut)
    n1 = await spi_read_nibble(dut)
    n2 = await spi_read_nibble(dut)
    n3 = await spi_read_nibble(dut)
    n4 = await spi_read_nibble(dut) # This call returns right after the 5th falling edge
    
    assert n0 == 0x5, f"Nibble 0 incorrect: expected 0x5, got {hex(n0)}"
    assert n1 == 0xA, f"Nibble 1 incorrect: expected 0xA, got {hex(n1)}"
    assert n2 == 0xE, f"Nibble 2 incorrect: expected 0xE, got {hex(n2)}"
    assert n3 == 0x0, f"Nibble 3 incorrect: expected 0x0, got {hex(n3)}"
    assert n4 == 0x0, f"Nibble 4 incorrect: expected 0x0, got {hex(n4)}"

    # Check tx_done pulse.
    assert int(dut.tx_done.value) == 1, "tx_done should be high after 5th nibble"
    
    # Now advance one clock and check that it pulsed low
    await RisingEdge(dut.clk)
    assert int(dut.tx_done.value) == 0, "tx_done should pulse low after one cycle"
    
    dut.spi_r.value = 0

@cocotb.test()
async def test_tx_no_spi_r(dut):
    """Verify TX module does not transmit if spi_r is low."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await reset(dut)
    
    await send_result_to_dut(dut, 0x123, 0)
    
    dut.spi_r.value = 0 # Ensure read is disabled
    
    # Try to "read" a nibble (spi_clk still toggles, but spi_r=0)
    n0 = await spi_read_nibble(dut)
    
    assert n0 == 0x0, "MISO should remain 0 when spi_r is low"
    assert int(dut.tx_done.value) == 0, "tx_done should not assert when spi_r is low"

@cocotb.test()
async def test_tx_alu_backpressure(dut):
    """Verify res_ready signal correctly applies backpressure."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await reset(dut)
    
    # 1. Send first result. res_ready should be 1.
    assert int(dut.res_ready.value) == 1, "res_ready should be 1 at start"
    await send_result_to_dut(dut, 0x111, 1)
    
    # 2. After capture, res_ready goes 0 (tx_active is 0)
    await RisingEdge(dut.clk)
    assert int(dut.res_ready.value) == 0, "res_ready should be 0 (backpressure)"
    
    # 3. Try to send a second result. It should stall.
    dut.res_data.value = 0x222
    dut.carry_in.value = 0
    dut.res_valid.value = 1
    await ClockCycles(dut.clk, 5) # Wait a few cycles
    
    # 4. Check that res_ready is still 0
    assert int(dut.res_ready.value) == 0, "res_ready should remain 0"
    
    # 5. Start reading. This makes tx_active=1, which makes res_ready=1
    dut.spi_r.value = 1
    await RisingEdge(dut.clk) # Let tx_active propogate
    assert int(dut.res_ready.value) == 1, "res_ready should be 1 once tx_active"
    
    # 6. The second result should NOT be captured yet, as tx_active is high
    await RisingEdge(dut.clk)
    dut.res_valid.value = 0 # ALU stops sending
    
    # 7. Read out all 5 nibbles of the *first* result (0x111)
    n0 = await spi_read_nibble(dut)
    n1 = await spi_read_nibble(dut)
    n2 = await spi_read_nibble(dut)
    n3 = await spi_read_nibble(dut)
    n4 = await spi_read_nibble(dut)

    assert n0 == 0x1, "Should have read 0x1 from first result"
    assert n2 == 0x6, "Should have read 0x6 ({01, 1, 0}) from first result"

    # 8. tx_done pulses, tx_active goes low.
    await RisingEdge(dut.clk)
    assert int(dut.tx_done.value) == 0, "tx_done should be low"
    
    # [FIX] This is the line that was wrong.
    # We must access the internal signal 'tx_active' via 'dut.dut.tx_active'
    assert int(dut.dut.tx_active.value) == 0, "tx_active should be low"
    
    dut.spi_r.value = 0
    
    # Wait for the module to be non-busy before sending the next value.
    while int(dut.res_ready.value) == 0:
        await RisingEdge(dut.clk)

    # 9. Now that tx is done and res_ready=1, send the second result.
    await send_result_to_dut(dut, 0x222, 0)
    
    # 10. Check that the module is now busy (holding 2nd result)
    await RisingEdge(dut.clk)
    assert int(dut.res_ready.value) == 0, "res_ready should be 0, holding 2nd result"

    # 11. Read the second result to verify it was captured
    dut.spi_r.value = 1
    n0_2 = await spi_read_nibble(dut)
    assert n0_2 == 0x2, "Failed to capture second result after backpressure"

@cocotb.test()
async def test_tx_reset_during_tx(dut):
    """Verify reset clears state during an active transmission."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await reset(dut)
    
    # Use a 10-bit value (0x2BC = 0b10 1011 1100)
    await send_result_to_dut(dut, 0x2BC, 1)
    
    dut.spi_r.value = 1
    
    # Read two nibbles
    n0 = await spi_read_nibble(dut)
    n1 = await spi_read_nibble(dut)
    
    # Assertions for 0x2BC
    assert n0 == 0xC, "Nibble 0 incorrect before reset" # 0b1100
    assert n1 == 0xB, "Nibble 1 incorrect before reset" # 0b1011
    
    # Apply reset
    await reset(dut)
    
    # Check that state is cleared
    assert int(dut.res_ready.value) == 1, "res_ready should be 1 after reset"
    assert int(dut.miso.value) == 0, "miso should be 0 after reset"
    assert int(dut.tx_done.value) == 0, "tx_done should be 0 after reset"
    
    # Try reading again, should just get 0s
    dut.spi_r.value = 1
    n2 = await spi_read_nibble(dut)
    assert n2 == 0x0, "miso should remain 0 after reset"

@cocotb.test()
async def test_tx_carry_out(dut):
    """Verify carry_out just passes through carry_in."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await reset(dut)

    # Test carry = 1
    dut.carry_in.value = 1
    await ClockCycles(dut.clk, 1)
    assert int(dut.carry_out.value) == 1, "carry_out should be 1"

    # Test carry = 0
    dut.carry_in.value = 0
    await ClockCycles(dut.clk, 1)
    assert int(dut.carry_out.value) == 0, "carry_out should be 0"