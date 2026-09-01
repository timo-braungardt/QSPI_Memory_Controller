import os
from pathlib import Path
import pytest
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import Timer, First, ClockCycles, RisingEdge
from cocotbext.spi import SpiBus
from cocotbext.qspi import QSpiBus, QSpiConfig
from HelperClasses import SpiFlashMemory, QSpiFlashMemory

DATA_WIDTH = int(os.environ.get("PARAM_DATA_WIDTH", 32))
NUM_BYTES = DATA_WIDTH // 8


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


def get_test_array():
    if NUM_BYTES == 4:
        return [0x12, 0x34, 0x56, 0x78]
    elif NUM_BYTES == 8:
        return [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xFF]
    else:
        raise NotImplementedError(f"Test Data can only be created for 32 or 64 bit data width!")


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

    for i in range(num_loops):
        if last_num_bytes == 0 and (num_loops - i) == 0:
            dut.i_last_word.value = True
        await RisingEdge(dut.o_next_word)
    await RisingEdge(dut.clk)
    dut.i_last_word.value = True
    if last_num_bytes != 0:
        dut.i_num_bytes.value = last_num_bytes -1
    await wait_for_idle(dut)


@cocotb.test()
@cocotb.parametrize(num_bytes=range(NUM_BYTES))
async def write_test_4bytes_spi(dut, num_bytes):
    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_data0_manager_serial_out",
            miso_name="io_data1_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )
    test_data = get_test_array()
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.i_opcode.value = 0x02
    dut.i_address.value = 0x800001
    dut.i_last_word.value = True
    dut.i_data_write.value = get_test_number(get_test_array())

    dut.i_config_read_data.value = False
    dut.i_config_write_data.value = True
    dut.i_config_write_address.value = True
    dut.i_config_quad_mode.value = 0b000
    dut.i_num_bytes.value = num_bytes
    dut.i_config_dummy_cycles.value = 0

    spi_subordinate.write_enable = True
    spi_subordinate.num_bytes = num_bytes+1
    await trigger_go(dut)
    await wait_for_idle(dut)

    [opcode, address] = await spi_subordinate.get_content()
    assert opcode == 0x02
    assert address == 0x800001
    lower_bound = len(test_data) - num_bytes - 1
    assert spi_subordinate.data == test_data[lower_bound:]


@cocotb.test()
@cocotb.parametrize(num_bytes=range(NUM_BYTES))
async def read_test_4bytes_spi(dut, num_bytes):
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

    dut.i_opcode.value = 0x03
    dut.i_address.value = 0x800001
    dut.i_last_word.value = True

    dut.i_config_read_data.value = True
    dut.i_config_write_data.value = False
    dut.i_config_write_address.value = True
    dut.i_config_quad_mode.value = 0b000
    dut.i_num_bytes.value = num_bytes
    dut.i_config_dummy_cycles.value = 0

    spi_subordinate.num_bytes = num_bytes+1
    spi_subordinate.data = get_test_array()
    await trigger_go(dut)
    await wait_for_idle(dut)

    [opcode, address] = await spi_subordinate.get_content()
    assert opcode == 0x03
    assert address == 0x800001
    test_data = 0
    for i in spi_subordinate.data[:num_bytes+1]:
        test_data = (test_data << 8) + i
    assert dut.o_data_read.value.to_unsigned() == test_data


@cocotb.test()
@cocotb.parametrize(num_bytes=range(NUM_BYTES))
async def write_test_4bytes_qspi(dut, num_bytes):
    qspi_subordinate = QSpiFlashMemory(
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
    test_data = get_test_array()
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.i_opcode.value = 0x02
    dut.i_address.value = 0x800001
    dut.i_last_word.value = True
    dut.i_data_write.value = get_test_number(get_test_array())

    dut.i_config_read_data.value = False
    dut.i_config_write_data.value = True
    dut.i_config_write_address.value = True
    dut.i_config_quad_mode.value = 0b111
    dut.i_num_bytes.value = num_bytes
    dut.i_config_dummy_cycles.value = 0

    qspi_subordinate.write_enable = True
    qspi_subordinate.num_bytes = num_bytes+1
    await trigger_go(dut)
    await wait_for_idle(dut)

    assert qspi_subordinate.opcode == 0x02
    assert qspi_subordinate.address == 0x800001
    lower_bound = len(test_data) - num_bytes - 1
    assert qspi_subordinate.data == test_data[lower_bound:]


@cocotb.test()
@cocotb.parametrize(num_bytes=range(NUM_BYTES))
async def read_test_4bytes_qspi(dut, num_bytes):
    qspi_subordinate = QSpiFlashMemory(
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
    dut.i_num_bytes.value = num_bytes
    dut.i_config_dummy_cycles.value = 0

    qspi_subordinate.num_bytes = num_bytes+1
    qspi_subordinate.data = get_test_array()
    await trigger_go(dut)
    await wait_for_idle(dut)

    assert qspi_subordinate.opcode == 0x03
    assert qspi_subordinate.address == 0x800001
    test_data = 0
    for i in qspi_subordinate.data[:num_bytes+1]:
        test_data = (test_data << 8) + i
    assert dut.o_data_read.value.to_unsigned() == test_data


@cocotb.test()
@cocotb.parametrize(num_bytes=range(NUM_BYTES*2, NUM_BYTES*3+1))
async def write_test_burst_qspi(dut, num_bytes):
    qspi_subordinate = QSpiFlashMemory(
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
    test_data = [0x81] * num_bytes
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.i_opcode.value = 0x02
    dut.i_address.value = 0x800001
    dut.i_last_word.value = False
    dut.i_num_bytes.value = NUM_BYTES -1
    dut.i_data_write.value = get_test_number(test_data[0:NUM_BYTES])

    dut.i_config_read_data.value = False
    dut.i_config_write_data.value = True
    dut.i_config_write_address.value = True
    dut.i_config_quad_mode.value = 0b111
    dut.i_config_dummy_cycles.value = 0

    qspi_subordinate.write_enable = True
    await trigger_go(dut)
    await handle_burst(dut, qspi_subordinate, test_data)

    assert qspi_subordinate.opcode == 0x02
    assert qspi_subordinate.address == 0x800001
    assert len(qspi_subordinate.data) == len(test_data)
    assert qspi_subordinate.data == test_data


@cocotb.test()
@cocotb.parametrize(num_bytes=range(NUM_BYTES*2, NUM_BYTES*3+1))
async def read_test_burst_qspi(dut, num_bytes):
    qspi_subordinate = QSpiFlashMemory(
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
    test_data = [0x81] * num_bytes
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
    await trigger_go(dut)
    await handle_burst(dut, qspi_subordinate, test_data)

    assert qspi_subordinate.opcode == 0x03
    assert qspi_subordinate.address == 0x800001


@pytest.mark.parametrize("data_width", [32, 64])
def test_spi_transmitter(data_width):
    """
    Test if the basics of the SPI protocol are implemented correctly.
    """
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../../src/SPITransmitter.v"]

    parameters = {}
    parameters["DATA_WIDTH"] = data_width
    extra_env = {f"PARAM_{k}": str(v) for k, v in parameters.items()}

    runner = get_runner(sim)
    runner.build(sources=sources, hdl_toplevel="SPITransmitter", always=True, waves=True, parameters=parameters)
    runner.test(hdl_toplevel="SPITransmitter", test_module="test_spi_transmitter", parameters=parameters, waves=True, extra_env=extra_env)


if __name__ == "__main__":
    test_spi_transmitter()
