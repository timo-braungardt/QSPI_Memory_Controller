import os
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ClockCycles, First
from cocotb.clock import Clock
from cocotb.handle import Immediate
from HelperClasses import DummyData, MemoryModelHelper, DataHandler
from unittest import SkipTest

T_rwr = Timer(35, unit="ns")  # read-write recovery time from the datasheet
# to wait after one transaction this much is pesimistic, we can already issue 4 cycles of the next command


# opcode for the S70KL1283 Octal SPI RAM chip
class OPCODE:
    read = 0xEE
    write = 0xDE
    write_enable = 0x06
    read_id = 0x9F


async def reset_model(dut):
    dut.test_number.value = dut.test_number.value + 1
    dut.i_write_valid.value = False
    dut.reset_neg.value = 0
    await Timer(200, unit="ns")  # t_RP
    dut.reset_neg.value = 1
    await Timer(200, unit="ns")  # t_RH

    if dut.Memory.bottom.PoweredUp.value == 0:
        await dut.Memory.bottom.PoweredUp.value_change


async def wait_for_idle(dut):
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.chip_select_neg), timeout)
    assert trigger != timeout


async def trigger_go(dut):
    dut.go.value = 0
    await ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0


def check_write_enable(dut):
    return dut.Memory.bottom.WREN.value


def config_transaction(dut, opcode, address=0):
    dut.i_address.value = Immediate(address)
    dut.i_opcode.value = Immediate(opcode)

    if opcode == OPCODE.write:
        dut.i_config_read_data.value = Immediate(False)
        dut.i_config_write_data.value = Immediate(True)
        dut.i_config_write_address.value = Immediate(True)

    if opcode == OPCODE.read:
        dut.i_config_read_data.value = Immediate(True)
        dut.i_config_write_data.value = Immediate(False)
        dut.i_config_write_address.value = Immediate(True)

    if opcode == OPCODE.write_enable:
        dut.i_config_read_data.value = Immediate(False)
        dut.i_config_write_data.value = Immediate(False)
        dut.i_config_write_address.value = Immediate(False)

    if opcode == OPCODE.read_id:
        dut.i_address.value = Immediate(0)
        dut.i_config_read_data.value = Immediate(True)
        dut.i_config_write_data.value = Immediate(False)
        dut.i_config_write_address.value = Immediate(True)


@cocotb.test()
async def write_test(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    await reset_model(dut)
    num_bytes = 1
    test_data = DummyData(num_bytes)
    address = 0x001000

    config_transaction(dut, OPCODE.write_enable)
    await Timer(50, unit="ns")      # this wait is needed, otherwise the test fails (issue #32)
    handler = DataHandler(dut, test_data)
    handler.start_write()
    await trigger_go(dut)
    await wait_for_idle(dut)

    await T_rwr

    assert check_write_enable(dut)

    config_transaction(dut, OPCODE.write, address=address)
    await trigger_go(dut)
    await wait_for_idle(dut)
    await T_rwr

    memory_data = MemoryModelHelper.get_memory_s70kl1283(dut.Memory, address, num_bytes + 1)
    # the controller shall only write one byte
    extended_test_data = test_data.get_test_array()
    extended_test_data.append(0xff)
    assert memory_data == extended_test_data


@cocotb.test()
async def read_test(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    await reset_model(dut)
    test_data = DummyData(1)
    address = 0x001004

    MemoryModelHelper.set_memory_s70kl1283(dut.Memory, address, test_data.get_test_array())

    config_transaction(dut, OPCODE.read, address=address)
    read_data = DummyData(0)
    handler = DataHandler(dut, read_data)
    handler.start_read(1)
    await trigger_go(dut)
    await wait_for_idle(dut)

    assert read_data.get_test_array() == test_data.get_test_array()


@cocotb.test()
async def variable_latency_test(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    await reset_model(dut)
    test_data = DummyData(1)

    config_transaction(dut, OPCODE.write_enable)
    await trigger_go(dut)
    await wait_for_idle(dut)

    MemoryModelHelper.set_variable_latency_s70kl1283(dut.Memory)

    await T_rwr

    assert check_write_enable(dut)

    config_transaction(dut, OPCODE.write, address=0x001000)
    handler = DataHandler(dut, test_data)
    handler.start_write()
    await trigger_go(dut)
    await wait_for_idle(dut)

    await T_rwr

    config_transaction(dut, OPCODE.read, address=0x001000)
    read_data = DummyData(0)
    handler = DataHandler(dut, read_data)
    handler.start_read(1)
    await trigger_go(dut)
    await wait_for_idle(dut)

    assert read_data.get_test_array() == test_data.get_test_array()


@cocotb.test()
@cocotb.parametrize(length=[6, 7])
async def write_burst_test(dut, length):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    await reset_model(dut)
    test_data = DummyData(length)
    address = 0x002000

    config_transaction(dut, OPCODE.write_enable)
    handler = DataHandler(dut, test_data)
    handler.start_write()
    await trigger_go(dut)
    await wait_for_idle(dut)

    await T_rwr

    assert check_write_enable(dut)

    config_transaction(dut, OPCODE.write, address=address)
    await trigger_go(dut)
    await wait_for_idle(dut)
    await T_rwr

    memory_data = MemoryModelHelper.get_memory_s70kl1283(dut.Memory, address, test_data.num_bytes +1)
    extended_test_data = test_data.get_test_array()
    extended_test_data.append(0xff)
    assert memory_data == extended_test_data


@cocotb.test()
@cocotb.parametrize(length=[6, 7])
async def read_burst_test(dut, length):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    await reset_model(dut)
    test_data = DummyData(length)
    address = 0x002010

    MemoryModelHelper.set_memory_s70kl1283(dut.Memory, address, test_data.get_test_array())

    config_transaction(dut, OPCODE.read, address=address)
    read_data = DummyData(0)
    handler = DataHandler(dut, read_data)
    handler.start_read(length)
    await trigger_go(dut)
    await wait_for_idle(dut)

    assert len(handler._data._array) == test_data.num_bytes
    assert read_data.get_test_array() == test_data.get_test_array()


# @cocotb.test()
# async def byte_masking_test(dut):


def test_octal_spi_model(wave=False):
    """
    Test if the basics of the Octal SPI protocol are implemented correctly.
    """
    required_file = Path(
        "../../test/memory_models/infineon-verilog-model-for-octal-spi-interface-simulationmodels-en-09018a90808f2609/002-30135/s70kl1283_00.v"
    )
    if not required_file.exists():
        raise SkipTest(f"Simulation Model for S70KL1283 not found!")

    proj_path = Path(__file__).resolve().parent
    sources = [
        proj_path / "../../src/OctalSPITransmitter.v",
        proj_path / "../../test/cocotb_wrapper/Octal_SPI_wrapper.v",
        proj_path / required_file,
    ]

    sim = os.getenv("SIM", "questa")
    try:
        runner = get_runner(sim)
    except SystemExit:
        raise SkipTest(f"Simulator {sim} not found!")

    runner.build(sources=sources, hdl_toplevel="Octal_SPI_wrapper", always=True, waves=True)
    runner.test(
        hdl_toplevel="Octal_SPI_wrapper",
        test_module="test_octal_spi_model",
        gui=wave,
        waves=True,
        pre_cmd=["source ../parameter_octal_spi_model.tcl"],
    )


if __name__ == "__main__":
    test_octal_spi_model(wave=True)
