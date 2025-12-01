
<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

<img src="./img/blockdiagram_v2.png" alt="Initial Proposal Block Diagram" width="2259">

## Project Description

This project implements a Math Accelerator Unit (MAU) in SystemVerilog, designed for integration on a TinyTapeout chip. The MAU is a specialized hardware block that performs selected mathematical operations faster and more efficiently than a general purpose CPU. In a typical system, the CPU can offload arithmetic heavy tasks to the MAU, improving overall performance while freeing CPU resources for other operations.

To implement some speedup to differentiate the MAU from a typical CPU, our design has parallel adders and multipliers to enable 2 lane Single Instruction/Multiple Data (SIMD2). This will be the main source of the speedup observed in the MAU, compared to the single ALU datapath of a traditional CPU.

The MAU supports vector, matrix, polynomial, and scalar arithmetic operations. By integrating these capabilities into a dedicated hardware datapath, the design demonstrates how specialized accelerators can improve throughput for math intensive workloads while remaining resource efficient in a constrained silicon environment.

## TT I/O Assignments

| Signal       | Description                       |
|--------------|-----------------------------------|
| `ui_in[7:0]` | Instruction / Operand input       |
| `ui_out[7:0]`| Result output                     |
| `uio[3:0]`   | SPI_clk, SPI_W, SPI_R, RES_CARRY  |
| `rst_n`      | Global TT reset                   |
| `clk`        | TT clock                          |

## Math Operations

| Formula                                                         | Operation | Description                      | Signals                                                                   |
| --------------------------------------------------------------- | --------- | -------------------------------- | ------------------------------------------------------------------------- |
| x<sub>0</sub>x<sub>1</sub> + y<sub>0</sub>y<sub>1</sub>         | `DOT2`    | 2x1 vector dot product           | N/A                                                                       |
| x<sub>0</sub>a + y<sub>0</sub>b                                 | `WSUM`    | Weighted sum                     | N/A                                                                       |
| x<sub>0</sub>ûx + y<sub>0</sub>ûy                             | `PROJU`   | Projection onto unit vector      | N/A                                                                       |
| x<sub>0</sub>x<sub>1</sub> - y<sub>0</sub>y<sub>1</sub>         | `DIFF2`   | Difference of products           | post sub                                                                  |
| x<sub>0</sub>x<sub>1</sub> + y<sub>0</sub>y<sub>1</sub>         | `SQM`     | Squared magnitude                | N/A                                                                       |
| x<sub>0</sub>y<sub>1</sub> - y<sub>0</sub>x<sub>1</sub>         | `DET2`    | 2x2 matrix determinant           | post sub                                                                  |
| (x<sub>0</sub>−x<sub>1</sub>)² − (y<sub>0</sub>−y<sub>1</sub>)² | `DIST2`   | Squared distance                 | X and Y lane pre sub, mul_sel (repeat), post sub                          |
| ax + b                                                          | `POLY`    | First degree polynomial          | Y lane mul_sel (1/skip)                                                   |
| x<sub>0</sub>+y<sub>0</sub> , x<sub>1</sub>+y<sub>1</sub>       | `VADD2`   | Adds two 2x1 vectors             | mul_sel (1/skip), post add skip                                           |
| x<sub>0</sub>−y<sub>0</sub> , x<sub>1</sub>−y<sub>1</sub>       | `VSUB2`   | Subtracts two 2x1 vectors        | 2x pre sub, mul_sel (1/skip), post skip                                   |
| x<sub>0</sub>x<sub>1</sub> , y<sub>0</sub>y<sub>1</sub>         | `SCMUL`   | Scalar multiplication (in pairs) | post skip                                                                 |
| x<sub>0</sub>c , x<sub>1</sub>c                                 | `SCALE2`  | Scale a 2x1 vector by a scalar   | post skip                                                                 |
| x<sub>0</sub>c + x<sub>1</sub>c                                 | `SCSUM`   | Scaled sum                       | N/A                                                                       |
| x<sub>0</sub> + c(y<sub>1</sub>−y<sub>0</sub>)                  | `LERPX`   | Linear interpolation in lane X   | X lane pre (0/skip) and mul_sel (1/skip), Y lane mul_sel (c, from X lane) |
| y<sub>0</sub> + c(x<sub>1</sub>−x<sub>0</sub>)                  | `LERPY`   | Linear interpolation in lane Y   | Y lane pre (0/skip) and mul_sel (1/skip), X lane mul_sel (c, from Y lane) |


## System Architecture

Instructions consist of 40-bits - 8-bits for the opcode/flags and 8-bits for each of the four operands.

Due to the pin limitations of TinyTapeout, the input bus ui_in[7:0] is 8-bits wide and reading in the 40-bit instruction from the SPI's MOSI lanes is done in byte increments across 5 SPI clock cycles. The output bus ui_out[7:0] operates in a similar fashion by sending out 8-bits of the result at a time back through the SPI's MISO lanes. The uio[3:0] bidirectional pins carry the SPI control and data signals.

A custom 20 pin "parallel" SPI interface will be used to accomodate the 8 lane MOSI, 8 lane MISO, and single lane SPI_clk, SPI_W, SPI_R, RES_CARRY. Both write and read signals will be used to enable a true idle state.

As not all 8-bits of the opcode are required, 4 or so bits will be reserved for flags that can be used for control signals (such as accumulate_en, QNotation_en, X_en, Y_en).

RX Stage:

Implemented using an 8-bit RX register and 1:5 demux, the RX register samples MOSI[7:0] on SPI_CLK when SPI_W is active and a MOD-5 counter controls the demux output. The demux will then direct data to the correct lane registers where they are held until all operands have been saved. 

Decode Stage:

The lane registers holding the operands will then be fed into the correct ALU inputs with pathing determined by a FSM or LUT, activating control signals based on the opcode. Any flags provided in the opcode will also be directed here to the corresponding hardware it enables/disables.

ALU Stage:

The two lanes, denoted X and Y, will both consist of an 8-bit pre-add/sub followed by a 9x9-bit multiplier. Control signals will control data forwarding paths that enable different inputs into the adder/multiplier depending on the operation being performed. This unlocks operations that fixed data paths wouldn't be able to perform (such as squaring sums/differences).

After the multiplier, the two lanes converge into an 18-bit adder to calculate the final result. Once again, data forwarding paths can be used to bypass the reducer and output a 2-element vector output. The value is then stored into a result register that doubles as an accumulator register for consecutive 18-bit adds.

TX Stage:

Similar to the RX stage, the TX stage is implemented using 3-5 (depending on output clock cycle count) 8-bit TX registers and a 5:1 mux. The 5:1 mux outputs to MISO[7:0] on SPI_CLK when SPI_R is active, sending the final result across multiple 8-bit chunks. The maximum output size, given four 8-bit inputs going through an add -> multiply -> add, is 18 bits with a carry. Since only 8 bits are available on the output bus, results are serialized in the same wave-based manner. Encoding for the result will be fixed and will require sending 8-bits across another 3-5 SPI clock cycles to return the full result. (Requirement of symmetric RX/TX cycles to be determined)

## Project Work Schedule

Verilog coding and timing verification using CocoTB - Now until Oct 29 (4 weeks time)
 - Finalize block diagram with control signals (1 week)
 - Split up work (RX/TX stages should be similar, M/A stage logic should be standardized, Decode stage might be more difficult depending on finalized ctrl signals)
 - Code in verilog individual components (1 week)
 - Verify timing using CocoTB (1 week? using github actions?)

Task 2: Sub-block (verilog) evaluation - Oct 29 <br>

Synthesis and verification with OpenLane and CocoTB - Oct 29 until Nov 19 (3 weeks time)
 - Update test.py?
 - Unsure about this workflow, will know more as project progresses
 - Work needs to be done to turn verilog modules into the standard cell designs provided by TT? and deciding placement within the tile, and then verification?
 - 1 week synthesis, 2 weeks verification/fixing?

Task 3: System integration - Nov 19
 - Clean up any loose ends

Final verification, completed documentation and github - Nov 26
 - Wrap up documentation and submission

Evaluation of final submissions and docs - Dec 3
 - Submit for tapeout

## How to Test

This section provides a basic example of how to interact with the MAU hardware once it's fabricated on the TinyTapeout chip. The code snippet demonstrates loading a 40-bit instruction and reading the result through the SPI-like interface.

```python
def send_instruction(tt, opcode, operands):
    #Load a 40-bit instruction into the MAU over 5 SPI clock cycles.
    #Args:
    #    tt: TinyTapeout interface object
    #    opcode: 8-bit operation code (e.g., 0x01 for DOT2)
    #    operands: List of four 8-bit operands [x0, x1, y0, y1]
    
    #Pack instruction into 5 bytes: [opcode, x0, x1, y0, y1]
    instruction_bytes = [opcode] + operands
    
    #Send each byte sequentially over the 8-bit input bus
    for byte in instruction_bytes:
        tt.input_byte = byte           #Place byte on ui_in[7:0]
        tt.uio.SPI_W = 1               #Assert write enable signal
        tt.clock_tick()                #Rising edge of SPI_clk to latch data
        tt.uio.SPI_W = 0               #Deassert write enable
    
def read_result(tt, num_bytes=3):
    #Read the result from the MAU over multiple SPI clock cycles.
    #Args:
    #    tt: TinyTapeout interface object
    #    num_bytes: Number of 8-bit chunks to read (3-5 depending on result size)
    #Returns:
    #    List of bytes representing the result (LSB first)

    result_bytes = []
    
    #Read each byte of the result sequentially
    for _ in range(num_bytes):
        tt.uio.SPI_R = 1                     #Assert read enable signal
        tt.clock_tick()                      #Rising edge of SPI_clk to output next byte
        result_bytes.append(tt.output_byte)  #Capture byte from ui_out[7:0]
        tt.uio.SPI_R = 0                     #Deassert read enable
    
    return result_bytes

#Example usage: Compute 2x1 vector dot product (DOT2)
#Operation: x0*x1 + y0*y1 = 2*3 + 4*5 = 6 + 20 = 26
send_instruction(tt, opcode=0x01, operands=[2, 3, 4, 5])

#Read 3 bytes of result (18-bit result + carry spans 3 bytes)
result = read_result(tt, num_bytes=3)

#Reconstruct the full result from received bytes
final_result = result[0] | (result[1] << 8) | (result[2] << 16)
print(f"DOT2 result: {final_result}")  # Expected: 26
```

The MAU processes instructions through its custom SPI interface, reading operands in sequence and returning results across multiple clock cycles to accommodate the 18-bit output width on an 8-bit bus.
