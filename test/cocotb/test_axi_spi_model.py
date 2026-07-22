import os
import logging
from pathlib import Path
import itertools
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, First, FallingEdge, RisingEdge
from cocotb.clock import Clock
from cocotb.types import Logic, LogicArray
from cocotbext.axi import AxiBus, AxiMaster
from unittest import SkipTest


async def reset_model(dut):
    dut.rst.setimmediatevalue(0)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 1
    await Timer(250, unit="ns")  # t_RP
    dut.rst.value = 0
    await Timer(500, unit="us")  # t_RH

    if dut.Memory.PoweredUp.value == 0:
        await dut.Memory.PoweredUp.value_change


@cocotb.test()
async def transmission_test(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    await reset_model(dut)

    addr = 0x1000
    length = 4
    test_data = bytearray([x % 256 for x in range(length)])
    await axi_master.write(addr, test_data)
    
    await Timer(480, unit="us")  # T_PP typ in the datasheet
    data = await axi_master.read(addr, length)
    assert data.data == test_data


def test_axi_spi_model(wave=False):
    required_file = Path(
        "../../test/memory_models/infineon-s25hl512t-qspi-verilog-model-simulationmodels-en/s25hl512tRel/src/s25hl512t.sv"
    )
    if not required_file.exists():
        raise SkipTest(f"Simulation Model for S25HL512T not found!")

    proj_path = Path(__file__).resolve().parent
    sources = [
        proj_path / "../../src/BasicSPI.v",
        proj_path / "../../src/Basic_AXI_SPI.v",
        proj_path / "../../test/cocotb_wrapper/AXI_SPI_wrapper.v",
        proj_path / required_file,
    ]

    sim = os.getenv("SIM", "questa")
    try:
        runner = get_runner(sim)
    except SystemExit:
        raise SkipTest(f"Simulator {sim} not found!")

    runner.build(
        sources=sources,
        hdl_toplevel="AXI_SPI_wrapper",
        always=True,
    )

    runner.test(
        hdl_toplevel="AXI_SPI_wrapper",
        test_module="test_axi_spi_model",
        gui=wave,
        pre_cmd=["source ../parameter_axi_spi_model.tcl"],
    )


if __name__ == "__main__":
    test_axi_spi_model(True)
