/*
 * Copyright (c) 2026
 * SPDX-License-Identifier: Apache-2.0
 *
 * PWM -> complementary outputs with programmable deadtime.
 *
 * Pins
 *   ui_in[7:0]  deadtime code in pin mode (both edges), e.g. on-board DIP switches
 *   uio[0]      PWM input
 *   uio[1]      SPI SCK
 *   uio[2]      SPI CS_n
 *   uio[3]      SPI MOSI
 *   uio[4]      MODE    0 = SPI registers, 1 = pin mode
 *   uio[5]      EN      output enable   (pin mode)
 *   uio[6]      CAL     calibration     (pin mode)
 *   uio[7]      CAL_SEL 0 = line A, 1 = line B (pin mode)
 *   uo_out[0]   OUT_H
 *   uo_out[1]   OUT_L
 *   uo_out[2]   SPI MISO
 *   uo_out[3]   calibration output (divided ring oscillator)
 */

`default_nettype none

module tt_um_jliang2_pwm_deadtime (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  wire pwm      = uio_in[0];
  wire sck      = uio_in[1];
  wire cs_n     = uio_in[2];
  wire mosi     = uio_in[3];
  wire pin_mode = uio_in[4];
  wire en_pin   = uio_in[5];
  wire cal_pin  = uio_in[6];
  wire sel_pin  = uio_in[7];

  // ---------------- SPI registers ----------------
  wire [7:0] reg_rise, reg_fall, reg_ctrl;
  wire       miso;

  dt_spi spi (
      .clk    (clk),
      .rst_n  (rst_n),
      .sck    (sck),
      .cs_n   (cs_n),
      .mosi   (mosi),
      .miso   (miso),
      .dt_rise(reg_rise),
      .dt_fall(reg_fall),
      .ctrl   (reg_ctrl)
  );

  // ---------------- mode select ----------------
  wire [7:0] code_rise = pin_mode ? ui_in   : reg_rise;
  wire [7:0] code_fall = pin_mode ? ui_in   : reg_fall;
  wire       out_en    = pin_mode ? en_pin  : reg_ctrl[0];
  wire       cal_en    = pin_mode ? cal_pin : reg_ctrl[1];
  wire       cal_sel   = pin_mode ? sel_pin : reg_ctrl[2];
  wire [2:0] div_sel   = pin_mode ? 3'd0    : reg_ctrl[5:3];

  // ---------------- deadtime core ----------------
  wire out_h, out_l, cal_out;

  dt_core core (
      .pwm_in   (pwm),
      .code_rise(code_rise),
      .code_fall(code_fall),
      .out_en   (out_en),
      .cal_en   (cal_en),
      .cal_sel  (cal_sel),
      .div_sel  (div_sel),
      .out_h    (out_h),
      .out_l    (out_l),
      .cal_out  (cal_out)
  );

  assign uo_out  = {4'b0000, cal_out, miso, out_l, out_h};
  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;    // all uio pins are inputs

  wire _unused = &{ena, reg_ctrl[7:6], 1'b0};

endmodule
