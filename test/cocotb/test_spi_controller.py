import os
import logging
from pathlib import Path
import random
import pytest
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, First, ClockCycles, RisingEdge
from cocotb.clock import Clock
from collections import deque
from cocotbext.spi import SpiBus
from HelperClasses import SpiFlashMemory

DATA_WIDTH = int(os.environ.get("PARAM_DATA_WIDTH", 32))
NUM_BYTES = DATA_WIDTH // 8


async def reset_dut(dut):
    dut.reset_neg.value = 0
    await ClockCycles(dut.clk, 2, rising=True)
    dut.reset_neg.value = 1
    await ClockCycles(dut.clk, 1, rising=True)


async def wait_for_idle(dut):
    if dut.o_chip_select_neg.value == False:
        await dut.o_chip_select_neg.value_change


async def trigger_go(dut):
    await wait_for_idle(dut)
    dut.go.value = 0
    await ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0


def generate_test_array(num_bytes):
    array = []
    for _ in range(num_bytes):
        array.append(random.randrange(256))
    return array


def get_test_number(test_array):
    number = 0
    for i in test_array:
        number = (number << 8) + i
    return number


async def handle_burst(dut, subordinate, test_data):
    subordinate.num_bytes = len(test_data)
    dut.i_num_bytes.value = NUM_BYTES -1
    num_loops = len(test_data) // NUM_BYTES
    last_num_bytes = len(test_data) - (NUM_BYTES * num_loops)

    for _ in range(num_loops):
        await RisingEdge(dut.o_next_word)
    await RisingEdge(dut.clk)
    dut.i_last_word.value = True
    dut.i_num_bytes.value = last_num_bytes
    await wait_for_idle(dut)


@cocotb.test()
async def spi_transmission_test(dut):
    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_data0_manager_serial_out",
            miso_name="io_data1_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await reset_dut(dut)

    dut.config_quad_mode.value = False
    spi_subordinate.num_bytes = 1

    dut.i_address.value = 0x800001
    dut.i_write_enable.value = 0b0
    dut.i_last_word.value = True
    dut.i_num_bytes.value = 0b000

    await trigger_go(dut)
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout

    [opcode, address] = await spi_subordinate.get_content()
    assert opcode == 0x03
    assert address == 0x800001


@cocotb.test()
@cocotb.parametrize(num_bytes=range(NUM_BYTES))
async def spi_read_test(dut, num_bytes):
    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_data0_manager_serial_out",
            miso_name="io_data1_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )
    test_data = generate_test_array(num_bytes+1)
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await reset_dut(dut)

    dut.config_quad_mode.value = False

    dut.i_address.value = 20
    dut.i_write_enable.value = False
    dut.i_last_word.value = True
    dut.i_num_bytes.value = num_bytes

    spi_subordinate.num_bytes = num_bytes+1
    spi_subordinate.data = test_data

    await trigger_go(dut)
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout

    [opcode, address] = await spi_subordinate.get_content()
    assert opcode == SpiFlashMemory.read
    assert address == 20
    assert dut.o_data_read.value == get_test_number(test_data)


@cocotb.test()
@cocotb.parametrize(num_bytes=range(NUM_BYTES))
async def spi_write_test(dut, num_bytes):
    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_data0_manager_serial_out",
            miso_name="io_data1_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )
    test_data = generate_test_array(num_bytes+1)
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await reset_dut(dut)

    dut.config_quad_mode.value = False

    dut.i_address.value = 21
    dut.i_data_write.value = get_test_number(test_data)
    dut.i_write_enable.value = True
    dut.i_last_word.value = True
    dut.i_num_bytes.value = num_bytes

    spi_subordinate.num_bytes = num_bytes+1

    assert not spi_subordinate.write_enable
    await trigger_go(dut)
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout

    assert spi_subordinate.opcode == SpiFlashMemory.program
    assert spi_subordinate.address == 21
    assert spi_subordinate.write_enable
    assert spi_subordinate.data == test_data


@cocotb.test()
async def spi_dummy_cycles_test(dut):
    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_data0_manager_serial_out",
            miso_name="io_data1_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await reset_dut(dut)

    dut.config_quad_mode.value = False
    dut.config_dummy_cycles.value = 8

    dut.i_address.value = 20
    dut.i_write_enable.value = False
    dut.i_last_word.value = True
    dut.i_num_bytes.value = 0b000

    spi_subordinate.num_bytes = 2
    spi_subordinate.data = [0x12, 0x34, 0x56]

    await trigger_go(dut)
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout

    [opcode, address] = await spi_subordinate.get_content()
    assert opcode == SpiFlashMemory.read
    assert address == 20
    assert dut.o_data_read.value == 0x34


@pytest.mark.parametrize("data_width", [32, 64])
def test_spi_controller(data_width):
    """
    Test the spi controller against cocotb memory models.
    """
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../../src/SPIController.v", proj_path / "../../src/SPITransmitter.v"]

    parameters = {}
    parameters["DATA_WIDTH"] = data_width
    parameters["ADDRESS_WIDTH"] = 24
    extra_env = {f"PARAM_{k}": str(v) for k, v in parameters.items()}

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="SPIController",
        always=True,
        waves=True,
        parameters=parameters,
    )
    runner.test(hdl_toplevel="SPIController", test_module="test_spi_controller", parameters=parameters, waves=True, extra_env=extra_env)


if __name__ == "__main__":
    test_spi_controller()
