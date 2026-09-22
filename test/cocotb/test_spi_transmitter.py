import os
from pathlib import Path
import pytest
import random
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import Timer, First, ClockCycles, RisingEdge, FallingEdge
from cocotbext.spi import SpiBus
from cocotbext.qspi import QSpiBus, QSpiConfig
from HelperClasses import SpiFlashFiFo, QSpiFlashFiFo


async def reset_dut(dut):
    dut.reset_neg.value = 0
    await ClockCycles(dut.clk, 4, rising=True)
    dut.reset_neg.value = 1
    await ClockCycles(dut.clk, 1, rising=True)


async def wait_for_idle(dut):
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout


async def trigger_go(dut):
    dut.start_transmission.value = 0
    await ClockCycles(dut.clk, 5, rising=True)
    dut.start_transmission.value = 1
    await ClockCycles(dut.clk, 1, rising=True)
    dut.start_transmission.value = 0


def generate_test_array(num_bytes):
    array = bytearray()
    for _ in range(num_bytes):
        array.append(random.randrange(256))
    return array


def get_test_number(test_array):
    number = 0
    for i in test_array:
        number = (number << 8) + i
    return number


async def handle_write_burst(dut, subordinate, test_data):
    subordinate.num_bytes = len(test_data)
    num_loops = len(test_data)

    for i in range(1, num_loops):
        await RisingEdge(dut.o_need_next_byte)
        dut.i_data_write.value = test_data[i]
        if (num_loops - i - 1) == 0:
            dut.i_last_word.value = True
    await RisingEdge(dut.clk)
    dut.i_last_word.value = True
    await wait_for_idle(dut)


async def handle_read_burst(dut, subordinate):
    num_bytes = len(subordinate.data)
    recieved_data = []

    for i in range(num_bytes):
        if (num_bytes - i - 1) == 0:
            dut.i_last_word.value = True
        # falling edge because we do not trigger on the signal but poll the value later in the design
        await FallingEdge(dut.o_recieved_next_byte)
        recieved_data.append(dut.o_data_read.value.to_unsigned())
    await RisingEdge(dut.clk)
    dut.i_last_word.value = True
    await wait_for_idle(dut)
    return recieved_data


@cocotb.test()
async def write_test_spi(dut):
    spi_subordinate = SpiFlashFiFo(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_data0_manager_serial_out",
            miso_name="io_data1_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )
    test_data = random.randrange(256)
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.i_opcode.value = 0x02
    dut.i_address.value = 0x800001
    dut.i_last_word.value = True
    dut.i_data_write.value = test_data

    dut.i_config_read_data.value = False
    dut.i_config_write_data.value = True
    dut.i_config_write_address.value = True
    dut.i_config_quad_mode.value = 0b000
    dut.i_config_dummy_cycles.value = 0

    spi_subordinate.write_enable = True
    spi_subordinate.num_bytes = 1
    await trigger_go(dut)
    await wait_for_idle(dut)

    [opcode, address] = await spi_subordinate.get_content()
    assert opcode == 0x02
    assert address == 0x800001
    assert spi_subordinate.data == [test_data]


@cocotb.test()
async def read_test_spi(dut):
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

    dut.i_opcode.value = 0x03
    dut.i_address.value = 0x800001
    dut.i_last_word.value = True

    dut.i_config_read_data.value = True
    dut.i_config_write_data.value = False
    dut.i_config_write_address.value = True
    dut.i_config_quad_mode.value = 0b000
    dut.i_config_dummy_cycles.value = 0

    spi_subordinate.num_bytes = 1
    test_data = random.randrange(256)
    spi_subordinate.data = [test_data]
    await trigger_go(dut)
    await wait_for_idle(dut)

    [opcode, address] = await spi_subordinate.get_content()
    assert opcode == 0x03
    assert address == 0x800001
    assert dut.o_data_read.value.to_unsigned() == test_data


@cocotb.test()
async def write_test_qspi(dut):
    qspi_subordinate = QSpiFlashFiFo(
        QSpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_d0_name="io_data0_manager_serial_out",
            miso_d1_name="io_data1_manager_serial_in",
            d2_name="io_data2",
            d3_name="io_data3",
            cs_name="o_chip_select_neg",
        ),
        QSpiConfig(
            word_width=8,
            sclk_freq=20e6,
            cpol=0,
            cpha=0,
            msb_first=True,
            frame_spacing_ns=10,
            ignore_rx_value=None,
            cs_active_low=True,
            is_quad_mode=True,
        ),
    )
    test_data = random.randrange(256)
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.i_opcode.value = 0x02
    dut.i_address.value = 0x800001
    dut.i_last_word.value = True
    dut.i_data_write.value = test_data

    dut.i_config_read_data.value = False
    dut.i_config_write_data.value = True
    dut.i_config_write_address.value = True
    dut.i_config_quad_mode.value = 0b111
    dut.i_config_dummy_cycles.value = 0

    qspi_subordinate.write_enable = True
    qspi_subordinate.num_bytes = 1
    await trigger_go(dut)
    await wait_for_idle(dut)

    assert qspi_subordinate.opcode == 0x02
    assert qspi_subordinate.address == 0x800001
    assert qspi_subordinate.data == [test_data]


@cocotb.test()
async def read_test_qspi(dut):
    qspi_subordinate = QSpiFlashFiFo(
        QSpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_d0_name="io_data0_manager_serial_out",
            miso_d1_name="io_data1_manager_serial_in",
            d2_name="io_data2",
            d3_name="io_data3",
            cs_name="o_chip_select_neg",
        ),
        QSpiConfig(
            word_width=8,
            sclk_freq=20e6,
            cpol=0,
            cpha=0,
            msb_first=True,
            frame_spacing_ns=10,
            ignore_rx_value=None,
            cs_active_low=True,
            is_quad_mode=True,
        ),
    )
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.i_opcode.value = 0x03
    dut.i_address.value = 0x800001
    dut.i_last_word.value = True

    dut.i_config_read_data.value = True
    dut.i_config_write_data.value = False
    dut.i_config_write_address.value = True
    dut.i_config_quad_mode.value = 0b111
    dut.i_config_dummy_cycles.value = 0

    qspi_subordinate.num_bytes = 1
    test_data = random.randrange(256)
    qspi_subordinate.data = [test_data]
    await trigger_go(dut)
    await wait_for_idle(dut)

    assert qspi_subordinate.opcode == 0x03
    assert qspi_subordinate.address == 0x800001
    assert dut.o_data_read.value.to_unsigned() == test_data


@cocotb.test()
@cocotb.parametrize(num_bytes=range(2, 5))
async def write_test_burst_qspi(dut, num_bytes):
    qspi_subordinate = QSpiFlashFiFo(
        QSpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_d0_name="io_data0_manager_serial_out",
            miso_d1_name="io_data1_manager_serial_in",
            d2_name="io_data2",
            d3_name="io_data3",
            cs_name="o_chip_select_neg",
        ),
        QSpiConfig(
            word_width=8,
            sclk_freq=20e6,
            cpol=0,
            cpha=0,
            msb_first=True,
            frame_spacing_ns=10,
            ignore_rx_value=None,
            cs_active_low=True,
            is_quad_mode=True,
        ),
    )
    test_data = generate_test_array(num_bytes)
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.i_opcode.value = 0x02
    dut.i_address.value = 0x800001
    dut.i_last_word.value = False
    dut.i_data_write.value = test_data[0]

    dut.i_config_read_data.value = False
    dut.i_config_write_data.value = True
    dut.i_config_write_address.value = True
    dut.i_config_quad_mode.value = 0b111
    dut.i_config_dummy_cycles.value = 0

    qspi_subordinate.write_enable = True
    qspi_subordinate.num_bytes = num_bytes
    await trigger_go(dut)
    await handle_write_burst(dut, qspi_subordinate, test_data)

    assert qspi_subordinate.opcode == 0x02
    assert qspi_subordinate.address == 0x800001
    assert len(qspi_subordinate.data) == len(test_data)
    assert list(qspi_subordinate.data) == list(test_data)


@cocotb.test()
@cocotb.parametrize(num_bytes=range(2, 5))
async def read_test_burst_qspi(dut, num_bytes):
    qspi_subordinate = QSpiFlashFiFo(
        QSpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_d0_name="io_data0_manager_serial_out",
            miso_d1_name="io_data1_manager_serial_in",
            d2_name="io_data2",
            d3_name="io_data3",
            cs_name="o_chip_select_neg",
        ),
        QSpiConfig(
            word_width=8,
            sclk_freq=20e6,
            cpol=0,
            cpha=0,
            msb_first=True,
            frame_spacing_ns=10,
            ignore_rx_value=None,
            cs_active_low=True,
            is_quad_mode=True,
        ),
    )
    test_data = generate_test_array(num_bytes)
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.i_opcode.value = 0x03
    dut.i_address.value = 0x800001
    dut.i_last_word.value = False

    dut.i_config_read_data.value = True
    dut.i_config_write_data.value = False
    dut.i_config_write_address.value = True
    dut.i_config_quad_mode.value = 0b111
    dut.i_config_dummy_cycles.value = 0

    qspi_subordinate.write_enable = False
    qspi_subordinate.data = test_data
    qspi_subordinate.num_bytes = num_bytes
    await trigger_go(dut)
    recieved_data = await handle_read_burst(dut, qspi_subordinate)

    assert qspi_subordinate.opcode == 0x03
    assert qspi_subordinate.address == 0x800001
    assert recieved_data == list(test_data)


def test_spi_transmitter():
    """
    Test if the basics of the SPI protocol are implemented correctly.
    """
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../../src/SPITransmitter.v"]

    runner = get_runner(sim)
    runner.build(sources=sources, hdl_toplevel="SPITransmitter", always=True, waves=True)
    runner.test(hdl_toplevel="SPITransmitter", test_module="test_spi_transmitter", waves=True)


if __name__ == "__main__":
    test_spi_transmitter()
