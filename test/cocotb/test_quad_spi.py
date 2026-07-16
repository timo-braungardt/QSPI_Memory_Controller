import os
import logging
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, First
from cocotb.clock import Clock
from collections import deque
from cocotbext.qspi import QSpiSubordinateBase, QSpiBus, QSpiConfig


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
            await self._quad_send(32, 0x12345678)   # ToDo: always shifts out 4 bytes, change logic

        # Manager ordered a program
        if self.opcode == 0x02:
            self.data = int(await self._quad_recieve(16))   # ToDo: only reads two bytes, change to an array
            self.log.info("   data %x", self.data)

        await frame_end


@cocotb.test()
async def transmission_test(dut):
    qspi_subordinate = SimpleQSpiSubordinate(
                    QSpiBus(
                        entity=dut, 
                        sclk_name='o_bus_clock', 
                        mosi_d1_name='io_dq1_manager_serial_out', 
                        miso_d0_name='io_dq0_manager_serial_in',
                        d2_name='io_dq2',
                        d3_name='io_dq3',
                        cs_name='o_chip_select_neg'),
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

    dut.opcode.value = 5
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

    assert qspi_subordinate.opcode == 0x05
    assert qspi_subordinate.address == 0x800001


@cocotb.test()
async def read_test(dut):

    qspi_subordinate = SimpleQSpiSubordinate(
                    QSpiBus(
                        entity=dut, 
                        sclk_name='o_bus_clock', 
                        mosi_d1_name='io_dq1_manager_serial_out', 
                        miso_d0_name='io_dq0_manager_serial_in',
                        d2_name='io_dq2',
                        d3_name='io_dq3',
                        cs_name='o_chip_select_neg'),
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

    assert qspi_subordinate.opcode == 0x03
    assert qspi_subordinate.address == 20
    assert dut.buffer[0].value.to_unsigned() == 0x12
    assert dut.buffer[1].value.to_unsigned() == 0x34
    assert dut.buffer[2].value.to_unsigned() == 0x56
    assert dut.buffer[3].value.to_unsigned() == 0x78


@cocotb.test()
async def write_test(dut):

    qspi_subordinate = SimpleQSpiSubordinate(
                    QSpiBus(
                        entity=dut, 
                        sclk_name='o_bus_clock', 
                        mosi_d1_name='io_dq1_manager_serial_out', 
                        miso_d0_name='io_dq0_manager_serial_in',
                        d2_name='io_dq2',
                        d3_name='io_dq3',
                        cs_name='o_chip_select_neg'),
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
    
    dut.opcode.value = 0x06
    
    dut.write_address.value = 0b0
    dut.write_data.value = 0b0
    dut.read_data.value = 0b0

    c = Clock(dut.clk  , 20, 'ns')
    cocotb.start_soon(c.start())

    assert not qspi_subordinate.write_enable

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.o_chip_select_neg.value_change

    assert qspi_subordinate.opcode == 0x06
    assert qspi_subordinate.write_enable

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

    assert qspi_subordinate.opcode == 0x02
    assert qspi_subordinate.address == 21
    assert qspi_subordinate.write_enable
    assert qspi_subordinate.data == 0x8001


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