import os
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import ClockCycles, RisingEdge
from cocotb.clock import Clock
from cocotb.types import LogicArray
from HelperClasses import HyperbusRam


async def reset_dut(dut):
    dut.reset.value = 1
    await ClockCycles(dut.clk, 1, rising=True)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 1, rising=True)


async def trigger_go(dut):
    dut.go.value = 0
    await ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await ClockCycles(dut.clk, 2, rising=True)


@cocotb.test()
async def transmission_test(dut):
    memory_model = HyperbusRam(dut)

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.is_read.value = True
    dut.is_register_space.value = False
    dut.is_linear_burst.value = False
    dut.address.value = 0x8000000D
    dut.num_bits.value = 8

    await trigger_go(dut)
    await RisingEdge(dut.o_chip_select_neg)

    assert memory_model.addr == 0x8000000D
    assert memory_model.is_read == True
    assert memory_model.is_register_space == False
    assert memory_model.is_linear_burst == False


@cocotb.test()
async def read_test(dut):
    memory_model = HyperbusRam(dut)

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.is_read.value = True
    dut.is_register_space.value = False
    dut.is_linear_burst.value = False
    dut.address.value = 0x00000000
    dut.num_bits.value = 32

    for i in range(8):
        memory_model.mem[i] = i + 1

    await trigger_go(dut)
    await RisingEdge(dut.o_chip_select_neg)

    assert memory_model.addr == 0x00000000
    assert memory_model.is_read == True
    assert memory_model.is_register_space == False
    assert memory_model.is_linear_burst == False

    assert dut.buffer[0].value == 1
    assert dut.buffer[1].value == 2
    assert dut.buffer[2].value == 3
    assert dut.buffer[3].value == 4
    assert dut.buffer[4].value == LogicArray("XXXXXXXX")


@cocotb.test()
async def write_test(dut):
    memory_model = HyperbusRam(dut)

    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_dut(dut)

    dut.is_read.value = False
    dut.is_register_space.value = False
    dut.is_linear_burst.value = False
    dut.address.value = 0x00000000
    dut.num_bits.value = 32

    for i in range(8):
        dut.buffer[i].value = i + 1

    await trigger_go(dut)
    await RisingEdge(dut.o_chip_select_neg)

    assert memory_model.addr == 0x00000000
    assert memory_model.is_read == False
    assert memory_model.is_register_space == False
    assert memory_model.is_linear_burst == False

    assert memory_model.mem[0] == 1
    assert memory_model.mem[1] == 2
    assert memory_model.mem[2] == 3
    assert memory_model.mem[3] == 4
    assert memory_model.mem[4] == 0


def test_hyperbus():
    """
    Test if the basics of the Hyperbus protocol are implemented correctly.
    """
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../../src/Hyperbus.v"]

    runner = get_runner(sim)
    runner.build(sources=sources, hdl_toplevel="Hyperbus", always=True, waves=True)
    runner.test(hdl_toplevel="Hyperbus", test_module="test_hyperbus", waves=True)


if __name__ == "__main__":
    test_hyperbus()
