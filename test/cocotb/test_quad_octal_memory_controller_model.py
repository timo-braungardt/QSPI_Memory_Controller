import os
import logging
from pathlib import Path
import random
import itertools
import pytest
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, First, ClockCycles, RisingEdge, FallingEdge
from cocotb.clock import Clock
from collections import deque
from cocotbext.axi import AxiBus, AxiMaster
from cocotbext.spi import SpiBus
from HelperClasses import DummyData, MemoryModelHelper
from unittest import SkipTest

DATA_WIDTH = int(os.environ.get("PARAM_DATA_WIDTH", 32))
NUM_BYTES = DATA_WIDTH // 8

T_rwr = Timer(35, unit="ns")  # read-write recovery time from the datasheet
# to wait after one transaction this much is pesimistic, we can already issue 4 cycles of the next command


def get_memory_quad(dut, addr, num_bytes):
    read_length = num_bytes // 4
    memory_data = []

    memory_data_0 = MemoryModelHelper.get_memory_s70kl1283(dut.gen_memory[0].Memory, addr, read_length)
    memory_data_1 = MemoryModelHelper.get_memory_s70kl1283(dut.gen_memory[1].Memory, addr, read_length)
    memory_data_2 = MemoryModelHelper.get_memory_s70kl1283(dut.gen_memory[2].Memory, addr, read_length)
    memory_data_3 = MemoryModelHelper.get_memory_s70kl1283(dut.gen_memory[3].Memory, addr, read_length)

    for i in range(read_length):
        memory_data.append(memory_data_0[i])
        memory_data.append(memory_data_1[i])
        memory_data.append(memory_data_2[i])
        memory_data.append(memory_data_3[i])

    return memory_data


def set_memory_quad(dut, addr, data):
    write_length = data.num_bytes // 4
    test_data = list(data.get_test_array())

    test_data_0 = []
    test_data_1 = []
    test_data_2 = []
    test_data_3 = []

    for i in range(write_length):
        test_data_0.append(test_data.pop(0))
        test_data_1.append(test_data.pop(0))
        test_data_2.append(test_data.pop(0))
        test_data_3.append(test_data.pop(0))

    MemoryModelHelper.set_memory_s70kl1283(dut.gen_memory[0].Memory, addr, test_data_0)
    MemoryModelHelper.set_memory_s70kl1283(dut.gen_memory[1].Memory, addr, test_data_1)
    MemoryModelHelper.set_memory_s70kl1283(dut.gen_memory[2].Memory, addr, test_data_2)
    MemoryModelHelper.set_memory_s70kl1283(dut.gen_memory[3].Memory, addr, test_data_3)


async def reset_model(dut):
    dut.test_number.value = dut.test_number.value + 1
    dut.reset.value = 1
    await Timer(200, unit="ns")  # t_RP
    dut.reset.value = 0
    await Timer(200, unit="ns")  # t_RH

    if dut.gen_memory[0].Memory.bottom.PoweredUp.value == 0:
        await dut.gen_memory[0].Memory.bottom.PoweredUp.value_change
    if dut.gen_memory[1].Memory.bottom.PoweredUp.value == 0:
        await dut.gen_memory[1].Memory.bottom.PoweredUp.value_change
    if dut.gen_memory[2].Memory.bottom.PoweredUp.value == 0:
        await dut.gen_memory[2].Memory.bottom.PoweredUp.value_change
    if dut.gen_memory[3].Memory.bottom.PoweredUp.value == 0:
        await dut.gen_memory[3].Memory.bottom.PoweredUp.value_change


async def wait_for_idle(dut):
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.chip_select_neg), timeout)
    assert trigger != timeout


@cocotb.test()
@cocotb.parametrize(params=[(4, 0x0100), (8, 0x0200), (16, 0x0200), (128, 0x0300), (256, 0x1000),(512, 0x1100)])
async def write_alligned_test(dut, params):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    await reset_model(dut)

    num_bytes, addr = params
    test_data = DummyData(num_bytes)

    timeout = Timer(200, unit="us")
    write_task = cocotb.start_soon(axi_master.write(addr, test_data.get_test_array()))
    trigger = await First(write_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        await FallingEdge(dut.Controller.spi_busy)

    await T_rwr

    test_array = test_data.get_test_array()
    
    memory_data = get_memory_quad(dut, addr, num_bytes)
    assert memory_data == test_array


@cocotb.test()
@cocotb.parametrize(params=[(4, 0x0108), (16, 0x0220), (128, 0x0500)])
async def read_alligned_test(dut, params):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    await reset_model(dut)

    num_bytes, addr = params
    test_data = DummyData(num_bytes)

    set_memory_quad(dut, addr, test_data)

    timeout = Timer(200, unit="us")
    read_task = cocotb.start_soon(axi_master.read(addr, num_bytes))
    trigger = await First(read_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        timeout = Timer(100, unit="us")
        await First(FallingEdge(dut.Controller.spi_busy), timeout)
    data = read_task.result()
    assert list(data.data) == test_data.get_test_array()


@cocotb.test()
async def write_length_test(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    await reset_model(dut)

    num_bytes = 4 
    addr = 0x0008
    test_data = DummyData(num_bytes)

    # step: write
    timeout = Timer(100, unit="us")
    write_task = cocotb.start_soon(axi_master.write(addr, test_data.get_test_array()))
    trigger = await First(write_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        await FallingEdge(dut.Controller.spi_busy)
    await T_rwr

    memory_data = get_memory_quad(dut, addr, test_data.num_bytes*2)
    temp_test_data = list(test_data.get_test_array())
    temp_test_data.extend([0xff] *4)
    assert memory_data == temp_test_data

    memory_data = get_memory_quad(dut, addr -1, 8)
    assert memory_data == [0xff] *8

    memory_data = get_memory_quad(dut, addr +1, 8)
    assert memory_data == [0xff] *8


@cocotb.test()
async def write_byte_masking(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    await reset_model(dut)

    addr = 0x0010

    test_data = DummyData(4)
    test_data._array = [0]*4
    
    set_memory_quad(dut, addr, test_data)
    await axi_master.write(addr+1, b'\xAA\xBB')   # WSTRB = 0b0110
    if dut.Controller.spi_busy.value == True:
        await FallingEdge(dut.Controller.spi_busy)
    await T_rwr

    memory_data = get_memory_quad(dut, addr, 8)
    assert memory_data[0] == 0
    assert memory_data[1] == 0xAA
    assert memory_data[2] == 0xBB

    await axi_master.write(addr+3, b'\xCC')       # WSTRB = 0b1000
    if dut.Controller.spi_busy.value == True:
        await FallingEdge(dut.Controller.spi_busy)
    await T_rwr
    
    memory_data = get_memory_quad(dut, addr, 8)
    assert memory_data[0] == 0
    assert memory_data[1] == 0xAA
    assert memory_data[2] == 0xBB
    assert memory_data[3] == 0xCC


@cocotb.test()
@cocotb.parametrize(params=[(4, 0x0104)])
async def unalligned_access_front_test(dut, params):
    """
    With the octal spi we always have to write two bytes.
    This test checks if we correctly padd the first byte when we write to an 'uneven' address.
    """
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    await reset_model(dut)

    num_bytes, addr = params
    test_data = DummyData(num_bytes)

    overwrite_data = DummyData(num_bytes*2)
    overwrite_data._array = [0xff]*(num_bytes*2)
    set_memory_quad(dut, addr-1, overwrite_data)

    timeout = Timer(200, unit="us")
    write_task = cocotb.start_soon(axi_master.write(addr, test_data.get_test_array()))
    trigger = await First(write_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        await FallingEdge(dut.Controller.spi_busy)

    await T_rwr

    
    memory_data = get_memory_quad(dut, addr, num_bytes*2)
    temp_test_data = []
    temp_test_data.extend([0xff] *4)
    temp_test_data.extend(list(test_data.get_test_array()))
    assert memory_data == temp_test_data


@cocotb.test()
@cocotb.parametrize(params=[(8, 0x0104)])
async def unalligned_access_front_back_test(dut, params):
    """
    With the octal spi we always have to write two bytes.
    This test checks if we correctly padd the first byte when we write to an 'uneven' address.
    """
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    await reset_model(dut)

    num_bytes, addr = params
    test_data = DummyData(num_bytes)

    overwrite_data = DummyData(num_bytes*2)
    overwrite_data._array = [0xff]*(num_bytes*2)
    set_memory_quad(dut, addr-1, overwrite_data)

    timeout = Timer(200, unit="us")
    write_task = cocotb.start_soon(axi_master.write(addr, test_data.get_test_array()))
    trigger = await First(write_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        await FallingEdge(dut.Controller.spi_busy)

    await T_rwr

    
    memory_data = get_memory_quad(dut, addr, num_bytes*2)
    temp_test_data = []
    temp_test_data.extend([0xff] *4)
    temp_test_data.extend(list(test_data.get_test_array()))
    temp_test_data.extend([0xff] *4)
    assert memory_data == temp_test_data


@cocotb.test()
@cocotb.parametrize(params=[(8, 0x0200)])
async def read_write_alligned_test(dut, params):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    await reset_model(dut)

    # write
    num_bytes, addr = params
    test_data = DummyData(num_bytes)

    timeout = Timer(200, unit="us")
    write_task = cocotb.start_soon(axi_master.write(addr, test_data.get_test_array()))
    trigger = await First(write_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        await FallingEdge(dut.Controller.spi_busy)

    await T_rwr

    test_array = test_data.get_test_array()
    
    memory_data = get_memory_quad(dut, addr, num_bytes)
    assert memory_data == test_array

    # read
    timeout = Timer(200, unit="us")
    read_task = cocotb.start_soon(axi_master.read(addr, num_bytes))
    trigger = await First(read_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        timeout = Timer(100, unit="us")
        await First(FallingEdge(dut.Controller.spi_busy), timeout)
    data = read_task.result()
    assert list(data.data) == test_data.get_test_array()


@cocotb.test()
@cocotb.parametrize(params=[(8, 0x0200)])
async def read_read_alligned_test(dut, params):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    await reset_model(dut)

    num_bytes, addr = params
    test_data = DummyData(num_bytes)

    set_memory_quad(dut, addr, test_data)

    timeout = Timer(200, unit="us")
    read_task = cocotb.start_soon(axi_master.read(addr, num_bytes))
    trigger = await First(read_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        timeout = Timer(100, unit="us")
        await First(FallingEdge(dut.Controller.spi_busy), timeout)
    data = read_task.result()
    assert list(data.data) == test_data.get_test_array()

    timeout = Timer(200, unit="us")
    read_task = cocotb.start_soon(axi_master.read(addr, num_bytes))
    trigger = await First(read_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        timeout = Timer(100, unit="us")
        await First(FallingEdge(dut.Controller.spi_busy), timeout)
    data = read_task.result()
    assert list(data.data) == test_data.get_test_array()



@cocotb.test()
@cocotb.parametrize(params=[(128, 0x0300)])
async def write_idle_cycles_test(dut, params):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    await reset_model(dut)

    num_bytes, addr = params
    test_data = DummyData(num_bytes)
    pause_pattern = itertools.cycle([1, 1, 1, 0])

    axi_master.write_if.w_channel.set_pause_generator(pause_pattern)

    timeout = Timer(200, unit="us")
    write_task = cocotb.start_soon(axi_master.write(addr, test_data.get_test_array()))
    trigger = await First(write_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        await FallingEdge(dut.Controller.spi_busy)

    await T_rwr

    test_array = test_data.get_test_array()
    
    memory_data = get_memory_quad(dut, addr, num_bytes)
    assert memory_data == test_array


@cocotb.test()
@cocotb.parametrize(params=[(128, 0x0500)])
async def read_idle_cycles_alligned_test(dut, params):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    await reset_model(dut)

    num_bytes, addr = params
    test_data = DummyData(num_bytes)
    pause_pattern = itertools.cycle([1, 1, 1, 0])

    axi_master.read_if.r_channel.set_pause_generator(pause_pattern)

    set_memory_quad(dut, addr, test_data)

    timeout = Timer(200, unit="us")
    read_task = cocotb.start_soon(axi_master.read(addr, num_bytes))
    trigger = await First(read_task, timeout)
    assert trigger != timeout
    if dut.Controller.spi_busy.value == True:
        timeout = Timer(100, unit="us")
        await First(FallingEdge(dut.Controller.spi_busy), timeout)
    data = read_task.result()
    assert list(data.data) == test_data.get_test_array()


def test_quad_octal_memory_controller_model(wave=False):
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
        proj_path / "../../src/OSPIController_quad.v",
        proj_path / "../../src/OctalSPI_quad.v",
        proj_path / "../../src/AXIInterface.v",
        proj_path / "../../src/OctalMemoryController_quad.v",
        proj_path / "../../test/cocotb_wrapper/Quad_Octal_Memory_Controller_wrapper.v",
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
        hdl_toplevel="Quad_Octal_Memory_Controller_wrapper",
        always=True,
        waves=True,
        parameters=parameters,
    )
    runner.test(
        hdl_toplevel="Quad_Octal_Memory_Controller_wrapper",
        test_module="test_quad_octal_memory_controller_model",
        parameters=parameters,
        gui=wave,
        pre_cmd=["source ../parameter_quad_octal_memory_controller_model.tcl"],
        extra_env=extra_env,
    )


if __name__ == "__main__":
    test_quad_octal_memory_controller_model(True)
