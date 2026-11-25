# SPDX-License-Identifier: Apache-2.0
#
# Tests for tt_um_pwm_deadtime.
#
# RTL simulation uses test/sim_cells.v (typical-corner delays from STA):
#   1 LSB = 1.14 ns, deadtime offset = 3.15 ns (input mux + 8 stage muxes)
# so absolute deadtimes are checked.
#
# Gate-level simulation (GATES=yes) uses unit delays for every cell, so only
# behaviour (ordering, monotonic increase, no overlap) is checked there.

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, First, ReadOnly, RisingEdge, Timer, ValueChange, with_timeout
from cocotb.utils import get_sim_time

GL = os.environ.get("GATES") == "yes"

# RTL model constants (must match sim_cells.v and UNIT_CELLS)
GATE_NS, MUX_NS, NAND_NS, UNIT_CELLS = 0.57, 0.35, 0.10, 2
LSB_NS = UNIT_CELLS * GATE_NS               # 1.14 ns
OFFSET_NS = 9 * MUX_NS                      # input mux + 8 stage muxes
RING_EXTRA_NS = NAND_NS + 9 * MUX_NS        # one ring half-period overhead
TOL_NS = 0.05

SETTLE_NS = 3000         # long enough for an edge to pass a full delay line (also in GL)

REG_RISE, REG_FALL, REG_CTRL, REG_ID = 0, 1, 2, 3
CTRL_EN, CTRL_CAL, CTRL_SEL = 0x01, 0x02, 0x04


def now_ns():
    return get_sim_time(unit="ps") / 1000.0


def bit(sig):
    return str(sig.value) == "1"


# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------
async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())  # 50 MHz
    dut.ena.value = 1
    dut.ui_in.value = 0
    for name in ("pwm", "sck", "mosi", "mode", "en_pin", "cal_pin", "sel_pin"):
        getattr(dut, name).value = 0
    dut.cs_n.value = 1
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await Timer(SETTLE_NS, unit="ns")


async def no_overlap_monitor(dut):
    """Fail the test if OUT_H and OUT_L are ever 1 at the same time."""
    while True:
        await First(ValueChange(dut.out_h), ValueChange(dut.out_l))
        await ReadOnly()
        assert not (bit(dut.out_h) and bit(dut.out_l)), f"shoot-through at {now_ns():.3f} ns"


async def spi_xfer(dut, header, data, half_ns=100):
    """One 16-bit SPI mode-0 frame. Returns the byte read on MISO during byte 1."""
    dut.cs_n.value = 0
    await Timer(half_ns, unit="ns")
    word = (header << 8) | data
    rx = 0
    for i in range(15, -1, -1):
        dut.mosi.value = (word >> i) & 1
        await Timer(half_ns, unit="ns")
        rx = (rx << 1) | (1 if bit(dut.miso) else 0)   # master samples at rising edge
        dut.sck.value = 1
        await Timer(half_ns, unit="ns")
        dut.sck.value = 0
    await Timer(half_ns, unit="ns")
    dut.cs_n.value = 1
    await Timer(2 * half_ns, unit="ns")
    return rx & 0xFF


async def spi_write(dut, addr, data):
    await spi_xfer(dut, 0x80 | addr, data)


async def spi_read(dut, addr):
    return await spi_xfer(dut, addr & 0x03, 0x00)


async def measure_deadtimes(dut):
    """PWM must be low and settled. Returns (rise_deadtime_ns, fall_deadtime_ns)."""
    t0 = now_ns()
    dut.pwm.value = 1
    await with_timeout(RisingEdge(dut.out_h), SETTLE_NS, "ns")
    dt_rise = now_ns() - t0
    assert not bit(dut.out_l)

    await Timer(SETTLE_NS, unit="ns")

    t0 = now_ns()
    dut.pwm.value = 0
    await with_timeout(RisingEdge(dut.out_l), SETTLE_NS, "ns")
    dt_fall = now_ns() - t0
    assert not bit(dut.out_h)

    await Timer(SETTLE_NS, unit="ns")
    return dt_rise, dt_fall


async def measure_cal_period(dut):
    """Period of the divided ring-oscillator output (2nd to 3rd rising edge)."""
    timeout = 2_000_000
    await with_timeout(RisingEdge(dut.cal_out), timeout, "ns")
    await with_timeout(RisingEdge(dut.cal_out), timeout, "ns")
    t0 = now_ns()
    await with_timeout(RisingEdge(dut.cal_out), timeout, "ns")
    return now_ns() - t0


def expected_dt(code):
    return OFFSET_NS + code * LSB_NS


# ----------------------------------------------------------------------------
# tests
# ----------------------------------------------------------------------------
@cocotb.test()
async def test_spi_registers(dut):
    """Reset values, write / read back, ID is read-only."""
    await setup(dut)

    assert await spi_read(dut, REG_ID) == 0xD7
    assert await spi_read(dut, REG_RISE) == 0xFF
    assert await spi_read(dut, REG_FALL) == 0xFF
    assert await spi_read(dut, REG_CTRL) == 0x00

    await spi_write(dut, REG_RISE, 0x12)
    await spi_write(dut, REG_FALL, 0xA5)
    await spi_write(dut, REG_CTRL, 0x2B)
    await spi_write(dut, REG_ID, 0x00)

    assert await spi_read(dut, REG_RISE) == 0x12
    assert await spi_read(dut, REG_FALL) == 0xA5
    assert await spi_read(dut, REG_CTRL) == 0x2B
    assert await spi_read(dut, REG_ID) == 0xD7


@cocotb.test()
async def test_outputs_off_after_reset(dut):
    """After reset the outputs are disabled: PWM toggling must not reach the pins."""
    await setup(dut)
    for _ in range(4):
        dut.pwm.value = 1
        await Timer(SETTLE_NS, unit="ns")
        assert not bit(dut.out_h) and not bit(dut.out_l)
        dut.pwm.value = 0
        await Timer(SETTLE_NS, unit="ns")
        assert not bit(dut.out_h) and not bit(dut.out_l)


@cocotb.test()
async def test_deadtime_spi_mode(dut):
    """Separate rising / falling deadtimes from the SPI registers."""
    await setup(dut)
    cocotb.start_soon(no_overlap_monitor(dut))

    results = {}
    for code_rise, code_fall in [(10, 40), (40, 10), (0, 0), (255, 128)]:
        await spi_write(dut, REG_CTRL, 0x00)          # disable before changing codes
        await spi_write(dut, REG_RISE, code_rise)
        await spi_write(dut, REG_FALL, code_fall)
        await spi_write(dut, REG_CTRL, CTRL_EN)
        await Timer(SETTLE_NS, unit="ns")

        dt_r, dt_f = await measure_deadtimes(dut)
        dut._log.info(f"codes rise={code_rise:3d} fall={code_fall:3d} -> "
                      f"deadtime rise={dt_r:8.3f} ns fall={dt_f:8.3f} ns")
        results[(code_rise, code_fall)] = (dt_r, dt_f)

        if not GL:
            assert abs(dt_r - expected_dt(code_rise)) < TOL_NS
            assert abs(dt_f - expected_dt(code_fall)) < TOL_NS

    # behaviour checks that also hold for gate level
    assert results[(40, 10)][0] > results[(10, 40)][0]
    assert results[(10, 40)][1] > results[(40, 10)][1]
    assert results[(255, 128)][0] > results[(40, 10)][0]


@cocotb.test()
async def test_pin_mode(dut):
    """MODE=1: both deadtimes come from ui_in, EN pin enables the outputs."""
    await setup(dut)
    cocotb.start_soon(no_overlap_monitor(dut))

    dut.mode.value = 1
    dut.ui_in.value = 25
    dut.en_pin.value = 0
    await Timer(SETTLE_NS, unit="ns")

    # EN low: nothing comes out
    dut.pwm.value = 1
    await Timer(SETTLE_NS, unit="ns")
    assert not bit(dut.out_h) and not bit(dut.out_l)
    dut.pwm.value = 0
    await Timer(SETTLE_NS, unit="ns")

    dut.en_pin.value = 1
    await Timer(SETTLE_NS, unit="ns")
    dt_r, dt_f = await measure_deadtimes(dut)
    dut._log.info(f"pin mode code=25 -> rise={dt_r:.3f} ns fall={dt_f:.3f} ns")
    if not GL:
        assert abs(dt_r - expected_dt(25)) < TOL_NS
        assert abs(dt_f - expected_dt(25)) < TOL_NS


@cocotb.test()
async def test_calibration(dut):
    """Ring-oscillator calibration: two codes -> LSB size and offset."""
    await setup(dut)

    for sel, reg in [(0, REG_RISE), (1, REG_FALL)]:
        periods = {}
        for code in (0, 100):
            await spi_write(dut, REG_CTRL, 0x00)
            await spi_write(dut, reg, code)
            await spi_write(dut, REG_CTRL, CTRL_CAL | (CTRL_SEL if sel else 0))  # div_sel = 0 -> /64
            periods[code] = await measure_cal_period(dut)
            assert not bit(dut.out_h) and not bit(dut.out_l)

        # ring period = 2 * (line delay + loop overhead); divided by 64
        lsb = (periods[100] - periods[0]) / (2 * 64 * 100)
        overhead = periods[0] / (2 * 64)
        dut._log.info(f"line {'B' if sel else 'A'}: T(0)={periods[0]:.2f} ns  T(100)={periods[100]:.2f} ns  "
                      f"-> LSB={lsb:.4f} ns, loop overhead={overhead:.3f} ns")

        assert periods[100] > periods[0]
        if not GL:
            assert abs(lsb - LSB_NS) < 0.01
            assert abs(overhead - RING_EXTRA_NS) < 0.01

    await spi_write(dut, REG_CTRL, 0x00)


@cocotb.test()
async def test_calibration_pin_mode(dut):
    """CAL pin starts the ring oscillator in pin mode."""
    await setup(dut)
    dut.mode.value = 1
    dut.ui_in.value = 0
    dut.cal_pin.value = 1
    period = await measure_cal_period(dut)
    dut._log.info(f"pin mode calibration period (code 0) = {period:.2f} ns")
    if not GL:
        assert abs(period / (2 * 64) - RING_EXTRA_NS) < 0.01
