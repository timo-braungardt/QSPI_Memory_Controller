import os
import logging
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, First, FallingEdge, RisingEdge
from cocotb.clock import Clock
from cocotb.types import Logic, LogicArray
from unittest import SkipTest


class SPI_COMMANDS:
    write_enable = 0x06
    program = 0x02
    read = 0x03


async def reset_model(dut):
    dut.reset.value = 0
    await Timer(10, unit='us')
    dut.reset.value = 1
    await Timer(10, unit='us')

    if dut.Memory.PoweredUp.value == 0:
        await dut.Memory.PoweredUp.value_change


@cocotb.test()
async def read_test(dut):
    # write enable
    dut.Controller.opcode.value = SPI_COMMANDS.write_enable
    
    dut.Controller.write_address.value = 0b0
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b0

    c = Clock(dut.clk  , 20, 'ns')
    cocotb.start_soon(c.start())

    await reset_model(dut)

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.chip_select_neg.value_change

    # program
    dut.Controller.opcode.value = SPI_COMMANDS.program
    dut.Controller.address.value = 0x20
    
    dut.Controller.write_address.value = 0b1
    dut.Controller.write_data.value = 0b1
    dut.Controller.read_data.value = 0b0
    dut.Controller.buffer[0].value = 0x12
    dut.Controller.buffer[1].value = 0x34
    dut.Controller.buffer[2].value = 0x56
    dut.Controller.buffer[3].value = 0x78
    dut.Controller.buffer[4].value = 0xFF
    dut.Controller.num_bits.value = 8

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.chip_select_neg.value_change

    # read
    await Timer(1700, unit='us')     # T_PP max in the datasheet

    dut.Controller.opcode.value = SPI_COMMANDS.read
    dut.Controller.address.value = 0x20
    
    dut.Controller.write_address.value = 0b1
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b1
    dut.Controller.num_bits.value = 8

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.chip_select_neg.value_change
       
    assert dut.Controller.buffer[0].value.to_unsigned() == 0x12
    assert dut.Controller.buffer[1].value.to_unsigned() == 0x34
    assert dut.Controller.buffer[2].value.to_unsigned() == 0x56
    assert dut.Controller.buffer[3].value.to_unsigned() == 0x78


def test_spi_model():
    required_file = Path("../../test/memory_models/infineon-s25hl512t-qspi-verilog-model-simulationmodels-en/s25hl512tRel/src/s25hl512t.sv")
    if not required_file.exists():
        raise SkipTest(f"Simulation Model for S25HL512T not found!")

    proj_path = Path(__file__).resolve().parent
    sources = [
        proj_path / "../../src/BasicSPI.v",
        proj_path / "../../test/cocotb_wrapper/SPI_wrapper.v",
        proj_path / required_file
    ]

    sim = os.getenv("SIM", "questa")
    try:
        runner = get_runner(sim)
    except (SystemExit):
        raise SkipTest(f"Simulator {sim} not found!")

    runner.build(
        sources=sources,
        hdl_toplevel="SPI_wrapper",
        always=True,
    )

    runner.test(hdl_toplevel="SPI_wrapper",
                test_module="test_spi_model",
                gui=True,
                )


if __name__ == "__main__":
    test_spi_model()
