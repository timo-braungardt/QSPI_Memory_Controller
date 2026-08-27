import os
import logging
from pathlib import Path
import itertools
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, First, FallingEdge, RisingEdge, ClockCycles
from cocotb.clock import Clock
from cocotb.types import Logic, LogicArray
from unittest import SkipTest


async def reset_model(dut):
    dut.reset_neg.value = 0
    await Timer(250, unit="ns")  # t_RP
    dut.reset_neg.value = 1
    await Timer(500, unit="us")  # t_RH

    if dut.Memory.PoweredUp.value == 0:
        await dut.Memory.PoweredUp.value_change


async def wait_for_idle(dut):
    timeout = Timer(100, unit="us")
    trigger = await First(FallingEdge(dut.busy), timeout)
    assert trigger != timeout


async def trigger_go(dut):
    dut.go.value = 0
    await ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0


@cocotb.test()
async def read_test(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_model(dut)

    dut.Controller.config_quad_mode.value = 0b000

    # step: write
    dut.i_address.value = 0x20
    dut.i_data_write.value = 0x12
    dut.i_write_enable.value = True

    await trigger_go(dut)
    await wait_for_idle(dut)

    # step: read
    await Timer(480, unit="us")  # T_PP typ in the datasheet

    dut.i_address.value = 0x20
    dut.i_write_enable.value = False

    await trigger_go(dut)
    await wait_for_idle(dut)

    assert dut.o_data_read.value == 0x12


def test_spi_controller_model(wave=False):
    required_file = Path(
        "../../test/memory_models/infineon-s25hl512t-qspi-verilog-model-simulationmodels-en/s25hl512tRel/src/s25hl512t.sv"
    )
    if not required_file.exists():
        raise SkipTest(f"Simulation Model for S25HL512T not found!")

    proj_path = Path(__file__).resolve().parent
    sources = [
        proj_path / "../../src/SPIController.v",
        proj_path / "../../src/SPITransmitter.v",
        proj_path / "../../test/cocotb_wrapper/SPIController_wrapper.v",
        proj_path / required_file,
    ]

    sim = os.getenv("SIM", "questa")
    try:
        runner = get_runner(sim)
    except SystemExit:
        raise SkipTest(f"Simulator {sim} not found!")

    runner.build(
        sources=sources,
        hdl_toplevel="SPIController_wrapper",
        always=True,
    )

    runner.test(
        hdl_toplevel="SPIController_wrapper",
        test_module="test_spi_controller_model",
        gui=wave,
        pre_cmd=["source ../parameter_spi_controller_model.tcl"],
    )


if __name__ == "__main__":
    test_spi_controller_model(True)
