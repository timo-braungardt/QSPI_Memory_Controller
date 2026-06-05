import os
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, First
from cocotb.clock import Clock
from collections import deque
from cocotbext.qspi import QSpiSubordinateBase, QSpiBus, QSpiConfig


class SimpleQSpiSubordinate(QSpiSubordinateBase):
    def __init__(self, bus: QSpiBus, config: QSpiConfig):
        self._config = config
        self._out_queue = deque()
        super().__init__(bus)

    async def get_contents(self):
        await self.idle.wait()
        data = self._out_queue
        self._out_queue = deque()
        return list(data)

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.idle.clear()

        content = int(await self._quad_recieve(8))
        self._out_queue.append(content)
        content = int(await self._quad_recieve(24))
        self._out_queue.append(content)
            
        await frame_end


@cocotb.test()
async def qspi_flash(dut):
    qspi_subordinate = SimpleQSpiSubordinate(
                    QSpiBus(
                        entity=dut, 
                        sclk_name='o_SpiClk', 
                        mosi_d1_name='io_ManagerSerialOut_QD1', 
                        miso_d0_name='io_ManagerSerialIn_QD0',
                        d2_name='io_DQ2',
                        d3_name='io_DQ3',
                        cs_name='o_ChipSelect_neg'),
                    QSpiConfig(
                        word_width=8,
                        sclk_freq=20e6,
                        cpol=0,
                        cpha=0,
                        msb_first=True,
                        frame_spacing_ns=10,
                        ignore_rx_value=None,
                        cs_active_low=True,
                        is_quad_mode=True,)
                    )

    dut.opcode.value = 3
    dut.address.value = 20

    c = Clock(dut.clk  , 20, 'ns')
    cocotb.start_soon(c.start())

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0

    await cocotb.triggers.ClockCycles(dut.clk, 100, rising=True)
    result = await qspi_subordinate.get_contents()
    assert result == [3, 20]


def test_quad_spi():
    """
    Test if the basics of the Quad SPI protocol are implemented correctly.
    """
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../../src/QuadSPI.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="QuadSPI",
        always=True,
        waves=True
    )
    runner.test(hdl_toplevel="QuadSPI", 
				test_module="test_quad_spi",
                waves=True)


if __name__ == "__main__":
    test_quad_spi()