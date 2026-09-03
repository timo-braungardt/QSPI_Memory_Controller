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


def generate_test_array(num_bytes):
    array = bytearray()
    for _ in range(num_bytes):
        array.append(random.randrange(256))
    return array


@cocotb.test()
async def write_test(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")


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

    await reset_dut(dut)

    addr = 0x1000
    length = 4
    test_data = generate_test_array(length)
    spi_subordinate.length = length

    # step: write
    timeout = Timer(100, unit="us")
    write_task = cocotb.start_soon(axi_master.write(addr, test_data))
    trigger = await First(write_task, timeout)
    assert trigger != timeout
    assert spi_subordinate.data == test_data


@cocotb.test()
async def read_test(dut):
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
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    addr = 0x1000
    length = 4
    test_data = generate_test_array(length)
    spi_subordinate.length = length
    spi_subordinate.data = test_data

    # step: read
    timeout = Timer(100, unit="us")
    read_task = cocotb.start_soon(axi_master.read(addr, length))
    trigger = await First(read_task, timeout)
    assert trigger != timeout
    data = read_task.result()
    assert data.data == test_data


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
