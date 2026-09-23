import logging
import cocotb
from cocotb.triggers import First, FallingEdge, RisingEdge
from cocotb.types import LogicArray

class HyperbusRam:
    def __init__(self, dut, size=8 * 1024 * 1024):
        self.LATENCY = 6 * 2
        self._CA_LENGTH = 6

        self.log = logging.getLogger("MemoryModel")
        self.log.setLevel(logging.DEBUG)
        self.dut = dut
        self.addr = 0
        self.is_read = 0
        self.is_register_space = 0
        self.is_linear_burst = 0

        # in the hyperbus spec one address always addresses 2 bytes
        # so this is a bit wrong
        self._MEMORY_SIZE = size
        self.mem = bytearray(size)

        self._run_coroutine_obj = None
        self._restart()

    def _restart(self):
        if self._run_coroutine_obj is not None:
            self._run_coroutine_obj.cancel()
        self._run_coroutine_obj = cocotb.start_soon(self._run())

    async def _run(self):
        while True:
            await FallingEdge(self.dut.o_chip_select_neg)
            ca = await self._read_ca()

            self.is_read = (ca >> 47) & 1
            self.is_register_space = (ca >> 46) & 1
            self.is_linear_burst = (ca >> 45) & 1

            self.addr = (ca >> 16) & 0x1FFFFFFF

            self.log.debug("test 0x%06x", (ca >> 16))
            self.addr <<= 3
            self.addr |= ca & 0x7

            self.log.debug(f"Is read is {self.is_read}")
            self.log.debug(f"Is register is {self.is_register_space}")
            self.log.debug(f"Is linear burst is {self.is_linear_burst}")
            self.log.debug("address is 0x%06x", self.addr)

            await self._latency(False)

            if self.is_read:
                await self._read_transaction(self.addr)
            else:
                await self._write_transaction(self.addr)

    async def _read_ca(self):
        clk_edge = RisingEdge(self.dut.o_bus_clock)
        clk_neg_edge = RisingEdge(self.dut.o_bus_clock_neg)
        ca = 0
        for _ in range(self._CA_LENGTH):
            await First(clk_edge, clk_neg_edge)
            word = int(self.dut.io_data.value)
            ca <<= 8
            ca |= word

        self.log.debug("Recieved 0x%06x", ca)
        return ca

    async def _latency(self, is_long):
        clk_edge = RisingEdge(self.dut.o_bus_clock)
        clk_neg_edge = RisingEdge(self.dut.o_bus_clock_neg)

        if is_long:
            latency = self.LATENCY * 2 - 2
        else:
            latency = self.LATENCY - 2

        for _ in range(latency):
            await First(clk_edge, clk_neg_edge)

    async def _write_transaction(self, addr):
        clk_edge = RisingEdge(self.dut.o_bus_clock)
        clk_neg_edge = RisingEdge(self.dut.o_bus_clock_neg)

        while not self.dut.o_chip_select_neg.value:
            await clk_edge
            if self.dut.io_data_strobe.value == 0:
                data = int(self.dut.io_data.value)
                self.mem[addr % self._MEMORY_SIZE] = data
                self.log.debug("Recieved 0x%02x", data)
            else:
                self.log.debug("Masked address")
            addr += 1

            await clk_neg_edge
            if self.dut.io_data_strobe.value == 0:
                data = int(self.dut.io_data.value)
                self.log.debug("Recieved 0x%02x", data)
                self.mem[addr % self._MEMORY_SIZE] = data
            else:
                self.log.debug("Masked address")
            addr += 1

    async def _read_transaction(self, addr):
        clk_edge = RisingEdge(self.dut.o_bus_clock)
        clk_neg_edge = RisingEdge(self.dut.o_bus_clock_neg)

        while not self.dut.o_chip_select_neg.value:
            await First(clk_edge, clk_neg_edge)
            data = self.mem[addr % self._MEMORY_SIZE]
            self.dut.io_data.value = LogicArray(data, 8)
            addr += 1
        self.dut.io_data.value = LogicArray("zzzzzzzz")
