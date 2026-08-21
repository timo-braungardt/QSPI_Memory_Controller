import os
import logging
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, First, ClockCycles, RisingEdge
from cocotb.clock import Clock
from collections import deque
from cocotbext.qspi import QSpiSubordinateBase, QSpiBus, QSpiConfig
from cocotbext.spi import SpiBus
from HelperClasses import SpiFlashMemory


async def reset_dut(dut):
    dut.reset_neg.value = 0
    await ClockCycles(dut.clk, 2, rising=True)
    dut.reset_neg.value = 1
    await ClockCycles(dut.clk, 1, rising=True)


class SimpleQSpiSubordinate(QSpiSubordinateBase):
    def __init__(self, bus: QSpiBus, config: QSpiConfig):
        self.log = logging.getLogger(f"cocotb.qspi")
        self._config = config
        self.opcode = 0
        self.address = 0
        self.write_enable = False
        self._out_queue = deque()
        super().__init__(bus)

    async def get_contents(self):
        await self.idle.wait()
        data = self._out_queue
        self._out_queue = deque()
        return list(data)

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.log.info("QSPI transaction started!")
        self.idle.clear()
        self.opcode = int(await self._quad_recieve(8))
        if self.opcode == 0x06:
            self.write_enable = True
        else:
            self.address = int(await self._quad_recieve(24))

        self.log.info("   opcode:  %x", self.opcode)
        self.log.info("   address: %d", self.address)
        # Manager ordered a read
        if self.opcode == 0x03:
            self.log.info("   Sending Data")
            await self._quad_send(32, 0x12345678)  # ToDo: always shifts out 4 bytes, change logic

        # Manager ordered a program
        if self.opcode == 0x02:
            self.data = int(
                await self._quad_recieve(16)
            )  # ToDo: only reads two bytes, change to an array
            self.log.info("   data %x", self.data)

        await frame_end


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
async def spi_transmission_test(dut):
    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_data1_manager_serial_out",
            miso_name="io_data0_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await reset_dut(dut)

    dut.SPI_Transmitter.is_quad_mode.value = False

    dut.i_address.value = 0x800001
    dut.i_data_write.value = 0x8001
    dut.i_write_enable.value = 0b0

    await trigger_go(dut)
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout

    [opcode, address] = await spi_subordinate.get_content()
    assert opcode == 0x03
    assert address == 0x800001


@cocotb.test()
async def spi_read_test(dut):
    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_data1_manager_serial_out",
            miso_name="io_data0_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await reset_dut(dut)

    dut.SPI_Transmitter.is_quad_mode.value = False

    dut.i_address.value = 20
    dut.i_write_enable.value = False

    dut.SPI_Transmitter.num_bits.value = 32
    spi_subordinate.num_bytes = 32 // 8
    spi_subordinate.data = [0x12, 0x34, 0x56, 0x78]

    await trigger_go(dut)
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout

    [opcode, address] = await spi_subordinate.get_content()
    assert opcode == SpiFlashMemory.read
    assert address == 20
    assert dut.o_data_read.value == 0x1234


@cocotb.test()
async def spi_write_test(dut):

    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_data1_manager_serial_out",
            miso_name="io_data0_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await reset_dut(dut)

    dut.SPI_Transmitter.is_quad_mode.value = False

    dut.i_address.value = 21
    dut.i_data_write.value = 0x8001
    dut.i_write_enable.value = True

    dut.SPI_Transmitter.num_bits.value = 16
    spi_subordinate.num_bytes = 16 // 8

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
    assert spi_subordinate.data == [0x80, 0x01]


def test_spi_controller():
    """
    Test the spi controller against cocotb memory models.
    """
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../../src/SPIController.v", proj_path / "../../src/SPITransmitter.v"]

    runner = get_runner(sim)
    runner.build(sources=sources, hdl_toplevel="SPIController", always=True, waves=True)
    runner.test(hdl_toplevel="SPIController", test_module="test_spi_controller", waves=True)


if __name__ == "__main__":
    test_spi_controller()
