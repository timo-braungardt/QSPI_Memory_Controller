import os
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import Timer, First, ClockCycles, RisingEdge
from cocotbext.spi import SpiBus
from HelperClasses import SpiFlashMemory

async def reset_dut(dut):
    dut.reset_neg.value = 0
    await ClockCycles(dut.clk, 4, rising=True)
    dut.reset_neg.value = 1
    await ClockCycles(dut.clk, 1, rising=True)


async def wait_for_idle(dut):
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout


async def trigger_go(dut):
    dut.start_transmission.value = 0
    await ClockCycles(dut.clk, 5, rising=True)
    dut.start_transmission.value = 1
    await ClockCycles(dut.clk, 1, rising=True)
    dut.start_transmission.value = 0


@cocotb.test()
async def transmission_test(dut):
    spi_subordinate = SpiFlashMemory(
        SpiBus(
            entity=dut,
            sclk_name="o_bus_clock",
            mosi_name="io_data0_manager_serial_out",
            miso_name="io_data1_manager_serial_in",
            cs_name="o_chip_select_neg",
        )
    )

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)
    
    dut.i_opcode.value = 0x02
    dut.i_address.value = 0x800001
    dut.i_data_write.value = 0x12345678

    dut.i_config_read_data.value = False
    dut.i_config_write_data.value = True
    dut.i_config_write_address.value = True
    dut.i_config_quad_mode.value = 0b000
    dut.i_config_dummy_cycles.value = 0
    dut.i_config_dummy_cycles.value = 0

    spi_subordinate.write_enable = True
    spi_subordinate.num_bytes = 1
    await trigger_go(dut)
    await wait_for_idle(dut)

    [opcode, address] = await spi_subordinate.get_content()
    assert opcode == 0x02
    assert address == 0x800001
    assert spi_subordinate.data == [0x78]


def test_spi_transmitter():
    """
    Test if the basics of the SPI protocol are implemented correctly.
    """
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../../src/SPITransmitter.v"]

    runner = get_runner(sim)
    runner.build(sources=sources, hdl_toplevel="SPITransmitter", always=True, waves=True)
    runner.test(hdl_toplevel="SPITransmitter", test_module="test_spi_transmitter", waves=True)


if __name__ == "__main__":
    test_spi_transmitter()
