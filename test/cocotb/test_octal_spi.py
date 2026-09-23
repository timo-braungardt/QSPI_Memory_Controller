import os
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotbext.ospi import OspiFlash

async def reset_dut(dut):
    dut.reset.value = 1
    await ClockCycles(dut.clk, 1, rising=True)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 1, rising=True)


@cocotb.test()
async def transmission_test(dut):
    assert False


@cocotb.test()
async def read_test(dut):
    assert False


@cocotb.test()
async def write_test(dut):
    assert False


def test_octal_spi():
    """
    Test if the basics of the Octal SPI protocol are implemented correctly.
    """
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../../src/OctalSPI.v"]

    runner = get_runner(sim)
    runner.build(sources=sources, hdl_toplevel="OctalSPI", always=True, waves=True)
    runner.test(hdl_toplevel="OctalSPI", test_module="test_octal_spi", waves=True)


if __name__ == "__main__":
    test_octal_spi()
