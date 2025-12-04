# Unit tests for tx_4b module
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, ReadOnly

CLK_NS = 10  # 100MHz system clock period
SPI_CLK_CYCLES = 5  # Number of system clocks per half SPI clock period

async def reset(dut):
    #Reset TX module and initialize all inputs to safe values
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
    #Simulates the ALU sending a new result to the TX module
    
    #Wait for res_ready before sending
    dut.res_data.value = data
    dut.carry_in.value = carry
    
    #Wait until TX module is ready to accept data
    while int(dut.res_ready.value) == 0:
        await RisingEdge(dut.clk)
        
    #Send the data for one cycle
    dut.res_valid.value = 1
    await RisingEdge(dut.clk)
    dut.res_valid.value = 0

async def spi_read_nibble(dut):
    #Simulates the SPI master clocking out one nibble and returns MISO value
    #Generates a complete SPI clock and samples MISO on high phase
    
    #SPI clock low phase
    dut.spi_clk.value = 0
    await ClockCycles(dut.clk, SPI_CLK_CYCLES)
    
    #SPI clock high phase
    dut.spi_clk.value = 1
    
    #Sample MISO value in read only phase
    await ReadOnly()
    miso_val = int(dut.miso.value)
    
    await ClockCycles(dut.clk, SPI_CLK_CYCLES) 
    
    #End on SPI clock low
    dut.spi_clk.value = 0
    
    #Wait one cycle to see the falling edge
    await ClockCycles(dut.clk, 1) 
    
    return miso_val

@cocotb.test()
async def test_tx_happy_path(dut):
    #Validate TX module correctly serializes a result
    
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)
    
    #Check that res_ready is high after reset
    assert int(dut.res_ready.value) == 1, "res_ready should be high after reset"

    #Send result from simulated ALU
    await send_result_to_dut(dut, 0x3A5, 1)
    
    #After capturing, res_ready should go low
    await RisingEdge(dut.clk)
    assert int(dut.res_ready.value) == 0, "res_ready should go low after capturing result"

    #Start SPI read
    dut.spi_r.value = 1
    
    #After spi_r=1, tx_active goes high which should make res_ready high again
    await RisingEdge(dut.clk)
    assert int(dut.res_ready.value) == 1, "res_ready should go high once tx_active"
    
    #Read all 5 nibbles and verify correct serialization
    n0 = await spi_read_nibble(dut)
    n1 = await spi_read_nibble(dut)
    n2 = await spi_read_nibble(dut)
    n3 = await spi_read_nibble(dut)
    n4 = await spi_read_nibble(dut)
    
    #0x3A5, carry = 1
    # n0 = res[3:0] = 0x5
    # n1 = res[7:4] = 0xA
    # n2 = {0, carry, res[9:8]} = {0, 1, 0b11} = 0x7
    assert n0 == 0x5, f"Nibble 0 incorrect: expected 0x5, got {hex(n0)}"
    assert n1 == 0xA, f"Nibble 1 incorrect: expected 0xA, got {hex(n1)}"
    assert n2 == 0x7, f"Nibble 2 incorrect: expected 0x7, got {hex(n2)}"
    assert n3 == 0x0, f"Nibble 3 incorrect: expected 0x0, got {hex(n3)}"
    assert n4 == 0x0, f"Nibble 4 incorrect: expected 0x0, got {hex(n4)}"

    #Check tx_done pulse after all nibbles transmitted
    assert int(dut.tx_done.value) == 1, "tx_done should be high after 5th nibble"
    
    #Verify tx_done is a single cycle pulse
    await RisingEdge(dut.clk)
    assert int(dut.tx_done.value) == 0, "tx_done should pulse low after one cycle"
    
    dut.spi_r.value = 0

@cocotb.test()
async def test_tx_no_spi_r(dut):
    #Verify TX module does not transmit if spi_r is low.

    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)
    
    #Send data to TX module
    await send_result_to_dut(dut, 0x123, 0)
    
    dut.spi_r.value = 0 # Ensure read is disabled
    
    # Try to read a nibble
    n0 = await spi_read_nibble(dut)
    
    #MISO should remain 0 without read enable
    assert n0 == 0x0, "MISO should remain 0 when spi_r is low"
    assert int(dut.tx_done.value) == 0, "tx_done should not assert when spi_r is low"

@cocotb.test()
async def test_tx_alu_backpressure(dut):
    #Verify res_ready signal correctly applies backpressure to ALU.
    #Tests that TX module won't accept new data while holding a result that hasn't been transmitted yet

    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)
    
    #Send first result, res_ready should be 1 initially
    assert int(dut.res_ready.value) == 1, "res_ready should be 1 at start"
    await send_result_to_dut(dut, 0x111, 1)
    
    #After capture, res_ready goes 0
    await RisingEdge(dut.clk)
    assert int(dut.res_ready.value) == 0, "res_ready should be 0 (backpressure)"
    
    #Try to send a second result, it should stall
    dut.res_data.value = 0x222
    dut.carry_in.value = 0
    dut.res_valid.value = 1
    await ClockCycles(dut.clk, 5) #Wait a few cycles
    
    #Check that res_ready is still 0, means that the module isn't ready to accept yet
    assert int(dut.res_ready.value) == 0, "res_ready should remain 0"
    
    #Start reading, makes tx_active = 1, which makes res_ready = 1 
    dut.spi_r.value = 1
    await RisingEdge(dut.clk)
    assert int(dut.res_ready.value) == 1, "res_ready should be 1 once tx_active"
    
    #The second result should not be captured yet as tx_active is high
    await RisingEdge(dut.clk)
    dut.res_valid.value = 0 # ALU stops sending
    
    #Read out all 5 nibbles of the first result
    n0 = await spi_read_nibble(dut)
    n1 = await spi_read_nibble(dut)
    n2 = await spi_read_nibble(dut)
    n3 = await spi_read_nibble(dut)
    n4 = await spi_read_nibble(dut)

    #Verify we got the first result
    # res = 0x111, carry = 1
    # n0 = res[3:0] = 0x1
    # n2 = {0, carry, res[9:8]} = 0x5
    assert n0 == 0x1, "Should have read 0x1 from first result"
    assert n2 == 0x5, "Should have read 0x5 ({0, 1, 01}) from first result"

    #tx_done pulses, tx_active goes low.
    await RisingEdge(dut.clk)
    assert int(dut.tx_done.value) == 0, "tx_done should be low"
    
    #Access internal tx_active signal to verify state
    assert int(dut.dut.tx_active.value) == 0, "tx_active should be low"
    
    dut.spi_r.value = 0
    
    #Wait for the module to be ready before sending next value
    while int(dut.res_ready.value) == 0:
        await RisingEdge(dut.clk)

    #Once tx is done and res_ready=1, send second result
    await send_result_to_dut(dut, 0x222, 0)
    
    #Check that the module is now busy again, which means the second result is being held
    await RisingEdge(dut.clk)
    assert int(dut.res_ready.value) == 0, "res_ready should be 0, holding 2nd result"

    #Read the second result to verify it was captured correctly
    dut.spi_r.value = 1
    n0_2 = await spi_read_nibble(dut)
    assert n0_2 == 0x2, "Failed to capture second result after backpressure"

@cocotb.test()
async def test_tx_reset_during_tx(dut):
    #Verify reset clears state during an active transmission.
    #Tests that asserting reset mid-transmission properly clears all state.
    
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)
    
    #Use a 10 bit value
    await send_result_to_dut(dut, 0x2BC, 1)
    
    dut.spi_r.value = 1
    
    #Read two nibbles before resetting
    n0 = await spi_read_nibble(dut)
    n1 = await spi_read_nibble(dut)
    
    #Verify nibbles before reset
    assert n0 == 0xC, "Nibble 0 incorrect before reset" # 0b1100
    assert n1 == 0xB, "Nibble 1 incorrect before reset" # 0b1011
    
    #Apply reset mid transmission
    await reset(dut)
    
    #Check that all state is cleared after reset
    assert int(dut.res_ready.value) == 1, "res_ready should be 1 after reset"
    assert int(dut.miso.value) == 0, "miso should be 0 after reset"
    assert int(dut.tx_done.value) == 0, "tx_done should be 0 after reset"
    
    #Try reading again, should just get 0s so that no data is loaded
    dut.spi_r.value = 1
    n2 = await spi_read_nibble(dut)
    assert n2 == 0x0, "miso should remain 0 after reset"

@cocotb.test()
async def test_tx_carry_out(dut):
    #Verify carry_out just passes through carry_in.
    
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset(dut)

    # Test carry = 1
    dut.carry_in.value = 1
    await ClockCycles(dut.clk, 1)
    assert int(dut.carry_out.value) == 1, "carry_out should be 1"

    # Test carry = 0
    dut.carry_in.value = 0
    await ClockCycles(dut.clk, 1)
    assert int(dut.carry_out.value) == 0, "carry_out should be 0"