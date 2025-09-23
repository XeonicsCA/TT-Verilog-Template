<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

<img src="./img/blockdiagram_v1.png" alt="Initial Proposal Block Diagram" width="2259">

## Project Description

blah blah blah bleh bleh bleh bloo bloo bloo

## TT I/O Assignments

Convert the table in the block diagram into text, will be used in the future

## Project Work Schedule

Verilog coding and timing verification using CocoTB - Now until Oct 22 (4 weeks time)
    - Finalize block diagram with control signals (1 week?)
    - Decide how to split up work (RX/TX stages should be similar, M/A stage logic should be standardized, Decode stage might be more difficult depending on finalized ctrl signals)
    - Code in verilog individual components (2 weeks?)
    - Verify timing using CocoTB (1 week? not sure if this can be done individually or needs to be all together)

Task 2: Sub-block (verilog) evaluation - Oct 22

Synthesis and verification with OpenLane and CocoTB - Oct 22 until Nov 12 (3 weeks time)
    - Unsure how this is done, will know more as project progresses
    - Guessing some work needs to be done to turn our verilog logic blocks into the standard cell designs provided by TT and deciding placement within the tile, and then verification
    - 1 week synthesis 2 weeks verification/fixing?

Task 3: System integration - Nov 12
    - Clean up any loose ends

Final verification - Nov 19
    - Just some documentation left

Completed documentation and github - Nov 26
    - Done by this point, project should be ready for tapeout

Evaluation of final submissions and docs - Dec 3
    - Submission for tapeout