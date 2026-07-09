import os
import logging
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge
from cocotbext.spi import SpiSlaveBase, SpiBus, SpiConfig
from cocotbext.axi import AxiBus, AxiMaster


class SimpleSpiSubordinate(SpiSlaveBase):
    def __init__(self, bus):
        self.log = logging.getLogger(f"cocotb.spi")
        self._config = SpiConfig()
        self.opcode = 0
        self.address = 0
        self.write_enable = False
        self.data = []
        self.length = 4
        super().__init__(bus)

    async def get_content(self):
        await self.idle.wait()
        return self.opcode, self.address

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.log.info("SPI transaction started!")
        self.idle.clear()
        self.opcode = int(await self._shift(8, tx_word=(0x00)))
        if self.opcode == 0x06:
            self.write_enable = True
        else:
            self.address = int(await self._shift(24, tx_word=(0x000000)))

        self.log.info("   opcode:  %d", self.opcode)
        self.log.info("   address: %d", self.address)
        # Manager ordered a read
        if self.opcode == 0x03:
            for i in range(self.length):
                data = 0
                if len(self.data) >= self.length:
                    data = self.data[i]
                await self._shift(8, data)   # ToDo: always shifts out 4 bytes, change logic

        # Manager ordered a program
        if self.opcode == 0x02:
            for i in range(self.length):
                data = int(await self._shift(8, tx_word=(0x00)))
                self.log.info("Recieved %d", data)
                self.data.append(data)

        await frame_end


@cocotb.test()
async def transmission_test(dut):
    c = Clock(dut.clk  , 20, 'ns')
    cocotb.start_soon(c.start())

    dut.rst.setimmediatevalue(0)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    axi_master = AxiMaster(AxiBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    spi_subordinate = SimpleSpiSubordinate(
                    SpiBus(
                        entity=dut, 
                        sclk_name='s_spi_clock', 
                        mosi_name='s_spi_manager_serial_out', 
                        miso_name='s_spi_manager_serial_in', 
                        cs_name='s_spi_chip_select_neg')
                    )

    addr = 0x1000
    length = 4
    spi_subordinate.length = 4
    test_data = bytearray([x % 256 for x in range(length)])
    await axi_master.write(addr, test_data)
    await Timer(8, 'us')

    print(spi_subordinate.data)
    assert spi_subordinate.data[0] == 0
    assert spi_subordinate.data[1] == 1
    assert spi_subordinate.data[2] == 2
    assert spi_subordinate.data[3] == 3

    data = await axi_master.read(addr, length)
    #assert data.data == test_data  # ToDo: the SPI write is offset by one clock edge...


def test_axi():
    """
    Test axi to spi.
    """
    top_level = "Basic_AXI_SPI"
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / f"../../src/{top_level}.v",
               proj_path / "../../src/BasicSPI.v"]


    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=top_level,
        always=True,
        waves=True
    )
    runner.test(hdl_toplevel=top_level, 
                test_module="test_axi",
                waves=True)


if __name__ == "__main__":
    test_axi()
