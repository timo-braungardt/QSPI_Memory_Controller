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
from cocotbext.spi import SpiBus
from HelperClasses import SpiFlashFiFo, SpiFlashMemory, DummyData

DATA_WIDTH = int(os.environ.get("PARAM_DATA_WIDTH", 32))
DATA_WIDTH_BYTES = DATA_WIDTH // 8


async def reset_dut(dut):
    dut.reset_neg.value = 0
    await ClockCycles(dut.clk, 2, rising=True)
    dut.reset_neg.value = 1
    await ClockCycles(dut.clk, 1, rising=True)


async def wait_for_idle(dut):
    if dut.o_busy.value == True:
        timeout = Timer(100, unit="us")
        trigger = await First(dut.o_busy.value_change, timeout)
        assert trigger != timeout


async def trigger_go(dut):
    await wait_for_idle(dut)
    dut.go.value = 0
    await ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0


async def handle_write_burst(dut, subordinate, test_data):
    subordinate.num_bytes = test_data.num_bytes
    dut.i_num_bytes.value = test_data.num_bytes
    num_loops = test_data.num_bytes // DATA_WIDTH_BYTES
    last_num_bytes = test_data.num_bytes - (DATA_WIDTH_BYTES * num_loops)

    for i in range(1, num_loops):
        timeout = Timer(8, unit="us")
        trigger = await First(RisingEdge(dut.o_next_word), timeout)
        assert trigger != timeout
        if i == num_loops - 2:
            dut.i_last_word.value = True

        dut.i_data_write.value = test_data.get_test_number_word(i * DATA_WIDTH_BYTES)

    if last_num_bytes != 0:
        timeout = Timer(100, unit="us")
        trigger = await First(RisingEdge(dut.o_next_word), timeout)
        assert trigger != timeout
        dut.i_data_write.value = test_data.get_test_number_word(
            num_loops * DATA_WIDTH_BYTES, last_num_bytes
        )

    await wait_for_idle(dut)


async def handle_read_burst(dut, subordinate, test_data):
    subordinate.num_bytes = test_data.num_bytes
    dut.i_num_bytes.value = test_data.num_bytes
    num_loops = test_data.num_bytes // DATA_WIDTH_BYTES
    last_num_bytes = test_data.num_bytes - (DATA_WIDTH_BYTES * num_loops)

    for i in range(num_loops):
        timeout = Timer(100, unit="us")
        trigger = await First(FallingEdge(dut.o_recieved_next_word), timeout)
        assert trigger != timeout
        if i == num_loops - 2:
            dut.i_last_word.value = True

        assert dut.o_data_read.value == test_data.get_test_number_word(i * DATA_WIDTH_BYTES)
        dut.data_read_reg.value = 0  # ToDo: the other bytes have to be masked (issue #18)

    if last_num_bytes != 0:
        timeout = Timer(100, unit="us")
        trigger = await First(FallingEdge(dut.o_recieved_next_word), timeout)
        assert trigger != timeout
        assert dut.o_data_read.value == test_data.get_test_number_word(
            num_loops * DATA_WIDTH_BYTES, last_num_bytes
        )

    await wait_for_idle(dut)


@cocotb.test()
async def spi_transmission_test(dut):
    spi_subordinate = SpiFlashFiFo(
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
@cocotb.parametrize(num_bytes=range(1, DATA_WIDTH_BYTES + 1))
async def spi_read_test(dut, num_bytes):
    spi_subordinate = SpiFlashFiFo(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_data0_manager_serial_out",
            miso_name="io_data1_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )
    test_data = DummyData(num_bytes)
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await reset_dut(dut)

    dut.config_quad_mode.value = False

    dut.i_address.value = 20
    dut.i_write_enable.value = False
    dut.i_last_word.value = True
    dut.i_num_bytes.value = num_bytes - 1

    spi_subordinate.num_bytes = num_bytes
    spi_subordinate.data = test_data.get_test_array()

    await trigger_go(dut)
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout

    [opcode, address] = await spi_subordinate.get_content()
    assert opcode == SpiFlashFiFo.read
    assert address == 20
    assert dut.o_data_read.value == test_data.get_test_number()


@cocotb.test()
@cocotb.parametrize(num_bytes=range(1, DATA_WIDTH_BYTES + 1))
async def spi_write_test(dut, num_bytes):
    spi_subordinate = SpiFlashFiFo(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_data0_manager_serial_out",
            miso_name="io_data1_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )
    test_data = DummyData(num_bytes)
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await reset_dut(dut)

    dut.config_quad_mode.value = False

    dut.i_address.value = 21
    dut.i_data_write.value = test_data.get_test_number()
    dut.i_write_enable.value = True
    dut.i_last_word.value = True
    dut.i_num_bytes.value = num_bytes - 1

    spi_subordinate.num_bytes = num_bytes

    assert not spi_subordinate.write_enable
    await trigger_go(dut)
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout

    assert spi_subordinate.opcode == SpiFlashFiFo.program
    assert spi_subordinate.address == 21
    assert spi_subordinate.write_enable
    assert spi_subordinate.data == test_data.get_test_array()


@cocotb.test()
@cocotb.parametrize(num_bytes=[4])
async def spi_endianness_test(dut, num_bytes):
    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_data0_manager_serial_out",
            miso_name="io_data1_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )
    test_data = DummyData(num_bytes)
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await reset_dut(dut)

    dut.config_quad_mode.value = False

    # write data
    dut.i_address.value = 0x20
    dut.i_data_write.value = test_data.get_test_number()
    dut.i_write_enable.value = True
    dut.i_last_word.value = True
    dut.i_num_bytes.value = num_bytes - 1

    spi_subordinate.num_bytes = num_bytes

    assert not spi_subordinate.write_enable
    await trigger_go(dut)
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout

    assert spi_subordinate.opcode == SpiFlashMemory.program
    assert spi_subordinate.address == 0x20
    assert spi_subordinate.write_enable
    assert spi_subordinate.data[0x20 : 0x20 + num_bytes] == test_data.get_test_array()

    # read back data
    dut.i_write_enable.value = False
    dut.i_address.value = 0x21
    dut.i_num_bytes.value = 1
    spi_subordinate.num_bytes = 2

    await trigger_go(dut)
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout

    [opcode, address] = await spi_subordinate.get_content()
    assert opcode == SpiFlashMemory.read
    assert address == dut.i_address.value
    assert dut.o_data_read.value.to_unsigned() == test_data.get_test_number_word(1, 2)


@cocotb.test()
@cocotb.parametrize(num_bytes=range(DATA_WIDTH_BYTES, DATA_WIDTH_BYTES * 2))
async def write_test_burst_qspi(dut, num_bytes):
    spi_subordinate = SpiFlashFiFo(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_data0_manager_serial_out",
            miso_name="io_data1_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )
    test_data = DummyData(num_bytes, DATA_WIDTH_BYTES)
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.i_address.value = 0x800001
    dut.i_write_enable.value = True
    dut.i_last_word.value = False
    dut.i_num_bytes.value = num_bytes - 1
    dut.i_data_write.value = test_data.get_test_number_word(0)

    dut.config_quad_mode.value = False

    await trigger_go(dut)
    # write enable
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout
    # the write command
    await handle_write_burst(dut, spi_subordinate, test_data)

    assert spi_subordinate.opcode == SpiFlashFiFo.program
    assert spi_subordinate.write_enable
    assert spi_subordinate.address == 0x800001
    assert len(spi_subordinate.data) == test_data.num_bytes
    assert spi_subordinate.data == test_data.get_test_array()


@cocotb.test()
@cocotb.parametrize(num_bytes=range(DATA_WIDTH_BYTES, DATA_WIDTH_BYTES * 2))
async def read_test_burst_qspi(dut, num_bytes):
    spi_subordinate = SpiFlashFiFo(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_data0_manager_serial_out",
            miso_name="io_data1_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )
    test_data = DummyData(num_bytes, DATA_WIDTH_BYTES)
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.i_address.value = 0x800001
    dut.i_write_enable.value = False
    dut.i_last_word.value = False
    dut.i_num_bytes.value = num_bytes - 1

    dut.config_quad_mode.value = False

    spi_subordinate.data = test_data.get_test_array()
    await trigger_go(dut)
    await handle_read_burst(dut, spi_subordinate, test_data)

    assert spi_subordinate.opcode == SpiFlashFiFo.read
    assert spi_subordinate.address == 0x800001


@cocotb.test()
async def spi_dummy_cycles_test(dut):
    spi_subordinate = SpiFlashFiFo(
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
    assert opcode == SpiFlashFiFo.read
    assert address == 20
    assert dut.o_data_read.value == 0x34


@cocotb.test()
async def qspi_enable_test(dut):
    spi_subordinate = SpiFlashFiFo(
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

    dut.i_address.value = 0
    dut.i_data_write.value = 0
    dut.i_write_enable.value = False
    dut.config_is_config_operation.value = True
    dut.config_quad_mode.value = 0b000
    dut.i_last_word.value = True
    dut.i_num_bytes.value = 0b000

    assert spi_subordinate.quad_enable_bit == False

    # step: set QUADIT bit in config register 1
    await trigger_go(dut)
    timeout = Timer(100, unit="us")
    trigger = await First(FallingEdge(dut.o_busy), timeout)
    assert trigger != timeout

    assert spi_subordinate.quad_enable_bit == True


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
    parameters["ADDRESS_LENGTH"] = 24
    extra_env = {f"PARAM_{k}": str(v) for k, v in parameters.items()}

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="SPIController",
        always=True,
        waves=True,
        parameters=parameters,
    )
    runner.test(
        hdl_toplevel="SPIController",
        test_module="test_spi_controller",
        parameters=parameters,
        waves=True,
        extra_env=extra_env,
    )


if __name__ == "__main__":
    test_spi_controller()
