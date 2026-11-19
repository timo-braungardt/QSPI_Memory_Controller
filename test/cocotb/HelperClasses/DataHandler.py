import cocotb
from cocotb.triggers import RisingEdge
from cocotb.handle import Immediate
from HelperClasses import DummyData


class DataHandler:
    def __init__(self, interface, data, bus_width = 1):
        self._interface = interface
        self._task = None
        self._data = data
        self._bus_width = bus_width

    async def _run_write(self, byte_mask):
        index = 0
        try:
            self._interface.i_write_valid.value = Immediate(1)
            self._interface.i_write_data.value = Immediate(self._data.get_test_number_word(0, width=self._bus_width))
            self._interface.i_write_data_mask.value = Immediate(byte_mask)
            self._interface.i_last.value = Immediate((self._data.num_bytes <= self._bus_width))

            while index < self._data.num_bytes:
                await RisingEdge(self._interface.clk)
                if self._interface.o_write_ready.value == 1:
                    index += self._bus_width
                    self._interface.i_write_data.value = self._data.get_test_number_word(
                        index, width=self._bus_width
                    )
                    if index == self._data.num_bytes - self._bus_width:
                        self._interface.i_last.value = True

        finally:
            # Clean up the interface when the task is cancelled.
            # This is triggered by the CancelledError exception being raised.
            self._interface.i_write_valid.value = 0
            self._interface.i_write_data.value = 0
            self._interface.i_write_data_mask.value = 0
            self._interface.i_last.value = True
    
    async def _run_read(self, num_bytes, bus_width = 1):
        index = 0
        self._data._array = []
        try:
            self._interface.i_read_ready.value = 1
            print(num_bytes)
            print(self._bus_width)
            self._interface.i_last.value = (num_bytes <= self._bus_width)

            while True:
                await RisingEdge(self._interface.clk)
                if self._interface.o_read_valid.value == 1:
                    index += self._bus_width
                    self._data._array.extend(
                        DummyData.convert_unsigned_to_array(self._interface.o_read_data.value.to_unsigned(), bus_width))
                    #print (self._data._array)
                    if index >= (num_bytes // self._bus_width) - 2:
                        self._interface.i_last.value = True

        finally:
            # Clean up the interface when the task is cancelled.
            # This is triggered by the CancelledError exception being raised.
            self._interface.i_write_valid.value = 0
            self._interface.i_write_data.value = 0
            self._interface.i_write_data_mask.value = 0
            self._interface.i_last.value = True

    def start_write(self, byte_mask=0):
        assert self._task is None, "Driver is already running!"
        self._task = cocotb.start_soon(self._run_write(byte_mask))

    def start_read(self, num_bytes, bus_width=1):
        assert self._task is None, "Driver is already running!"
        self._task = cocotb.start_soon(self._run_read(num_bytes, bus_width))

    def stop(self):
        assert self._task is not None, "Driver is not running!"
        # Cancel the task to stop the Driver's execution.
        self._task.cancel()
        self._task = None
