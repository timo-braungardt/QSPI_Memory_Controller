import os
import logging
from pathlib import Path
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.triggers import Timer, First, FallingEdge, RisingEdge
from cocotb.clock import Clock


class HyperRamModel:
    def __init__(self, dut, size=8*1024*1024):
        self.log = logging.getLogger("MemoryModel")
        self.log.setLevel(logging.DEBUG)
        self.dut = dut
        self.addr = 0
        self.is_read = 0
        self.is_register_space = 0
        self.is_linear_burst = 0

        # 8 MB default
        self.mem = bytearray(size)

        self._run_coroutine_obj = None
        self._restart()


    def _restart(self):
        if self._run_coroutine_obj is not None:
            self._run_coroutine_obj.cancel()
        self._run_coroutine_obj = cocotb.start_soon(self._run())


    async def _run(self):
        while True:
            await FallingEdge(self.dut.o_ChipSelect_neg)
            ca = await self._read_ca()

            self.is_read = (ca >> 47) & 1
            self.is_register_space = (ca >> 46) & 1
            self.is_linear_burst = (ca >> 45) & 1
            
            self.addr = (ca >> 16) & 0x1FFFFFFF

            self.log.debug("test 0x%06x", (ca >> 16))
            self.addr <<= 3
            self.addr |= ca & 0x7

            self.log.debug(f"Is read is {self.is_read}")
            self.log.debug(f"Is register is {self.is_register_space}")
            self.log.debug(f"Is linear burst is {self.is_linear_burst}")
            self.log.debug("address is 0x%06x", self.addr)


    async def _read_ca(self):
        clk_edge = RisingEdge(self.dut.o_SpiClk)
        clk_neg_edge = RisingEdge(self.dut.o_SpiClk_neg)
        ca = 0
        for _ in range(6):
            await First(clk_edge, clk_neg_edge)
            word = int(self.dut.io_QD.value)
            ca <<= 8
            ca |= word
        
        self.log.debug("Recieved 0x%06x", ca)
        return ca


    async def _write_transaction(self, addr):
        while not self.dut.o_ChipSelect_neg.value:
            await RisingEdge(self.dut.o_SpiClk)
            data = int(self.dut.io_QD.value)
            self.mem[addr] = data
            addr += 1


    async def _read_transaction(self, addr):
        while not self.dut.o_ChipSelect_neg.value:
            data = self.mem[addr]
            self.dut.io_QD.value = BinaryValue(data, 8)
            await FallingEdge(self.dut.o_SpiClk)
            addr += 1
        self.dut.io_QD.value = BinaryValue("zzzzzzzz")


@cocotb.test()
async def transmission_test(dut):
    memory_model = HyperRamModel(dut)

    dut.is_read.value           = True
    dut.is_register_space.value = False
    dut.is_linear_burst.value   = False
    dut.address.value           = 0x8000000d
    dut.num_bits.value          = 8

    c = Clock(dut.clk  , 20, 'ns')
    cocotb.start_soon(c.start())

    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 5, rising=True)
    dut.go.value = 1
    await cocotb.triggers.ClockCycles(dut.clk, 1, rising=True)
    dut.go.value = 0
    await cocotb.triggers.ClockCycles(dut.clk, 2, rising=True)
    await dut.o_ChipSelect_neg.value_change

    assert memory_model.addr == 0x8000000d
    assert memory_model.is_read == True
    assert memory_model.is_register_space == False
    assert memory_model.is_linear_burst == False



def test_hyperbus():
    """
    Test if the basics of the Hyperbus protocol are implemented correctly.
    """
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../../src/Hyperbus.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="Hyperbus",
        always=True,
        waves=True
    )
    runner.test(hdl_toplevel="Hyperbus", 
				test_module="test_hyperbus",
                waves=True)


if __name__ == "__main__":
    test_hyperbus()
