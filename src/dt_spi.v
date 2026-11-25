/*
 * Copyright (c) 2026
 * SPDX-License-Identifier: Apache-2.0
 *
 * SPI peripheral (mode 0: CPOL=0, CPHA=0, MSB first) with 4 registers.
 *
 * SCK, CS_n and MOSI are oversampled by the system clock through 2-FF
 * synchronizers, so the whole block runs in the `clk` domain.
 * Requirement: f_SCK <= f_clk / 8  (e.g. clk = 50 MHz -> SCK <= 6 MHz).
 *
 * Frame: 16 bits while CS_n is low
 *   byte 0: [7] = 1 write / 0 read, [6:2] = don't care, [1:0] = address
 *   byte 1: write -> data from master on MOSI
 *           read  -> register value from chip on MISO
 *
 * Registers
 *   0x0 DT_RISE  reset 0xFF   deadtime before out_h turns on (LSBs)
 *   0x1 DT_FALL  reset 0xFF   deadtime before out_l turns on (LSBs)
 *   0x2 CTRL     reset 0x00   [0] out_en  [1] cal_en  [2] cal_sel  [5:3] div_sel
 *   0x3 ID       read-only    0xD7
 */

`default_nettype none

module dt_spi (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       sck,
    input  wire       cs_n,
    input  wire       mosi,
    output wire       miso,
    output reg  [7:0] dt_rise,
    output reg  [7:0] dt_fall,
    output reg  [7:0] ctrl
);

  localparam [7:0] ID = 8'hD7;

  // ---------------- synchronizers ----------------
  reg [2:0] sck_s;
  reg [1:0] cs_s;
  reg [1:0] mosi_s;

  always @(posedge clk or negedge rst_n)
    if (!rst_n) begin
      sck_s  <= 3'b000;
      cs_s   <= 2'b11;
      mosi_s <= 2'b00;
    end else begin
      sck_s  <= {sck_s[1:0], sck};
      cs_s   <= {cs_s[0], cs_n};
      mosi_s <= {mosi_s[0], mosi};
    end

  wire sck_rise  = (sck_s[2:1] == 2'b01);
  wire sck_fall  = (sck_s[2:1] == 2'b10);
  wire selected  = ~cs_s[1];
  wire mosi_bit  = mosi_s[1];

  // ---------------- shift logic ----------------
  reg  [4:0]  bit_cnt;
  reg  [15:0] rx;
  reg  [7:0]  tx;
  wire [15:0] rx_next = {rx[14:0], mosi_bit};

  reg [7:0] rd_data;
  always @(*)
    case (rx_next[1:0])
      2'd0:    rd_data = dt_rise;
      2'd1:    rd_data = dt_fall;
      2'd2:    rd_data = ctrl;
      default: rd_data = ID;
    endcase

  always @(posedge clk or negedge rst_n)
    if (!rst_n) begin
      bit_cnt <= 5'd0;
      rx      <= 16'd0;
      tx      <= 8'd0;
      dt_rise <= 8'hFF;
      dt_fall <= 8'hFF;
      ctrl    <= 8'h00;
    end else if (!selected) begin
      bit_cnt <= 5'd0;
      tx      <= 8'd0;
    end else if (sck_rise) begin
      rx <= rx_next;
      if (bit_cnt != 5'd16) bit_cnt <= bit_cnt + 5'd1;

      // 8th bit received: header complete, load read data for MISO
      if (bit_cnt == 5'd7) tx <= rd_data;

      // 16th bit received: header in rx_next[15:8], data in rx_next[7:0]
      if (bit_cnt == 5'd15 && rx_next[15])
        case (rx_next[9:8])
          2'd0:    dt_rise <= rx_next[7:0];
          2'd1:    dt_fall <= rx_next[7:0];
          2'd2:    ctrl    <= rx_next[7:0];
          default: ;  // ID is read-only
        endcase
    end else if (sck_fall && bit_cnt >= 5'd9) begin
      // master samples on the rising edge, we shift on the falling edge
      tx <= {tx[6:0], 1'b0};
    end

  assign miso = tx[7];

endmodule
