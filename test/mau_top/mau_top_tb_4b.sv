//Testbench wrapper for mau_top_4b module

`default_nettype none
`timescale 1ns / 1ps

module mau_top_tb_4b ();
    //Declare testbench signals to connect to Device Under Test (DUT)
    reg        clk;        //System clock
    reg        rst_n;      //Active low reset
    reg        ena;        //Enable signal
    reg  [7:0] ui_in;      //Dedicated inputs (MOSI data)
    reg  [7:0] uio_in;     //Bidirectional IOs input path (SPI control signals)
    wire [7:0] uo_out;     //Dedicated outputs (MISO data)
    wire [7:0] uio_out;    //Bidirectional IOs output path (carry output)
    wire [7:0] uio_oe;     //Bidirectional IOs enable path

    //Gate-level test power supply nets
    `ifdef GL_TEST
    wire VPWR = 1'b1;
    wire VGND = 1'b0;
    `endif

    //Instantiate the TinyTapeout user module (MAU top)
    tt_um_mau_top_4b user_project (
        `ifdef GL_TEST
        .VPWR (VPWR),      //Power supply for gate level simulation
        .VGND (VGND),      //Ground for gate level simulation
        `endif
        .ui_in  (ui_in),   //Dedicated inputs (MOSI[7:0])
        .uo_out (uo_out),  //Dedicated outputs (MISO[7:0])
        .uio_in (uio_in),  //IOs: Input path (SPI control signals)
        .uio_out(uio_out), //IOs: Output path (carry output)
        .uio_oe (uio_oe),  //IOs: Enable path (active high: 0=input, 1=output)
        .ena    (ena),     //enable, goes high when design is selected
        .clk    (clk),     //clock
        .rst_n  (rst_n)    //active low reset
    );

    //Generate VCD waveform dump for debugging if VCD_PATH is defined
    `ifdef VCD_PATH
    initial begin
        $dumpfile(`VCD_PATH);
        $dumpvars(0, mau_top_tb_4b);
    end
    `endif

endmodule

`default_nettype wire