`default_nettype none
`timescale 1ns / 1ps

/* Testbench: instantiates the design and gives every pin a readable name
   so test.py can drive / watch them individually.
*/
module tb ();

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;        // deadtime code in pin mode

  // uio inputs, one reg per pin
  reg pwm;
  reg sck;
  reg cs_n;
  reg mosi;
  reg mode;
  reg en_pin;
  reg cal_pin;
  reg sel_pin;
  wire [7:0] uio_in = {sel_pin, cal_pin, en_pin, mode, mosi, cs_n, sck, pwm};

  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  wire out_h   = uo_out[0];
  wire out_l   = uo_out[1];
  wire miso    = uo_out[2];
  wire cal_out = uo_out[3];

`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  tt_um_jliang2_pwm_deadtime user_project (

      // Include power ports for the Gate Level test:
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif

      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );

endmodule
