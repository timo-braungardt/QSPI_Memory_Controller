import os
import logging
from cocotbext.qspi import QSpiSubordinateBase, QSpiBus, QSpiConfig


class QSpiFlashMemory(QSpiSubordinateBase):
    write_enable = 0x06
    program = 0x02
    read = 0x03

    def __init__(self, bus: QSpiBus, config: QSpiConfig):
        self.log = logging.getLogger(f"cocotb.qspi")
        self._config = config
        self.opcode = 0
        self.address = 0
        self.write_enable = False
        self.data = []
        self.num_bytes = 4
        super().__init__(bus)

    async def get_contents(self):
        await self.idle.wait()
        return self.opcode, self.address

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.log.info("QSPI transaction started!")
        self.idle.clear()
        self.opcode = int(await self._quad_recieve(8))
        self.log.info("   opcode:  %x", self.opcode)
        if self.opcode == QSpiFlashMemory.write_enable:
            self.write_enable = True
            self.log.info("   writing enabled")
        else:
            self.address = int(await self._quad_recieve(24))
            self.log.info("   address: %d", self.address)

        # Manager ordered a read
        if self.opcode == QSpiFlashMemory.read:
            for i in range(self.num_bytes):
                data = 0
                if len(self.data) >= self.num_bytes:
                    data = self.data[i]
                await self._quad_send(8, data)
                self.log.info("   sending %x", data)

        # Manager ordered a program
        if self.opcode == QSpiFlashMemory.program:
            if not self.write_enable:
                raise RuntimeError("Write enable not set!")
            
            for i in range(self.num_bytes):
                data = int(await self._quad_recieve(8))
                self.log.info(f"   recieved {data}")
                self.data.append(data)

        await frame_end
