/*
 * Copyright (c) 2026
 * SPDX-License-Identifier: Apache-2.0
 *
 * Deadtime core: two delay lines, the deadtime gates, and the
 * ring-oscillator calibration path.
 *
 * Normal operation (cal_en = 0):
 *
 *   pwm_in --+--[mux]--[delay line A, code_rise]-- dA --+
 *            |                                          AND --> out_h =  pwm &  dA
 *            +--[mux]--[delay line B, code_fall]-- dB --+
 *                                                       AND --> out_l = ~pwm & ~dB
 *
 *   out_h turns ON code_rise LSBs after pwm rises, and OFF immediately when pwm falls.
 *   out_l turns ON code_fall LSBs after pwm falls, and OFF immediately when pwm rises.
 *   out_h and out_l can never be 1 at the same time (one needs pwm=1, the other pwm=0).
 *
 * Calibration (cal_en = 1, outputs forced off):
 *
 *   the selected line's input mux switches from pwm_in to a NAND feedback:
 *
 *     +--[mux]--[delay line]--+--> ring
 *     |                       |
 *     +-------[NAND]<---------+        NAND(cal, out) acts as an inverter
 *
 *   An odd number of inversions in a loop oscillates with
 *     period = 2 * (delay line + mux + NAND).
 *   The ring is divided by 2^(6+div_sel) with a ripple counter so the
 *   frequency is low enough for an output pin.
 */

`default_nettype none

module dt_core #(
    parameter UNIT_CELLS = 2
) (
    input  wire       pwm_in,
    input  wire [7:0] code_rise,
    input  wire [7:0] code_fall,
    input  wire       out_en,     // 1 = outputs enabled
    input  wire       cal_en,     // 1 = calibration mode (outputs forced off)
    input  wire       cal_sel,    // 0 = calibrate line A (rise), 1 = line B (fall)
    input  wire [2:0] div_sel,    // ring divider: 2^(6+div_sel)
    output wire       out_h,
    output wire       out_l,
    output wire       cal_out
);

  wire cal_a = cal_en & ~cal_sel;
  wire cal_b = cal_en &  cal_sel;

  // ---------------- line A (rising-edge deadtime, drives out_h) ----------------
  wire in_a, out_a, fb_a;

  sky130_fd_sc_hd__mux2_1 dt_keep_in_mux_a (.A0(pwm_in), .A1(fb_a), .S(cal_a), .X(in_a));

  dt_delay_line #(.UNIT_CELLS(UNIT_CELLS)) line_a (.in(in_a), .code(code_rise), .out(out_a));

  sky130_fd_sc_hd__nand2_1 dt_keep_fb_a (.A(cal_a), .B(out_a), .Y(fb_a));

  // ---------------- line B (falling-edge deadtime, drives out_l) ---------------
  wire in_b, out_b, fb_b;

  sky130_fd_sc_hd__mux2_1 dt_keep_in_mux_b (.A0(pwm_in), .A1(fb_b), .S(cal_b), .X(in_b));

  dt_delay_line #(.UNIT_CELLS(UNIT_CELLS)) line_b (.in(in_b), .code(code_fall), .out(out_b));

  sky130_fd_sc_hd__nand2_1 dt_keep_fb_b (.A(cal_b), .B(out_b), .Y(fb_b));

  // ---------------- deadtime gates ----------------
  wire active = out_en & ~cal_en;

  assign out_h = active &  pwm_in &  out_a;
  assign out_l = active & ~pwm_in & ~out_b;

  // ---------------- ring divider (ripple counter) ----------------
  // A ripple counter only needs each flip-flop to toggle, so it keeps working
  // at ring frequencies (hundreds of MHz) where a normal counter would not.
  wire ring = cal_sel ? out_b : out_a;

  wire [12:0] q;

  reg q0;
  always @(posedge ring or negedge cal_en)
    if (!cal_en) q0 <= 1'b0;
    else         q0 <= ~q0;
  assign q[0] = q0;

  genvar i;
  generate
    for (i = 1; i < 13; i = i + 1) begin : div
      reg t;
      always @(negedge q[i-1] or negedge cal_en)
        if (!cal_en) t <= 1'b0;
        else         t <= ~t;
      assign q[i] = t;
    end
  endgenerate

  // q[n] toggles at ring / 2^(n+1); select q[5..12] -> divide by 64 .. 8192
  assign cal_out = cal_en & q[5 + div_sel];

endmodule
