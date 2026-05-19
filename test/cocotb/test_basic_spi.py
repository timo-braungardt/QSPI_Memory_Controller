import cocotb
from cocotb.triggers import Timer
from cocotbext.spi import SpiSlaveBase, SpiBus, SpiConfig

class SimpleSpiSubordinate(SpiSlaveBase):
    def __init__(self, bus):
        self._config = SpiConfig()
        self.content = 0
        super().__init__(bus)

    async def get_content(self):
        await self.idle.wait()
        return self.content

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.idle.clear()

        self.content = int(await self._shift(16, tx_word=(0xAAAA)))

        await frame_end


async def generate_clock(dut):
    for _ in range(1):
        dut.clk.value = 0
        await Timer(1, unit="ns")
        dut.clk.value = 1
        await Timer(1, unit="ns")


@cocotb.test()
async def my_first_test(dut):
    cocotb.start_soon(generate_clock(dut))

    dut.go.value = 0
    spi_slave = SimpleSpiSubordinate(SpiBus(entity=dut, sclk_name='o_SpiClk', mosi_name='io_ManagerSerialOut', miso_name='io_ManagerSerialIn', cs_name='o_ChipSelect'))


    await Timer(2, unit="ns")
    cocotb.log.info("signal is %s", dut.o_SpiClk.value)
    assert dut.o_SpiClk.value == 0
