/*
 * Copyright (c) 2026
 * SPDX-License-Identifier: Apache-2.0
 *
 * 8-bit binary-weighted programmable delay line.
 *
 *   in -> [stage0: 1 LSB or bypass] -> [stage1: 2 LSB or bypass] -> ... -> [stage7: 128 LSB or bypass] -> out
 *
 * Stage k contains (2^k * UNIT_CELLS) delay cells. A 2:1 mux after each stage
 * selects either the delayed signal (code[k] = 1) or the bypass (code[k] = 0).
 *
 *   delay(code) ~= t_offset + code * t_lsb
 *   t_offset    = 8 mux delays (always in the path)
 *   t_lsb       = UNIT_CELLS * t_dlygate
 *
 * All cells are instantiated directly from the sky130_fd_sc_hd library so that
 * synthesis does not optimise the chain away. Instance names contain "dt_keep"
 * so the resizer can be told not to touch them (RSZ_DONT_TOUCH_RX in config.json).
 *
 * This path is ASYNCHRONOUS: no clock is involved. Changing `code` while a
 * signal edge is travelling through the line can create a glitch, so only
 * change the code while the outputs are disabled.
 */

`default_nettype none

module dt_delay_line #(
    parameter UNIT_CELLS = 2      // delay cells per LSB
) (
    input  wire       in,
    input  wire [7:0] code,
    output wire       out
);

  wire [8:0] node;
  assign node[0] = in;

  genvar k, j;
  generate
    for (k = 0; k < 8; k = k + 1) begin : stage
      localparam integer N = (1 << k) * UNIT_CELLS;

      wire [N:0] chain;
      assign chain[0] = node[k];

      for (j = 0; j < N; j = j + 1) begin : dly
        sky130_fd_sc_hd__dlygate4sd3_1 dt_keep_dly (
            .A(chain[j]),
            .X(chain[j+1])
        );
      end

      // code[k] = 0 -> bypass, code[k] = 1 -> through the delay chain
      sky130_fd_sc_hd__mux2_1 dt_keep_mux (
          .A0(node[k]),
          .A1(chain[N]),
          .S (code[k]),
          .X (node[k+1])
      );
    end
  endgenerate

  assign out = node[8];

endmodule
