import os
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer


async def generate_clock(dut):
    for _ in range(1):
        dut.clk.value = 0
        await Timer(1, unit="ns")
        dut.clk.value = 1
        await Timer(1, unit="ns")


@cocotb.test()
async def my_first_test(dut):
    cocotb.start_soon(generate_clock(dut))

    await Timer(2, unit="ns")
    cocotb.log.info("signal is %s", dut.signal.value)
    assert dut.signal.value == 1


def test_my_design():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../../src/my_design.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="my_design",
        always=True
    )

    runner.test(hdl_toplevel="my_design", test_module="test_my_design,")


if __name__ == "__main__":
    test_my_design()
