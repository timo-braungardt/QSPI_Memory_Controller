import os
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ClockCycles, First
from cocotb.clock import Clock
from HelperClasses import DummyData, MemoryModelHelper, DataHandler
from unittest import SkipTest

DATA_WIDTH = int(os.environ.get("PARAM_DATA_WIDTH", 32))
DATA_WIDTH_BYTES = DATA_WIDTH // 8

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


def config_transaction(dut, opcode, address=0, data_mask=0b0000, only_one_word=True):
    dut.i_address.value = address
    dut.i_last.value = only_one_word

    if opcode == OPCODE.write:
        dut.i_write_valid.value = True
        dut.i_write_data_mask.value = data_mask
        dut.i_write_enable.value = True

    if opcode == OPCODE.read:
        dut.i_write_enable.value = False

    if opcode == OPCODE.read_id:
        dut.i_address.value = 0
        dut.i_write_enable.value = False


@cocotb.test()
async def write_test(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    num_bytes = 4

    await Timer(50, unit="ns")
    await reset_model(dut)
    test_data = DummyData(num_bytes)
    address = 0x001000

    MemoryModelHelper.set_memory_s70kl1283(dut.Memory, address, [0]*2*num_bytes)
    config_transaction(dut, OPCODE.write, address=address)
    handler = DataHandler(interface=dut, data=test_data, bus_width=DATA_WIDTH_BYTES)
    handler.start_write()
    await trigger_go(dut)
    await wait_for_idle(dut)
    await wait_for_idle(dut)
    await T_rwr

    memory_data = MemoryModelHelper.get_memory_s70kl1283(dut.Memory, address, 2*num_bytes)
    # the controller shall only write one byte
    extended_test_data = test_data.get_test_array()
    extended_test_data.extend([0]*4)
    assert memory_data == extended_test_data


@cocotb.test()
async def write_mask_test(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    await reset_model(dut)
    test_data = DummyData(4)
    address = 0x000100

    MemoryModelHelper.set_memory_s70kl1283(dut.Memory, address, [0]*4)
    config_transaction(dut, OPCODE.write, address=address, data=test_data.get_test_number(), data_mask=0b0110)
    await trigger_go(dut)
    await wait_for_idle(dut)
    await wait_for_idle(dut)
    await T_rwr

    memory_data = MemoryModelHelper.get_memory_s70kl1283(dut.Memory, address, 4)
    assert memory_data != test_data.get_test_array()
    assert memory_data[0] == test_data.get_test_array()[0]
    assert memory_data[1] == 0
    assert memory_data[2] == 0
    assert memory_data[3] == test_data.get_test_array()[3]


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
    handler = DataHandler(dut, read_data, DATA_WIDTH_BYTES)
    handler.start_read(4, DATA_WIDTH_BYTES)
    await trigger_go(dut)
    await wait_for_idle(dut)

    # since now we only read word wise, we have to append some data to the test data
    # (issue #18)
    test_data._array.append(0x00)
    test_data._array.append(0xff)
    test_data._array.append(0xff)
    assert read_data.get_test_array() == test_data.get_test_array()


@cocotb.test()
async def variable_latency_test(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    await reset_model(dut)
    test_data = DummyData(1)

    config_transaction(dut, OPCODE.write, address=0x001000, data=test_data.get_test_number())
    await trigger_go(dut)
    await wait_for_idle(dut)
    await wait_for_idle(dut)

    MemoryModelHelper.set_variable_latency_s70kl1283(dut.Memory)

    await T_rwr

    config_transaction(dut, OPCODE.read, address=0x001000, data=test_data.get_test_number())
    await trigger_go(dut)
    await wait_for_idle(dut)

    assert dut.o_read_data.value.to_unsigned() == test_data.get_test_number()


@cocotb.test()
@cocotb.parametrize(num_bytes=[DATA_WIDTH_BYTES, DATA_WIDTH_BYTES*2])
async def write_burst_test(dut, num_bytes):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    await reset_model(dut)
    test_data = DummyData(num_bytes)
    print(test_data.get_test_array())
    address = 0x002000

    config_transaction(dut, OPCODE.write, address=address)
    handler = DataHandler(interface=dut, data=test_data, bus_width=DATA_WIDTH_BYTES)
    handler.start_write()
    await trigger_go(dut)
    await wait_for_idle(dut)
    await wait_for_idle(dut)
    await T_rwr

    memory_data = MemoryModelHelper.get_memory_s70kl1283(dut.Memory, address, test_data.num_bytes)
    assert memory_data == test_data.get_test_array()
    


@cocotb.test()
@cocotb.parametrize(num_bytes=[DATA_WIDTH_BYTES, DATA_WIDTH_BYTES*2])
async def read_burst_test(dut, num_bytes):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    await reset_model(dut)
    test_data = DummyData(num_bytes)
    print(test_data.get_test_array())
    address = 0x002010
    
    MemoryModelHelper.set_memory_s70kl1283(dut.Memory, address, test_data.get_test_array())

    config_transaction(dut, OPCODE.read, address=address)
    read_data = DummyData(0)
    handler = DataHandler(dut, read_data, DATA_WIDTH_BYTES)
    handler.start_read(num_bytes, DATA_WIDTH_BYTES)
    
    await trigger_go(dut)
    await wait_for_idle(dut)

    assert read_data.get_test_array() == test_data.get_test_array()


@cocotb.test()
async def correct_opcode_test(dut):
    """
    This test checks if the opcode set in the controller is the same as the Infineon opcodes.
    """
    assert dut.Controller.OPCODE_READ.value.to_unsigned() == OPCODE.read
    assert dut.Controller.OPCODE_WRITE.value.to_unsigned() == OPCODE.write


def test_octal_spi_controller_model(wave=False):
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
        proj_path / "../../src/OctalSPIController.v",
        proj_path / "../../test/cocotb_wrapper/Octal_SPI_Controller_wrapper.v",
        proj_path / required_file,
    ]

    sim = os.getenv("SIM", "questa")
    try:
        runner = get_runner(sim)
    except SystemExit:
        raise SkipTest(f"Simulator {sim} not found!")

    runner.build(sources=sources, hdl_toplevel="Octal_SPI_Controller_wrapper", always=True, waves=True)
    runner.test(
        hdl_toplevel="Octal_SPI_Controller_wrapper",
        test_module="test_octal_spi_controller_model",
        gui=wave,
        waves=True,
        pre_cmd=["source ../parameter_octal_spi_controller_model.tcl"],
    )


if __name__ == "__main__":
    test_octal_spi_controller_model(wave=True)
