import logging
import cocotb
from cocotbext.spi import SpiSlaveBase, SpiBus, SpiConfig
from cocotb.triggers import FallingEdge, First, RisingEdge, Timer


class SpiFlashMemory(SpiSlaveBase):
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

        frame_end = RisingEdge(self._cs) if self._config.cs_active_low else FallingEdge(self._cs)

        for k in range(num_bits):
            if (await First(RisingEdge(self._sclk), frame_end)) == frame_end or self._cs.value == 1:
                raise SpiFrameError("End of frame in the middle of a transaction")

            rx_word |= int(self._mosi.value) << (num_bits - 1 - k)
        return rx_word

    async def _write_data(self, num_bits: int, tx_word: int) -> int:
        frame_end = RisingEdge(self._cs) if self._config.cs_active_low else FallingEdge(self._cs)

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
        if self.opcode == SpiFlashMemory.write_enable:
            self.write_enable = True
            self.log.info("   writing enabled")
        else:
            self.address = int(await self._read_data(24))
            self.log.info("   address: %d", self.address)

        # Manager ordered a read
        if self.opcode == SpiFlashMemory.read:
            await self._write_data(
                32, tx_word=0x12345678
            )  # ToDo: always shifts out 4 bytes, change logic
            self.log.info("   reading data %x", self.data)

        # Manager ordered a program
        if self.opcode == SpiFlashMemory.program:
            self.data = int(
                await self._read_data(16)
            )  # ToDo: only reads two bytes, change to an array
            self.log.info("   sending Data")

        await frame_end
