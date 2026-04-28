import cocotb
from cocotb.triggers import Timer


async def generate_clock(dut):
    for _ in range(1):
        dut.clk.value = 0
        await Timer(1, unit="ns")
        dut.clk.value = 1
        await Timer(1, unit="ns")


@cocotb.test()
async def my_first_test(dut):
    cocotb.start_soon(generate_clock(dut))

    await Timer(2, unit="ns")
    cocotb.log.info("signal is %s", dut.signal.value)
    assert dut.signal.value == 0
