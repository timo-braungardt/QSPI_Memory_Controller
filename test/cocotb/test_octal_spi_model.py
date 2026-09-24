import os
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, RisingEdge
from cocotb.clock import Clock
from HelperClasses import DummyData


# opcode for the S70KL1283 Octal SPI RAM chip
class OPCODE:
    read = 0xEE
    write = 0xDE
    write_enable = 0x06
    read_id = 0x9F


async def reset_model(dut):
    dut.reset_neg.value = 0
    await Timer(200, unit="ns")  # t_RP
    dut.reset_neg.value = 1
    await Timer(200, unit="ns")  # t_RH

    if dut.Memory.top.PoweredUp.value == 0:
        await dut.Memory.top.PoweredUp.value_change


async def wait_for_idle(dut):
    timeout = Timer(100, unit="us")
    trigger = await First(RisingEdge(dut.o_chip_select_neg), timeout)
    assert trigger != timeout


async def trigger_go(dut):
    dut.go.value = 0
    await ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0


def config_transaction(dut, opcode, address=0, data=0):
    dut.i_address.value = address
    dut.i_opcode.value = opcode
    dut.i_last_word.value = True

    if opcode == OPCODE.write:
        dut.i_data_write.value = data
        dut.i_config_read_data.value = False
        dut.i_config_write_data.value = True
        dut.i_config_write_address.value = True

    if opcode == OPCODE.read:
        dut.i_config_read_data.value = True
        dut.i_config_write_data.value = False
        dut.i_config_write_address.value = True

    if opcode == OPCODE.write_enable:
        dut.i_config_read_data.value = False
        dut.i_config_write_data.value = False
        dut.i_config_write_address.value = False

    if opcode == OPCODE.read_id:
        dut.i_address.value = 0
        dut.i_config_read_data.value = True
        dut.i_config_write_data.value = False
        dut.i_config_write_address.value = True


@cocotb.test()
async def read_write_test(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())

    await Timer(50, unit="ns")
    await reset_model(dut)
    test_data = DummyData(1)

    config_transaction(dut, OPCODE.write_enable)
    await trigger_go(dut)
    await wait_for_idle(dut)

    config_transaction(dut, OPCODE.write, address=0x800001, data=test_data, num_bytes=1)
    await trigger_go(dut)
    await wait_for_idle(dut)

    config_transaction(dut, OPCODE.read, address=0x800001, data=test_data, num_bytes=1)
    await trigger_go(dut)
    await wait_for_idle(dut)

    assert dut.o_data_read.value.to_unsigned() == test_data.get_test_number()


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
        proj_path / "../../src/OctalSPI.v",
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
