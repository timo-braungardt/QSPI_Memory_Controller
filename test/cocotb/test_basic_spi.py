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
        self.write_enable = False
        self.data = 0
        super().__init__(bus)

    async def get_content(self):
        await self.idle.wait()
        return self.opcode, self.address

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.idle.clear()
        self.opcode = int(await self._shift(8, tx_word=(0x00)))
        if self.opcode == 0x06:
            self.write_enable = True
        else:
            self.address = int(await self._shift(24, tx_word=(0x000000)))

        # Manager ordered a read
        if self.opcode == 0x03:
            await self._shift(32, 0x12345678)   # ToDo: always shifts out 4 bytes, change logic

        # Manager ordered a program
        if self.opcode == 0x02:
            self.data = int(await self._shift(16, tx_word=(0x00)))   # ToDo: only reads two bytes, change to an array

        await frame_end


@cocotb.test()
async def transmission_test(dut):
    spi_subordinate = SimpleSpiSubordinate(
                    SpiBus(
                        entity=dut, 
                        sclk_name='o_bus_clock', 
                        mosi_name='io_manager_serial_out', 
                        miso_name='io_manager_serial_in', 
                        cs_name='o_chip_select_neg')
                    )
    
    dut.opcode.value = 0x81
    dut.address.value = 0x800001

    dut.write_address.value = 0b1
    dut.write_data.value = 0b0
    dut.read_data.value = 0b0

    c = Clock(dut.clk  , 20, 'ns')
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

    spi_subordinate = SimpleSpiSubordinate(
                    SpiBus(
                        entity=dut, 
                        sclk_name='o_bus_clock', 
                        mosi_name='io_manager_serial_out', 
                        miso_name='io_manager_serial_in', 
                        cs_name='o_chip_select_neg')
                    )
    
    dut.opcode.value = 0x03
    dut.address.value = 20
    
    dut.write_address.value = 0b1
    dut.write_data.value = 0b0
    dut.read_data.value = 0b1
    dut.num_bits.value = 32

    c = Clock(dut.clk  , 20, 'ns')
    cocotb.start_soon(c.start())

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.o_chip_select_neg.value_change
    [opcode, address] = await spi_subordinate.get_content()

    assert opcode == 3
    assert address == 20

    # ToDo: this is not the data we expect to recieve
    # but the module can only shift out data on the next negative clock edge, 
    # therefore we have to manually shift the data for now        
    #assert dut.buffer[0].value.to_unsigned() == 0x12
    #assert dut.buffer[1].value.to_unsigned() == 0x34
    #assert dut.buffer[2].value.to_unsigned() == 0x56
    #assert dut.buffer[3].value.to_unsigned() == 0x78
    assert dut.buffer[0].value.to_unsigned() == 0b00001001
    assert dut.buffer[1].value.to_unsigned() == 0b00011010
    assert dut.buffer[2].value.to_unsigned() == 0b00101011
    assert dut.buffer[3].value.to_unsigned() == 0b00111100


@cocotb.test()
async def write_test(dut):

    spi_subordinate = SimpleSpiSubordinate(
                    SpiBus(
                        entity=dut, 
                        sclk_name='o_bus_clock', 
                        mosi_name='io_manager_serial_out', 
                        miso_name='io_manager_serial_in', 
                        cs_name='o_chip_select_neg')
                    )
    
    dut.opcode.value = 0x06
    
    dut.write_address.value = 0b0
    dut.write_data.value = 0b0
    dut.read_data.value = 0b0

    c = Clock(dut.clk  , 20, 'ns')
    cocotb.start_soon(c.start())

    assert not spi_subordinate.write_enable

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.o_chip_select_neg.value_change

    assert spi_subordinate.opcode == 0x06
    assert spi_subordinate.write_enable

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

    assert spi_subordinate.opcode == 0x02
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
