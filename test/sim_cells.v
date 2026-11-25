/*
 * Behavioural models of the sky130 standard cells used in src/, for RTL
 * simulation only (NOT synthesised - this file is not in src/).
 *
 * Delays are the typical-corner values (tt, 25 C, 1.80 V) read from the
 * post-route STA of the first hardening run (2026-11-25), rounded:
 *   dlygate4sd3_1  0.57 ns   (ff -40C 1.95V: 0.39 ns, ss 100C 1.60V: 1.18 ns)
 *   mux2_1         0.35 ns   (ff: 0.12 ns, ss: 0.78 ns)
 *   nand2_1        0.10 ns   (estimate, not on the reported path)
 *
 * With UNIT_CELLS = 2:
 *   1 LSB          = 2 * 0.57 ns = 1.14 ns
 *   line offset    = 8 * 0.35 ns = 2.80 ns  (stage muxes)
 *   input mux      = 0.35 ns
 */

`timescale 1ns / 1ps
`default_nettype none

`ifndef DLY_GATE_NS
`define DLY_GATE_NS 0.57
`endif
`ifndef DLY_MUX_NS
`define DLY_MUX_NS 0.35
`endif
`ifndef DLY_NAND_NS
`define DLY_NAND_NS 0.10
`endif

module sky130_fd_sc_hd__dlygate4sd3_1 (input wire A, output wire X);
  assign #(`DLY_GATE_NS) X = A;
endmodule

module sky130_fd_sc_hd__mux2_1 (input wire A0, input wire A1, input wire S, output wire X);
  assign #(`DLY_MUX_NS) X = S ? A1 : A0;
endmodule

module sky130_fd_sc_hd__nand2_1 (input wire A, input wire B, output wire Y);
  assign #(`DLY_NAND_NS) Y = ~(A & B);
endmodule

`default_nettype wire
