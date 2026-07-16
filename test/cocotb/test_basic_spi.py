import os
import logging
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import FallingEdge, First, RisingEdge, Timer
from cocotb.clock import Clock
from cocotbext.spi import SpiSlaveBase, SpiBus, SpiConfig


class SPIFlashMemory(SpiSlaveBase):
    write_enable = 0x06
    program = 0x02
    read = 0x03

    def __init__(self, bus):
        self.log = logging.getLogger(f"cocotb.spi")
        self._config = SpiConfig()
        self.opcode = 0
        self.address = 0
        self.write_enable = False
        self.data = 0
        super().__init__(bus)

    async def get_content(self):
        await self.idle.wait()
        return self.opcode, self.address

    async def _read_data(self, num_bits: int) -> int:
        rx_word = 0

        frame_end = (
            RisingEdge(self._cs)
            if self._config.cs_active_low
            else FallingEdge(self._cs)
        )

        for k in range(num_bits):
            if (
                await First(RisingEdge(self._sclk), frame_end)
            ) == frame_end or self._cs.value == 1:
                raise SpiFrameError("End of frame in the middle of a transaction")

            rx_word |= int(self._mosi.value) << (num_bits - 1 - k)
        return rx_word

    async def _write_data(self, num_bits: int, tx_word: int) -> int:
        frame_end = (
            RisingEdge(self._cs)
            if self._config.cs_active_low
            else FallingEdge(self._cs)
        )

        for k in range(num_bits):
            if (
                await First(FallingEdge(self._sclk), frame_end)
            ) == frame_end or self._cs.value == 1:
                raise SpiFrameError("End of frame in the middle of a transaction")

            self._miso.value = bool(tx_word & (1 << (num_bits - 1 - k)))

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.log.info("SPI transaction started!")
        self.idle.clear()
        self.opcode = int(await self._read_data(8))
        self.log.info("   opcode:  %x", self.opcode)
        if self.opcode == SPIFlashMemory.write_enable:
            self.write_enable = True
            self.log.info("   writing enabled")
        else:
            self.address = int(await self._read_data(24))
            self.log.info("   address: %d", self.address)

        # Manager ordered a read
        if self.opcode == SPIFlashMemory.read:
            await self._write_data(
                32, tx_word=0x12345678
            )  # ToDo: always shifts out 4 bytes, change logic
            self.log.info("   reading data %x", self.data)

        # Manager ordered a program
        if self.opcode == SPIFlashMemory.program:
            self.data = int(
                await self._read_data(16)
            )  # ToDo: only reads two bytes, change to an array
            self.log.info("   sending Data")

        await frame_end


@cocotb.test()
async def transmission_test(dut):
    spi_subordinate = SPIFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_manager_serial_out",
            miso_name="io_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )

    dut.opcode.value = 0x81
    dut.address.value = 0x800001

    dut.write_address.value = 0b1
    dut.write_data.value = 0b0
    dut.read_data.value = 0b0

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.o_chip_select_neg.value_change
    [opcode, address] = await spi_subordinate.get_content()
    assert opcode == 0x81
    assert address == 0x800001


@cocotb.test()
async def read_test(dut):
    spi_subordinate = SPIFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_manager_serial_out",
            miso_name="io_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )

    dut.opcode.value = SPIFlashMemory.read
    dut.address.value = 20

    dut.write_address.value = 0b1
    dut.write_data.value = 0b0
    dut.read_data.value = 0b1
    dut.num_bits.value = 32

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.o_chip_select_neg.value_change
    [opcode, address] = await spi_subordinate.get_content()

    assert opcode == SPIFlashMemory.read
    assert address == 20

    assert dut.buffer[0].value.to_unsigned() == 0x12
    assert dut.buffer[1].value.to_unsigned() == 0x34
    assert dut.buffer[2].value.to_unsigned() == 0x56
    assert dut.buffer[3].value.to_unsigned() == 0x78


@cocotb.test()
async def write_test(dut):

    spi_subordinate = SPIFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_manager_serial_out",
            miso_name="io_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )

    dut.opcode.value = SPIFlashMemory.write_enable

    dut.write_address.value = 0b0
    dut.write_data.value = 0b0
    dut.read_data.value = 0b0

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    assert not spi_subordinate.write_enable

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.o_chip_select_neg.value_change

    assert spi_subordinate.opcode == SPIFlashMemory.write_enable
    assert spi_subordinate.write_enable

    dut.opcode.value = SPIFlashMemory.program
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

    assert spi_subordinate.opcode == SPIFlashMemory.program
    assert spi_subordinate.address == 21
    assert spi_subordinate.write_enable
    assert spi_subordinate.data == 0x8001


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
