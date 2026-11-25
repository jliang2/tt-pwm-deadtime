/*
 * Behavioural models of the sky130 standard cells used in src/, for RTL
 * simulation only (NOT synthesised - this file is not in src/).
 *
 * The delays are PLACEHOLDERS so the deadtime and ring-oscillator behaviour
 * can be seen in simulation. Real delays depend on process, voltage and
 * temperature and must be taken from the timing reports after hardening.
 *
 * With the defaults below and UNIT_CELLS = 2:
 *   1 LSB          = 2 * 0.5 ns  = 1.0 ns
 *   line offset    = 8 * 0.1 ns  = 0.8 ns  (stage muxes)
 *   input mux      = 0.1 ns
 */

`timescale 1ns / 1ps
`default_nettype none

`ifndef DLY_GATE_NS
`define DLY_GATE_NS 0.5
`endif
`ifndef DLY_MUX_NS
`define DLY_MUX_NS 0.1
`endif
`ifndef DLY_NAND_NS
`define DLY_NAND_NS 0.05
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
