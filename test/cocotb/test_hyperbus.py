import os
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, First
from cocotb.clock import Clock


@cocotb.test()
async def transmission_test(dut):
    dut.opcode.value = 5
    dut.address.value = 0x8000000001
    dut.write_address.value = 0b1
    dut.write_data.value = 0b1
    dut.read_data.value = 0b0

    c = Clock(dut.clk  , 20, 'ns')
    cocotb.start_soon(c.start())

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.o_ChipSelect_neg.value_change



def test_hyperbus():
    """
    Test if the basics of the Hyperbus protocol are implemented correctly.
    """
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../../src/Hyperbus.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="Hyperbus",
        always=True,
        waves=True
    )
    runner.test(hdl_toplevel="Hyperbus", 
				test_module="test_hyperbus",
                waves=True)


if __name__ == "__main__":
    test_hyperbus()