import os
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer
from cocotb.clock import Clock


@cocotb.test()
async def qspi_flash(dut):
    dut.opcode.value = 3
    dut.address.value = 20

    c = Clock(dut.clk  , 20, 'ns')
    cocotb.start_soon(c.start())

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 100, rising=True)


def test_quad_spi():
    """
    Test if the basics of the Quad SPI protocol are implemented correctly.
    """
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../../src/QuadSPI.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="QuadSPI",
        always=True,
        waves=True
    )
    runner.test(hdl_toplevel="QuadSPI", 
				test_module="test_quad_spi",
                waves=True)


if __name__ == "__main__":
    test_quad_spi()