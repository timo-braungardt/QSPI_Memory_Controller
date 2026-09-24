import os
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner


async def reset_dut(dut):
    dut.reset.value = 1
    await ClockCycles(dut.clk, 1, rising=True)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 1, rising=True)


@cocotb.test()
async def transmission_test(dut):
    assert True


def test_octal_spi_model(wave=False):
    """
    Test if the basics of the Octal SPI protocol are implemented correctly.
    """
    required_file = Path(
        "../../test/memory_models/infineon-verilog-model-for-octal-spi-interface-simulationmodels-en-09018a90808f2609/002-30135/s70kl1283_00.v"
    )
    if not required_file.exists():
        raise SkipTest(f"Simulation Model for S70KL1283 not found!")

    proj_path = Path(__file__).resolve().parent
    sources = [
        proj_path / "../../src/OctalSPI.v",
        proj_path / "../../test/cocotb_wrapper/Octal_SPI_wrapper.v",
        proj_path / required_file,
    ]

    sim = os.getenv("SIM", "questa")
    try:
        runner = get_runner(sim)
    except SystemExit:
        raise SkipTest(f"Simulator {sim} not found!")

    runner.build(sources=sources, hdl_toplevel="Octal_SPI_wrapper", always=True, waves=True)
    runner.test(
        hdl_toplevel="Octal_SPI_wrapper",
        test_module="test_octal_spi_model",
        gui=wave,
        waves=True,
        pre_cmd=["source ../parameter_octal_spi_model.tcl"],
    )


if __name__ == "__main__":
    test_octal_spi_model(wave=True)
