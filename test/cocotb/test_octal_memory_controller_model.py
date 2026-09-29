import os
import logging
from pathlib import Path
import random
import pytest
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, First, ClockCycles, RisingEdge, FallingEdge
from cocotb.clock import Clock
from collections import deque
from cocotbext.axi import AxiBus, AxiMaster
from cocotbext.spi import SpiBus
from HelperClasses import DummyData
from unittest import SkipTest

DATA_WIDTH = int(os.environ.get("PARAM_DATA_WIDTH", 32))
NUM_BYTES = DATA_WIDTH // 8

T_rwr = Timer(35, unit="ns")  # read-write recovery time from the datasheet
# to wait after one transaction this much is pesimistic, we can already issue 4 cycles of the next command


async def reset_model(dut):
    dut.reset.value = 1
    await Timer(200, unit="ns")  # t_RP
    dut.reset.value = 0
    await Timer(200, unit="ns")  # t_RH

    if dut.Memory.bottom.PoweredUp.value == 0:
        await dut.Memory.bottom.PoweredUp.value_change


async def wait_for_idle(dut):
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.chip_select_neg), timeout)
    assert trigger != timeout


@cocotb.test()
@cocotb.parametrize(params=[(4, 0x0100), (16, 0x0200), (128, 0x0300)])
async def readwrite_alligned_test(dut, params):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    await reset_model(dut)

    num_bytes, addr = params
    test_data = DummyData(num_bytes)

    # step: write
    timeout = Timer(200, unit="us")
    write_task = cocotb.start_soon(axi_master.write(addr, test_data.get_test_array()))
    trigger = await First(write_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        await FallingEdge(dut.Controller.spi_busy)

    await T_rwr

    # step: read
    timeout = Timer(200, unit="us")
    read_task = cocotb.start_soon(axi_master.read(addr, test_data.num_bytes))
    trigger = await First(read_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        timeout = Timer(100, unit="us")
        await First(FallingEdge(dut.Controller.spi_busy), timeout)
    data = read_task.result()
    assert list(data.data) == test_data.get_test_array()


@cocotb.test()
@cocotb.parametrize(params=[(3, 0x0180), (15, 0x0280)])
async def readwrite_unalligned_test(dut, params):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    await reset_model(dut)

    num_bytes, addr = params
    test_data = DummyData(num_bytes)

    # step: write
    timeout = Timer(100, unit="us")
    write_task = cocotb.start_soon(axi_master.write(addr, test_data.get_test_array()))
    trigger = await First(write_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        await FallingEdge(dut.Controller.spi_busy)

    await T_rwr

    # step: read
    timeout = Timer(100, unit="us")
    read_task = cocotb.start_soon(axi_master.read(addr, test_data.num_bytes))
    trigger = await First(read_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        timeout = Timer(100, unit="us")
        await First(FallingEdge(dut.Controller.spi_busy), timeout)
    data = read_task.result()
    assert list(data.data) == test_data.get_test_array()


def test_octal_memory_controller_model(wave=False):
    """
    Integration test of all modules in memory controller.
    """

    required_file = Path(
        "../../test/memory_models/infineon-verilog-model-for-octal-spi-interface-simulationmodels-en-09018a90808f2609/002-30135/s70kl1283_00.v"
    )
    if not required_file.exists():
        raise SkipTest(f"Simulation Model for S70KL1283 not found!")

    proj_path = Path(__file__).resolve().parent
    sources = [
        proj_path / "../../src/OSPIController.v",
        proj_path / "../../src/OctalSPI.v",
        proj_path / "../../src/AXIInterface.v",
        proj_path / "../../src/MemoryController.v",
        proj_path / "../../test/cocotb_wrapper/Octal_Memory_Controller_wrapper.v",
        proj_path / required_file,
    ]

    parameters = {}
    parameters["DATA_WIDTH"] = 32
    parameters["ADDR_WIDTH"] = 32
    extra_env = {f"PARAM_{k}": str(v) for k, v in parameters.items()}

    sim = os.getenv("SIM", "questa")
    try:
        runner = get_runner(sim)
    except SystemExit:
        raise SkipTest(f"Simulator {sim} not found!")

    runner.build(
        sources=sources,
        hdl_toplevel="Octal_Memory_Controller_wrapper",
        always=True,
        waves=True,
        parameters=parameters,
    )
    runner.test(
        hdl_toplevel="Octal_Memory_Controller_wrapper",
        test_module="test_octal_memory_controller_model",
        parameters=parameters,
        gui=wave,
        pre_cmd=["source ../parameter_octal_memory_controller_model.tcl"],
        extra_env=extra_env,
    )


if __name__ == "__main__":
    test_octal_memory_controller_model(True)
