<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

A PWM signal on `uio[0]` is turned into a complementary pair `OUT_H` / `OUT_L` with a programmable deadtime,
as needed to drive a half bridge:

- `OUT_H = PWM & delayA(PWM)`: turns on `DT_RISE` LSBs after PWM rises, turns off immediately when PWM falls.
- `OUT_L = ~PWM & ~delayB(PWM)`: turns on `DT_FALL` LSBs after PWM falls, turns off immediately when PWM rises.
- The two outputs can never be high at the same time.

Each delay is an 8-bit binary-weighted delay line built from `sky130_fd_sc_hd__dlygate4sd3_1` cells
(stage k = 2^k LSB, bypassed by a mux when code bit k is 0). The signal path is asynchronous: PWM is never
sampled by the clock, so there is no clock-related jitter.

Nominal target is about 1 ns per LSB (0 to about 255 ns), but the real value depends on process, voltage and temperature.
It can be measured on the chip: in calibration mode the selected delay line is closed into a ring oscillator
(period = 2 x (line delay + loop overhead)), divided by 2^(6+DIV), and sent to `CAL_OUT`.
Measuring the period at two codes gives the LSB size and the offset.

### Modes

- **SPI mode** (`MODE` = 0): separate rise / fall deadtimes from SPI registers.
- **Pin mode** (`MODE` = 1): both deadtimes = `ui_in[7:0]` (DIP switches), `EN`, `CAL`, `CAL_SEL` from pins, divider fixed at /64.

### SPI (mode 0, MSB first, SCK <= clk/8)

16-bit frame while `CS_N` is low. Byte 0: bit 7 = 1 write / 0 read, bits 1:0 = address. Byte 1: data (MOSI for write, MISO for read).

| Addr | Name    | Reset | Description |
|------|---------|-------|-------------|
| 0    | DT_RISE | 0xFF  | deadtime before OUT_H turns on |
| 1    | DT_FALL | 0xFF  | deadtime before OUT_L turns on |
| 2    | CTRL    | 0x00  | [0] EN, [1] CAL, [2] CAL_SEL, [5:3] DIV |
| 3    | ID      | 0xD7  | read-only |

After reset the outputs are disabled (both low).

## How to test

Pin mode: set `MODE`=1, set the deadtime on the DIP switches, set `EN`=1, feed a PWM signal into `uio[0]` and
look at `OUT_H` / `OUT_L` with an oscilloscope. Change the deadtime only while `EN`=0.

Calibration: set `CAL`=1 (pin mode), measure the `CAL_OUT` period T at code 0 and code N. Then
LSB = (T(N) - T(0)) / (2 x 64 x N).

## External hardware

Oscilloscope, PWM source (signal generator or microcontroller), optional SPI master (e.g. the RP2040 on the demo board).
