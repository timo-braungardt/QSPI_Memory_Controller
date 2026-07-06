import os
import logging
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, First, FallingEdge, RisingEdge
from cocotb.clock import Clock
from cocotb.types import Logic, LogicArray
from unittest import SkipTest


async def reset_model(dut):
    dut.reset.value = 0
    await Timer(10, unit='us')
    dut.reset.value = 1
    await Timer(10, unit='us')

    if dut.RAM.PoweredUp.value == 0:
        await dut.RAM.PoweredUp.value_change


@cocotb.test()
async def read_test(dut):
    dut.controller.is_read.value           = True
    dut.controller.is_register_space.value = False
    dut.controller.is_linear_burst.value   = False
    dut.controller.address.value           = 0x00000000
    dut.controller.num_bits.value          = 512

    for i in range(8):
        dut.controller.buffer[i].value = 0

    c = Clock(dut.clk  , 20, 'ns')
    cocotb.start_soon(c.start())

    await reset_model(dut)

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.controller.o_chip_select_neg.value_change

    assert dut.controller.buffer[0].value == 0xFF
    assert dut.controller.buffer[1].value == 0xFF
    assert dut.controller.buffer[2].value == 0xFF
    assert dut.controller.buffer[3].value == 0xFF
    assert dut.controller.buffer[4].value == 0xFF


@cocotb.test()
async def write_test(dut):
    dut.controller.is_read.value           = False
    dut.controller.is_register_space.value = False
    dut.controller.is_linear_burst.value   = False
    dut.controller.address.value           = 0x00000000
    dut.controller.num_bits.value          = 32

    for i in range(8):
        dut.controller.buffer[i].value = i+1

    c = Clock(dut.clk  , 20, 'ns')
    cocotb.start_soon(c.start())

    await reset_model(dut)

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.controller.o_chip_select_neg.value_change

    # Read Back
    await Timer(50, unit='us')

    dut.controller.is_read.value           = True
    dut.controller.is_register_space.value = False
    dut.controller.is_linear_burst.value   = False
    dut.controller.address.value           = 0x00000000
    dut.controller.num_bits.value          = 32

    for i in range(8):
        dut.controller.buffer[i].value = 0

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.controller.o_chip_select_neg.value_change

    assert dut.controller.buffer[0].value == 0x01
    assert dut.controller.buffer[1].value == 0x02
    assert dut.controller.buffer[2].value == 0x03
    assert dut.controller.buffer[3].value == 0x04
    assert dut.controller.buffer[4].value == 0x00


@cocotb.test()
async def read_register_test(dut):
    """
    This is a bit weird, apparently the data should follow right after the CA bits are sent (zero latency).
    But the simulation model uses 2 latencies and only has 16 bits for the register, where there should be 6 16 Bit registers.
    """
    dut.controller.is_read.value           = True
    dut.controller.is_register_space.value = True
    dut.controller.is_linear_burst.value   = False
    dut.controller.address.value           = 0x00000000
    dut.controller.num_bits.value          = 32

    for i in range(8):
        dut.controller.buffer[i].value = 0

    c = Clock(dut.clk  , 20, 'ns')
    cocotb.start_soon(c.start())

    await reset_model(dut)

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.controller.o_chip_select_neg.value_change

    assert dut.controller.buffer[0].value == 0b10001111
    assert dut.controller.buffer[1].value == 0b00011111
    assert dut.controller.buffer[2].value == 0b10001111
    assert dut.controller.buffer[3].value == 0b00011111


def test_hyperbus_model():
    required_file = Path("../../test/memory_models/infineon-s27kl0641-simulationmodels-en/s27kl0641/model/s27kl0641.v")
    if not required_file.exists():
        raise SkipTest(f"Simulation Model for S27KL0641 not found!")

    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [
        proj_path / "../../src/Hyperbus.v",
        proj_path / "../../test/cocotb_wrapper/HyperRAM_wrapper.v",
        proj_path / "../../test/memory_models/infineon-s27kl0641-simulationmodels-en/s27kl0641/model/s27kl0641.v",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="HyperRAM_wrapper",
        always=True,
        waves=True
    )

    runner.test(hdl_toplevel="HyperRAM_wrapper", 
                test_module="test_hyperbus_model",
                waves=True)


if __name__ == "__main__":
    test_hyperbus_model()
