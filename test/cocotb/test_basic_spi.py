import os
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import Timer, First, ClockCycles, RisingEdge
from cocotbext.spi import SpiBus
from HelperClasses import SpiFlashMemory

async def reset_dut(dut):
    dut.reset.value = 1
    await ClockCycles(dut.clk, 1, rising=True)
    dut.reset.value = 0
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


@cocotb.test()
async def transmission_test(dut):
    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_manager_serial_out",
            miso_name="io_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)
    
    dut.opcode.value = 0x81
    dut.address.value = 0x800001

    dut.write_address.value = 0b1
    dut.write_data.value = 0b0
    dut.read_data.value = 0b0

    await trigger_go(dut)
    await ClockCycles(dut.clk, 2, rising=True)
    await dut.o_chip_select_neg.value_change
    [opcode, address] = await spi_subordinate.get_content()
    assert opcode == 0x81
    assert address == 0x800001


@cocotb.test()
async def timing_read_test(dut):
    timeout = Timer(100, unit="us")

    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_manager_serial_out",
            miso_name="io_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.opcode.value = SpiFlashMemory.read
    dut.address.value = 0x000000

    dut.write_address.value = 0b1
    dut.write_data.value = 0b0
    dut.read_data.value = 0b1
    dut.num_bits.value = 16
    spi_subordinate.num_bytes = 16 // 8
    spi_subordinate.data = [0x80, 0x01]

    num_clock_cycles = 8 + 24 + 16

    await trigger_go(dut)

    trigger = await First(ClockCycles(dut.o_bus_clock, num_clock_cycles, rising=True), timeout)
    assert trigger != timeout
    assert dut.o_chip_select_neg.value == False

    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout


@cocotb.test()
async def timing_write_test(dut):
    timeout = Timer(100, unit="us")

    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_manager_serial_out",
            miso_name="io_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.opcode.value = SpiFlashMemory.program
    dut.address.value = 0x000000

    dut.write_address.value = 0b1
    dut.write_data.value = 0b1
    dut.read_data.value = 0b0
    dut.num_bits.value = 16
    spi_subordinate.num_bytes = 16 // 8
    # force write enable, we just want the length of the write command
    spi_subordinate.write_enable = True
    dut.buffer[0].value = 0x80
    dut.buffer[1].value = 0x01

    num_clock_cycles = 8 + 24 + 16

    await trigger_go(dut)

    trigger = await First(ClockCycles(dut.o_bus_clock, num_clock_cycles, rising=True), timeout)
    assert trigger != timeout
    assert dut.o_chip_select_neg.value == False

    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout


@cocotb.test()
async def read_test(dut):
    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_manager_serial_out",
            miso_name="io_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.opcode.value = SpiFlashMemory.read
    dut.address.value = 20
    dut.write_address.value = 0b1
    dut.write_data.value = 0b0
    dut.read_data.value = 0b1
    dut.num_bits.value = 32
    spi_subordinate.num_bytes = 32 // 8
    spi_subordinate.data = [0x12, 0x34, 0x56, 0x78]

    await trigger_go(dut)
    await ClockCycles(dut.clk, 2, rising=True)
    await dut.o_chip_select_neg.value_change
    [opcode, address] = await spi_subordinate.get_content()

    assert opcode == SpiFlashMemory.read
    assert address == 20

    assert dut.buffer[0].value.to_unsigned() == 0x12
    assert dut.buffer[1].value.to_unsigned() == 0x34
    assert dut.buffer[2].value.to_unsigned() == 0x56
    assert dut.buffer[3].value.to_unsigned() == 0x78


@cocotb.test()
async def write_test(dut):

    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_manager_serial_out",
            miso_name="io_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.opcode.value = SpiFlashMemory.write_enable
    dut.write_address.value = 0b0
    dut.write_data.value = 0b0
    dut.read_data.value = 0b0

    assert not spi_subordinate.write_enable

    await trigger_go(dut)
    await ClockCycles(dut.clk, 2, rising=True)
    await dut.o_chip_select_neg.value_change

    assert spi_subordinate.opcode == SpiFlashMemory.write_enable
    assert spi_subordinate.write_enable

    dut.opcode.value = SpiFlashMemory.program
    dut.address.value = 21

    dut.write_address.value = 0b1
    dut.write_data.value = 0b1
    dut.read_data.value = 0b0
    dut.buffer[0].value = 0x80
    dut.buffer[1].value = 0x01
    dut.buffer[2].value = 0xFF
    dut.num_bits.value = 16
    spi_subordinate.num_bytes = 16 // 8

    await trigger_go(dut)
    await ClockCycles(dut.clk, 2, rising=True)
    await dut.o_chip_select_neg.value_change

    assert spi_subordinate.opcode == SpiFlashMemory.program
    assert spi_subordinate.address == 21
    assert spi_subordinate.write_enable
    assert spi_subordinate.data == [0x80, 0x01]


def test_basic_spi():
    """
    Test if the basics of the SPI protocol are implemented correctly.
    """
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../../src/BasicSPI.v"]

    runner = get_runner(sim)
    runner.build(sources=sources, hdl_toplevel="BasicSPI", always=True, waves=True)
    runner.test(hdl_toplevel="BasicSPI", test_module="test_basic_spi", waves=True)


if __name__ == "__main__":
    test_basic_spi()
