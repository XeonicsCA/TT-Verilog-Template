<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This 1x1 tile is a tiny math-accelerator built around a 4-bit ALU pipeline.  
A host device talks to it over a simple SPI-style interface using the TinyTapeout pins.

Each operation is encoded as a 20-bit “instruction word”:

- 4 bits of opcode: which math operation to run (dot product, vector add/sub, sum of squares, distance², 2×2 determinant, scalar multiply, lerp, etc.)
- 4 × 4-bit operands: `a1`, `a2`, `b1`, `b2`

The host sends this instruction 4 bits at a time on `ui_in[3:0]` while toggling:

- `uio_in[0]` – SPI clock  
- `uio_in[1]` – write strobe (load data into the RX stage)

After 5 nibbles, the **RX stage** has a complete instruction and asserts a valid signal to the **decode stage**.  
The **decode stage**:

- Reads the opcode and selects which math operation to perform  
- Routes the four 4-bit operands into two internal “lanes” (X and Y)  
- Generates an `alu_ctrl_t` control signal package that is used to configure the ALU (pre-add, multiply mode, post-add/concat, add vs sub, etc.)
- Sends a valid command to the **ALU stage** when the ALU indicates it is ready

The **ALU stage** is a single-cycle 4-bit core with:

- Per lane pre-adders (for adding or subtracting operand pairs)
- Per lane multiplier blocks that can multiply, square, or pass values through
- A combined post-stage that either concatenates the two lanes or adds/subtracts them

By enabling or bypassing these blocks, different opcodes implement functionality such as:

- `DOT2` – 2D dot product  
- `VADD2` / `VSUB2` – vector add/sub  
- `SUMSQ`, `DIST2`, `DIFFSQ` – sum of squares / distance² / squared difference  
- `DET2` – 2×2 determinant  
- `SCMUL`, `WSUM`, `PROJU`, `LERPX`, `LERPY` – scalar multiply, weighted sums, projection, and simple linear interpolation

The ALU produces a 10-bit result plus a carry flag, which are stored in a small output register.  

The **TX stage** then serializes this result back to the host:

- Result bits are packed into 4-bit chunks and driven on `uo_out[3:0]`
- The carry flag is exposed on `uio_out[3]`
- The host clocks the data out using `uio_in[0]` (SPI clock) and `uio_in[2]` (read enable)

All stages use valid/ready handshakes, so if the host stops reading results, backpressure propagates and the ALU will stop accepting new commands without losing any results.

## How to test

Explain how to use your project

## External hardware

List external hardware used in your project (e.g. PMOD, LED display, etc), if any
