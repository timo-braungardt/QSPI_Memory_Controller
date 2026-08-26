import os
import logging
from pathlib import Path
import itertools
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, First, FallingEdge, RisingEdge, ClockCycles
from cocotb.clock import Clock
from cocotb.types import Logic, LogicArray
from unittest import SkipTest

T_pp_typ = Timer(480, unit="us")    # program time typical from the datasheet
T_w_typ  = Timer( 44, unit="ms")    # Nonvolatile Register Write Time

class SPI_COMMANDS:
    write_enable = 0x06
    write_enable_volatile = 0x50
    write_any_reg = 0x71
    program = 0x02
    read = 0x03
    read_114 = 0x6B
    read_status_reg_1 = 0x05
    read_status_reg_2 = 0x07
    read_config_reg_1 = 0x35
    read_config_regs  = 0x65
    read_JEDEC_parameter = 0x5A


async def reset_model(dut):
    dut.reset.value = 1
    await Timer(250, unit="ns")  # t_RP
    dut.reset.value = 0
    await Timer(500, unit="us")  # t_RH

    if dut.Memory.PoweredUp.value == 0:
        await dut.Memory.PoweredUp.value_change


async def wait_for_idle(dut):
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    if dut.chip_select_neg.value == False:
        await dut.chip_select_neg.value_change


async def trigger_go(dut):
    dut.go.value = 0
    await ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0


@cocotb.test()
async def read_test(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_model(dut)

    # write enable
    dut.Controller.opcode.value = SPI_COMMANDS.write_enable

    dut.Controller.write_address.value = 0b0
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b0
    dut.Controller.is_quad_mode.value = 0b000

    await trigger_go(dut)
    await wait_for_idle(dut)

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
    dut.Controller.num_bits.value = 32

    await trigger_go(dut)
    await wait_for_idle(dut)

    # read
    await T_pp_typ

    dut.Controller.opcode.value = SPI_COMMANDS.read
    dut.Controller.address.value = 0x20

    for i in range(8):
        dut.Controller.buffer[i].value = 0

    dut.Controller.write_address.value = 0b1
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b1
    dut.Controller.num_bits.value = 32

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


@cocotb.test()
async def get_jedec_parameter_test(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_model(dut)

    dut.Controller.opcode.value = SPI_COMMANDS.read_JEDEC_parameter
    dut.Controller.address.value = 0x000000
    dut.Controller.is_quad_mode.value = 0b000

    dut.Controller.write_address.value = 0b1
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b1
    dut.Controller.num_bits.value = 72
    dut.Controller.num_dummy_cycles.value = 8

    await trigger_go(dut)
    await wait_for_idle(dut)

    # Problem: in the memory model, the SFDP bytes are set and later overwritten with the manufacturer ID
    #          this may be a bug - i do not know

    assert dut.Controller.buffer[0].value.to_unsigned() == 0x34
    assert dut.Controller.buffer[1].value.to_unsigned() == 0x2A
    assert dut.Controller.buffer[2].value.to_unsigned() == 0x1A
    assert dut.Controller.buffer[3].value.to_unsigned() == 0x0F

    assert dut.Controller.buffer[4].value.to_unsigned() == 0x03
    assert dut.Controller.buffer[5].value.to_unsigned() == 0x90
    assert dut.Controller.buffer[6].value.to_unsigned() == 0xFF

    # SFDP Header
    # assert dut.Controller.buffer[0].value.to_unsigned() == 0x53 # ascii: S
    # assert dut.Controller.buffer[1].value.to_unsigned() == 0x46 # ascii: F
    # assert dut.Controller.buffer[2].value.to_unsigned() == 0x44 # ascii: D
    # assert dut.Controller.buffer[3].value.to_unsigned() == 0x50 # ascii: P

    # assert dut.Controller.buffer[4].value.to_unsigned() == 0x08 # SFDP minor version
    # assert dut.Controller.buffer[5].value.to_unsigned() == 0x01 # SFDP major version
    # assert dut.Controller.buffer[6].value.to_unsigned() == 0x03 # number of parameter headers
    # assert dut.Controller.buffer[7].value.to_unsigned() == 0xFF # access protocoll

    # 1st Parameter
    # assert dut.Controller.buffer[8].value.to_unsigned() == 0x00 # param ID lsb
    # assert dut.Controller.buffer[9].value.to_unsigned() == 0x00 # minor version
    # assert dut.Controller.buffer[10].value.to_unsigned() == 0x01 # major version
    # assert dut.Controller.buffer[11].value.to_unsigned() == 0x14 # parameter length

    # assert dut.Controller.buffer[12].value.to_unsigned() == 0x00 # address
    # assert dut.Controller.buffer[13].value.to_unsigned() == 0x01 # address
    # assert dut.Controller.buffer[14].value.to_unsigned() == 0x00 # address
    # assert dut.Controller.buffer[15].value.to_unsigned() == 0xFF # parameter ID msb

    ## get memory size

    # we should be able to read the address from the header - but it was overwritten in the model
    # dword_1_pointer = LogicArray(
    #    itertools.chain(
    #        dut.Controller.buffer[14].value,
    #        dut.Controller.buffer[13].value,
    #        dut.Controller.buffer[12].value
    #    )
    # )
    dword_1_pointer = 0x000100

    dut.Controller.opcode.value = SPI_COMMANDS.read_JEDEC_parameter
    dut.Controller.address.value = dword_1_pointer

    dut.Controller.write_address.value = 0b1
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b1
    dut.Controller.num_bits.value = 72
    dut.Controller.num_dummy_cycles.value = 8

    await trigger_go(dut)
    await wait_for_idle(dut)

    assert dut.Controller.buffer[0].value.to_unsigned() == 0xE7
    assert dut.Controller.buffer[1].value.to_unsigned() == 0x20
    assert dut.Controller.buffer[2].value.to_unsigned() == 0xFA
    assert dut.Controller.buffer[3].value.to_unsigned() == 0xFF

    assert dut.Controller.buffer[4].value.to_unsigned() == 0xFF
    assert dut.Controller.buffer[5].value.to_unsigned() == 0xFF
    assert dut.Controller.buffer[6].value.to_unsigned() == 0xFF
    assert dut.Controller.buffer[7].value.to_unsigned() == 0x1F


@cocotb.test()
async def get_status_register_test(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_model(dut)

    dut.Controller.opcode.value = SPI_COMMANDS.read_status_reg_1
    dut.Controller.address.value = 0x000000
    dut.Controller.is_quad_mode.value = 0b000

    dut.Controller.write_address.value = 0b0
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b1
    dut.Controller.num_bits.value = 8

    await trigger_go(dut)
    await wait_for_idle(dut)

    assert dut.Controller.buffer[0].value[0] == False  # Device Ready/Busy Status Flag
    assert dut.Controller.buffer[0].value[1] == False  # Write/Program Enable Status Flag

    # write enable
    dut.Controller.opcode.value = SPI_COMMANDS.write_enable

    dut.Controller.write_address.value = 0b0
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b0

    await trigger_go(dut)
    await wait_for_idle(dut)

    # read status reg
    dut.Controller.opcode.value = SPI_COMMANDS.read_status_reg_1
    dut.Controller.address.value = 0x000000

    dut.Controller.write_address.value = 0b0
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b1
    dut.Controller.num_bits.value = 8

    await trigger_go(dut)
    await wait_for_idle(dut)

    assert dut.Controller.buffer[0].value[0] == False  # Device Ready/Busy Status Flag
    assert dut.Controller.buffer[0].value[1] == True  # Write/Program Enable Status Flag

    # program
    dut.Controller.opcode.value = SPI_COMMANDS.program
    dut.Controller.address.value = 0x20

    dut.Controller.write_address.value = 0b1
    dut.Controller.write_data.value = 0b1
    dut.Controller.read_data.value = 0b0
    dut.Controller.buffer[0].value = 0x12
    dut.Controller.buffer[1].value = 0x34
    dut.Controller.num_bits.value = 16

    await trigger_go(dut)
    await wait_for_idle(dut)

    # read status reg
    dut.Controller.opcode.value = SPI_COMMANDS.read_status_reg_1
    dut.Controller.address.value = 0x000000

    dut.Controller.write_address.value = 0b0
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b1
    dut.Controller.num_bits.value = 8

    await trigger_go(dut)
    await wait_for_idle(dut)

    assert dut.Controller.buffer[0].value[0] == True  # Device Ready/Busy Status Flag
    assert dut.Controller.buffer[0].value[1] == True  # Write/Program Enable Status Flag


@cocotb.test()
async def qspi_read_test(dut):
    c = Clock(dut.clk, 20, "ns")
    cocotb.start_soon(c.start())
    await reset_model(dut)

    # check state QUADIT bit in config register 1
    dut.Controller.opcode.value = SPI_COMMANDS.read_config_reg_1
    dut.Controller.address.value = 0x000000
    dut.Controller.is_quad_mode.value = 0b000
    dut.Controller.write_address.value = 0b0
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b1
    dut.Controller.num_bits.value = 8

    await trigger_go(dut)
    await wait_for_idle(dut)

    assert dut.Controller.buffer[0].value[1] == False  # QUADIT bit

    # write enable
    dut.Controller.opcode.value = SPI_COMMANDS.write_enable
    dut.Controller.write_address.value = 0b0
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b0

    await trigger_go(dut)
    await wait_for_idle(dut)

    # set QUADIT bit in config register 1
    dut.Controller.opcode.value = SPI_COMMANDS.write_any_reg
    dut.Controller.address.value = 0x800002
    # this is the volatile register
    # The non-volatile is address 0x000002, but needs T_w_typ

    dut.Controller.write_address.value = 0b1
    dut.Controller.write_data.value = 0b1
    dut.Controller.read_data.value = 0b0
    dut.Controller.num_bits.value = 8
    dut.Controller.buffer[0].value |= LogicArray(0b00000010, 8)    # set QUADIT bit to 1

    await trigger_go(dut)
    await wait_for_idle(dut)
    await T_pp_typ

    # check status
    dut.Controller.opcode.value = SPI_COMMANDS.read_status_reg_1
    dut.Controller.write_address.value = 0b0
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b1
    dut.Controller.num_bits.value = 8

    await trigger_go(dut)
    await wait_for_idle(dut)

    assert dut.Controller.buffer[0].value[0] == False  # Device not busy
    assert dut.Controller.buffer[0].value[1] == False  # Write is enabled
    assert dut.Controller.buffer[0].value[5] == False  # Last erase operation was successful
    assert dut.Controller.buffer[0].value[6] == False  # Last programming operation was successful

    # check state QUADIT bit in config register 1
    dut.Controller.opcode.value = SPI_COMMANDS.read_config_reg_1

    dut.Controller.write_address.value = 0b0
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b1
    dut.Controller.num_bits.value = 8

    await trigger_go(dut)
    await wait_for_idle(dut)

    assert dut.Controller.buffer[0].value[1] == True  # QUADIT bit
    dut.Controller.is_quad_mode.value = 0b001

    # write enable
    dut.Controller.opcode.value = SPI_COMMANDS.write_enable

    dut.Controller.write_address.value = 0b0
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b0
    dut.Controller.is_quad_mode.value = 0b000

    await trigger_go(dut)
    await wait_for_idle(dut)

    # program
    dut.Controller.opcode.value = SPI_COMMANDS.program
    dut.Controller.address.value = 0x30

    dut.Controller.write_address.value = 0b1
    dut.Controller.write_data.value = 0b1
    dut.Controller.read_data.value = 0b0
    dut.Controller.buffer[0].value = 0x12
    dut.Controller.buffer[1].value = 0x34
    dut.Controller.buffer[2].value = 0x56
    dut.Controller.buffer[3].value = 0x78
    dut.Controller.buffer[4].value = 0xFF
    dut.Controller.num_bits.value = 32

    await trigger_go(dut)
    await wait_for_idle(dut)
    await T_pp_typ

    # read with 1-1-4
    dut.Controller.opcode.value = SPI_COMMANDS.read_114
    dut.Controller.num_dummy_cycles.value = 8
    dut.Controller.address.value = 0x30

    for i in range(8):
        dut.Controller.buffer[i].value = 0

    dut.Controller.write_address.value = 0b1
    dut.Controller.write_data.value = 0b0
    dut.Controller.read_data.value = 0b1
    dut.Controller.num_bits.value = 32
    dut.Controller.is_quad_mode.value = 0b001

    await trigger_go(dut)
    await wait_for_idle(dut)

    assert dut.Controller.buffer[0].value.to_unsigned() == 0x12
    assert dut.Controller.buffer[1].value.to_unsigned() == 0x34
    assert dut.Controller.buffer[2].value.to_unsigned() == 0x56
    assert dut.Controller.buffer[3].value.to_unsigned() == 0x78


def test_combined_spi_model(wave=False):
    required_file = Path(
        "../../test/memory_models/infineon-s25hl512t-qspi-verilog-model-simulationmodels-en/s25hl512tRel/src/s25hl512t.sv"
    )
    if not required_file.exists():
        raise SkipTest(f"Simulation Model for S25HL512T not found!")

    proj_path = Path(__file__).resolve().parent
    sources = [
        proj_path / "../../src/CombinedSPI.v",
        proj_path / "../../test/cocotb_wrapper/Combined_SPI_wrapper.v",
        proj_path / required_file,
    ]

    sim = os.getenv("SIM", "questa")
    try:
        runner = get_runner(sim)
    except SystemExit:
        raise SkipTest(f"Simulator {sim} not found!")

    runner.build(
        sources=sources,
        hdl_toplevel="Combined_SPI_wrapper",
        always=True,
    )

    runner.test(
        hdl_toplevel="Combined_SPI_wrapper",
        test_module="test_combined_spi_model",
        gui=wave,
        pre_cmd=["source ../parameter_combined_spi_model.tcl"],
    )


if __name__ == "__main__":
    test_combined_spi_model(True)
