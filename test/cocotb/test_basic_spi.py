import os
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer
from cocotb.clock import Clock
from cocotbext.spi import SpiSlaveBase, SpiBus, SpiConfig


class SimpleSpiSubordinate(SpiSlaveBase):
    def __init__(self, bus):
        self._config = SpiConfig()
        self.opcode = 0
        self.address = 0
        super().__init__(bus)

    async def get_content(self):
        await self.idle.wait()
        return self.opcode, self.address

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.idle.clear()
        self.opcode = int(await self._shift(8, tx_word=(0x00)))
        self.address = int(await self._shift(24, tx_word=(0x888888)))

        # Manager ordered a read
        if self.opcode == 0x03:
            await self._shift(32, 0x12345678)
            #await self._shift(8, 0x78)

        await frame_end


@cocotb.test()
async def transmission_test(dut):
    spi_subordinate = SimpleSpiSubordinate(
                    SpiBus(
                        entity=dut, 
                        sclk_name='o_SpiClk', 
                        mosi_name='io_ManagerSerialOut', 
                        miso_name='io_ManagerSerialIn', 
                        cs_name='o_ChipSelect_neg')
                    )
    
    dut.opcode.value = 5
    dut.address.value = 20

    c = Clock(dut.clk  , 20, 'ns')
    cocotb.start_soon(c.start())

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 100, rising=True)
    [opcode, address] = await spi_subordinate.get_content()
    assert opcode == 5
    assert address == 20


@cocotb.test()
async def read_test(dut):

    spi_subordinate = SimpleSpiSubordinate(
                    SpiBus(
                        entity=dut, 
                        sclk_name='o_SpiClk', 
                        mosi_name='io_ManagerSerialOut', 
                        miso_name='io_ManagerSerialIn', 
                        cs_name='o_ChipSelect_neg')
                    )
    
    dut.opcode.value = 0x03
    dut.address.value = 20
    
    dut.write_address.value = 0b1
    dut.write_data.value = 0b0
    dut.read_data.value = 0b1
    dut.num_bits.value = 66  # has to be +2 because we sample on the next edge, not on the "sending" edge!
    # ToDo: the DUT is not sampling on the positive clock edge but the negative - fix!

    c = Clock(dut.clk  , 20, 'ns')
    cocotb.start_soon(c.start())

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 100, rising=True)
    [opcode, address] = await spi_subordinate.get_content()

    assert opcode == 3
    assert address == 20
    assert dut.buffer[0].value.integer == 0x12
    assert dut.buffer[1].value.integer == 0x34
    assert dut.buffer[2].value.integer == 0x56
    assert dut.buffer[3].value.integer == 0x78


def test_basic_spi():
    """
    Test if the basics of the SPI protocol are implemented correctly.
    """
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../../src/BasicSPI.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="BasicSPI",
        always=True,
        waves=True
    )
    runner.test(hdl_toplevel="BasicSPI", 
				test_module="test_basic_spi",
                waves=True)


if __name__ == "__main__":
    test_basic_spi()
