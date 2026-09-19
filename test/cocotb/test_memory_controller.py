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
from HelperClasses import SpiFlashMemory, DummyData

DATA_WIDTH = int(os.environ.get("PARAM_DATA_WIDTH", 32))
NUM_BYTES = DATA_WIDTH // 8


async def reset_dut(dut):
    dut.reset.value = 1
    await ClockCycles(dut.clk, 4, rising=True)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 1, rising=True)


async def wait_for_idle(dut):
    timeout = Timer(100, unit="us")
    trigger = await First(FallingEdge(dut.spi_busy), timeout)
    assert trigger != timeout


# ToDo: problem with the state machines when the num_bites is bigger than 8  (issue #10)
# the transmitter state machine runns on the slow clock but the outputs are routed to the axi interface
# it is fixed now by an edge detection on the next word signal - but this is shitty, this should be implemented better
@cocotb.test()
@cocotb.parametrize(num_bytes=range(1, NUM_BYTES+1))
async def write_test(dut, num_bytes):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut) # the reset is here, because otherwise the axi manager loggs too many resets

    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_spi_bus_clock",
            mosi_name="io_spi_data0_manager_serial_out",
            miso_name="io_spi_data1_manager_serial_in",
            cs_name="o_spi_chip_select_neg",
        )
    )

    addr = 0x1000
    test_data = DummyData(num_bytes)
    spi_subordinate.num_bytes = test_data.num_bytes

    # step: write
    timeout = Timer(100, unit="us")
    write_task = cocotb.start_soon(axi_master.write(addr, test_data.get_test_array()))
    trigger = await First(write_task, timeout)
    assert trigger != timeout
    if dut.spi_busy.value == True:
        await FallingEdge(dut.spi_busy)
    assert spi_subordinate.opcode == SpiFlashMemory.program
    assert spi_subordinate.address == 0x1000
    assert len(spi_subordinate.data) == test_data.num_bytes
    assert spi_subordinate.data == test_data.get_test_array()


@cocotb.test()
@cocotb.parametrize(num_bytes=range(1, NUM_BYTES+1))
async def read_test(dut, num_bytes):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_spi_bus_clock",
            mosi_name="io_spi_data0_manager_serial_out",
            miso_name="io_spi_data1_manager_serial_in",
            cs_name="o_spi_chip_select_neg",
        )
    )

    addr = 0x1000
    test_data = DummyData(num_bytes)
    spi_subordinate.num_bytes = test_data.num_bytes
    spi_subordinate.data = test_data.get_test_array()

    # step: read
    timeout = Timer(100, unit="us")
    read_task = cocotb.start_soon(axi_master.read(addr, num_bytes))
    trigger = await First(read_task, timeout)
    assert trigger != timeout
    if dut.spi_busy.value == True:
        timeout = Timer(100, unit="us")
        await First(FallingEdge(dut.spi_busy), timeout)
    assert spi_subordinate.opcode == SpiFlashMemory.read
    assert spi_subordinate.address == 0x1000
    data = read_task.result()
    assert list(data.data) == test_data.get_test_array()


@cocotb.test()
@cocotb.parametrize(num_bytes=[NUM_BYTES+2, NUM_BYTES*3, NUM_BYTES*3+1])
async def write_burst_test(dut, num_bytes):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut) # the reset is here, because otherwise the axi manager loggs too many resets

    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_spi_bus_clock",
            mosi_name="io_spi_data0_manager_serial_out",
            miso_name="io_spi_data1_manager_serial_in",
            cs_name="o_spi_chip_select_neg",
        )
    )

    addr = 0x1000
    length = 4
    test_data = DummyData(num_bytes)
    spi_subordinate.num_bytes = test_data.num_bytes

    # step: write
    timeout = Timer(100, unit="us")
    write_task = cocotb.start_soon(axi_master.write(addr, test_data.get_test_array()))
    trigger = await First(write_task, timeout)
    assert trigger != timeout
    if dut.spi_busy.value == True:
        await FallingEdge(dut.spi_busy)
    assert spi_subordinate.opcode == SpiFlashMemory.program
    assert spi_subordinate.address == 0x1000
    assert len(spi_subordinate.data) == test_data.num_bytes
    assert spi_subordinate.data == test_data.get_test_array()


@cocotb.test()
@cocotb.parametrize(num_bytes=[NUM_BYTES+2, NUM_BYTES*3, NUM_BYTES*3+1])
async def read_burst_test(dut, num_bytes):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.reset)
    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_spi_bus_clock",
            mosi_name="io_spi_data0_manager_serial_out",
            miso_name="io_spi_data1_manager_serial_in",
            cs_name="o_spi_chip_select_neg",
        )
    )

    addr = 0x1000
    test_data = DummyData(num_bytes)
    spi_subordinate.num_bytes = test_data.num_bytes
    spi_subordinate.data = test_data.get_test_array()

    # step: read
    timeout = Timer(100, unit="us")
    read_task = cocotb.start_soon(axi_master.read(addr, num_bytes))
    trigger = await First(read_task, timeout)
    assert trigger != timeout
    if dut.spi_busy.value == True:
        timeout = Timer(100, unit="us")
        await First(FallingEdge(dut.spi_busy), timeout)
    assert spi_subordinate.opcode == SpiFlashMemory.read
    assert spi_subordinate.address == 0x1000
    data = read_task.result()
    assert list(data.data) == test_data.get_test_array()


def test_memory_controller():
    """
    Integration test of all modules in memory controller.
    """
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [
        proj_path / "../../src/SPIController.v",
        proj_path / "../../src/SPITransmitter.v",
        proj_path / "../../src/AXIInterface.v",
        proj_path / "../../src/MemoryController.v",
    ]

    parameters = {}
    parameters["DATA_WIDTH"] = 32
    parameters["ADDR_WIDTH"] = 24
    extra_env = {f"PARAM_{k}": str(v) for k, v in parameters.items()}

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="MemoryController",
        always=True,
        waves=True,
        parameters=parameters,
    )
    runner.test(
        hdl_toplevel="MemoryController",
        test_module="test_memory_controller",
        parameters=parameters,
        waves=True,
        extra_env=extra_env,
    )


if __name__ == "__main__":
    test_memory_controller()
