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
from HelperClasses import SpiFlashMemory
from unittest import SkipTest

DATA_WIDTH = int(os.environ.get("PARAM_DATA_WIDTH", 32))
NUM_BYTES = DATA_WIDTH // 8

T_pp_typ = Timer(480, unit="us")    # program time typical from the datasheet


async def reset_model(dut):
    dut.reset.value = 1
    await Timer(250, unit="ns")  # t_RP
    dut.reset.value = 0
    await Timer(500, unit="us")  # t_RH

    if dut.Memory.PoweredUp.value == 0:
        await dut.Memory.PoweredUp.value_change


async def wait_for_idle(dut):
    timeout = Timer(100, unit="us")
    trigger = await First(FallingEdge(dut.spi_busy), timeout)
    assert trigger != timeout


def generate_test_array(num_bytes):
    array = bytearray()
    for _ in range(num_bytes):
        array.append(random.randrange(256))
    return array


@cocotb.test()
@cocotb.parametrize(params=[(4, 0x0100), (16, 0x0200), (128, 0x0300)])
async def readwrite_alligned_test(dut, params):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    await reset_model(dut)

    num_bytes, addr = params
    test_data = generate_test_array(num_bytes)

    # step: write
    timeout = Timer(200, unit="us")
    write_task = cocotb.start_soon(axi_master.write(addr, test_data))
    trigger = await First(write_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        await FallingEdge(dut.Controller.spi_busy)

    await T_pp_typ

    # step: read
    timeout = Timer(200, unit="us")
    read_task = cocotb.start_soon(axi_master.read(addr, num_bytes))
    trigger = await First(read_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        timeout = Timer(100, unit="us")
        await First(FallingEdge(dut.Controller.spi_busy), timeout)
    data = read_task.result()
    assert list(data.data) == list(test_data)


# ToDo: At the moment it is expected that the unalligned access does not work due to the endian missmatch
# issue #13
@cocotb.test()
@cocotb.parametrize(params=[(3, 0x0180), (15, 0x0280)])
async def readwrite_unalligned_test(dut, params):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    await reset_model(dut)

    num_bytes, addr = params
    test_data = generate_test_array(num_bytes)

    # step: write
    timeout = Timer(100, unit="us")
    write_task = cocotb.start_soon(axi_master.write(addr, test_data))
    trigger = await First(write_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        await FallingEdge(dut.Controller.spi_busy)

    await T_pp_typ

    # step: read
    timeout = Timer(100, unit="us")
    read_task = cocotb.start_soon(axi_master.read(addr, num_bytes))
    trigger = await First(read_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        timeout = Timer(100, unit="us")
        await First(FallingEdge(dut.Controller.spi_busy), timeout)
    data = read_task.result()
    assert list(data.data) == list(test_data)


def test_memory_controller_model(wave=False):
    """
    Integration test of all modules in memory controller.
    """

    required_file = Path(
        "../../test/memory_models/infineon-s25hl512t-qspi-verilog-model-simulationmodels-en/s25hl512tRel/src/s25hl512t.sv"
    )
    if not required_file.exists():
        raise SkipTest(f"Simulation Model for S25HL512T not found!")

    proj_path = Path(__file__).resolve().parent
    sources = [
        proj_path / "../../src/SPIController.v",
        proj_path / "../../src/SPITransmitter.v",
        proj_path / "../../src/AXIInterface.v",
        proj_path / "../../src/MemoryController.v",
        proj_path / "../../test/cocotb_wrapper/Memory_Controller_wrapper.v",
        proj_path / required_file,
    ]

    parameters = {}
    parameters["DATA_WIDTH"] = 32
    parameters["ADDR_WIDTH"] = 24
    extra_env = {f"PARAM_{k}": str(v) for k, v in parameters.items()}

    sim = os.getenv("SIM", "questa")
    try:
        runner = get_runner(sim)
    except SystemExit:
        raise SkipTest(f"Simulator {sim} not found!")

    runner.build(
        sources=sources,
        hdl_toplevel="Memory_Controller_wrapper",
        always=True,
        waves=True,
        parameters=parameters,
    )
    runner.test(
        hdl_toplevel="Memory_Controller_wrapper",
        test_module="test_memory_controller_model",
        parameters=parameters,
        gui=wave,
        pre_cmd=["source ../parameter_memory_controller_model.tcl"],
        extra_env=extra_env,
    )


if __name__ == "__main__":
    test_memory_controller_model(True)
