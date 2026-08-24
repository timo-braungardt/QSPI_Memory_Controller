import os
import logging
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, First, ClockCycles
from cocotb.clock import Clock
from cocotbext.qspi import QSpiBus, QSpiConfig
from HelperClasses import QSpiFlashMemory


async def reset_dut(dut):
    dut.reset.value = 1
    await ClockCycles(dut.clk, 1, rising=True)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 1, rising=True)


@cocotb.test()
async def transmission_test(dut):
    qspi_subordinate = QSpiFlashMemory(
        QSpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_d1_name="io_dq1_manager_serial_out",
            miso_d0_name="io_dq0_manager_serial_in",
            d2_name="io_dq2",
            d3_name="io_dq3",
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
    qspi_subordinate.num_bytes = 4

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.opcode.value = 5
    dut.address.value = 0x800001
    dut.write_address.value = 0b1
    dut.write_data.value = 0b0
    dut.read_data.value = 0b0

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)

    timeout = Timer(100, unit="us")
    trigger = await First(dut.o_chip_select_neg.value_change, timeout)
    assert trigger != timeout

    assert qspi_subordinate.opcode == 0x05
    assert qspi_subordinate.address == 0x800001


@cocotb.test()
async def read_test(dut):

    qspi_subordinate = QSpiFlashMemory(
        QSpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_d1_name="io_dq1_manager_serial_out",
            miso_d0_name="io_dq0_manager_serial_in",
            d2_name="io_dq2",
            d3_name="io_dq3",
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
    qspi_subordinate.num_bytes = 4
    qspi_subordinate.data = [0x12, 0x34, 0x56, 0x78]

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.opcode.value = 0x03
    dut.address.value = 20

    dut.write_address.value = 0b1
    dut.write_data.value = 0b0
    dut.read_data.value = 0b1
    dut.num_bits.value = 32

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.o_chip_select_neg.value_change

    assert qspi_subordinate.opcode == 0x03
    assert qspi_subordinate.address == 20
    assert dut.buffer[0].value.to_unsigned() == 0x12
    assert dut.buffer[1].value.to_unsigned() == 0x34
    assert dut.buffer[2].value.to_unsigned() == 0x56
    assert dut.buffer[3].value.to_unsigned() == 0x78


@cocotb.test()
async def write_test(dut):

    qspi_subordinate = QSpiFlashMemory(
        QSpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_d1_name="io_dq1_manager_serial_out",
            miso_d0_name="io_dq0_manager_serial_in",
            d2_name="io_dq2",
            d3_name="io_dq3",
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
    qspi_subordinate.num_bytes = 2

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.opcode.value = 0x06

    dut.write_address.value = 0b0
    dut.write_data.value = 0b0
    dut.read_data.value = 0b0

    assert not qspi_subordinate.write_enable

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.o_chip_select_neg.value_change

    assert qspi_subordinate.opcode == 0x06
    assert qspi_subordinate.write_enable

    dut.opcode.value = 0x02
    dut.address.value = 21

    dut.write_address.value = 0b1
    dut.write_data.value = 0b1
    dut.read_data.value = 0b0
    dut.buffer[0].value = 0x80
    dut.buffer[1].value = 0x01
    dut.buffer[2].value = 0xFF
    dut.num_bits.value = 16

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.o_chip_select_neg.value_change

    assert qspi_subordinate.opcode == 0x02
    assert qspi_subordinate.address == 21
    assert qspi_subordinate.write_enable
    assert qspi_subordinate.data == [0x80, 0x01]


def test_quad_spi():
    """
    Test if the basics of the Quad SPI protocol are implemented correctly.
    """
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../../src/QuadSPI.v"]

    runner = get_runner(sim)
    runner.build(sources=sources, hdl_toplevel="QuadSPI", always=True, waves=True)
    runner.test(hdl_toplevel="QuadSPI", test_module="test_quad_spi", waves=True)


if __name__ == "__main__":
    test_quad_spi()
