import cocotb
from cocotb.triggers import RisingEdge


class DataHandler:
    def __init__(self, interface, data):
        self._interface = interface
        self._task = None
        self._data = data

    async def _run_write(self):
        index = 0
        try:
            self._interface.i_write_valid.value = 1
            self._interface.i_write_data.value = self._data.get_test_number_word(0, width=1)
            self._interface.i_write_data_byte_mask.value = 0
            self._interface.i_last_byte.value = (self._data.num_bytes <= 1)

            while index < self._data.num_bytes:
                await RisingEdge(self._interface.clk)
                if self._interface.o_write_ready.value == 1:
                    index += 1
                    self._interface.i_write_data.value = self._data.get_test_number_word(
                        index, width=1
                    )
                    if index == self._data.num_bytes - 1:
                        self._interface.i_last_byte.value = True

        finally:
            # Clean up the interface when the task is cancelled.
            # This is triggered by the CancelledError exception being raised.
            self._interface.i_write_valid.value = 0
            self._interface.i_write_data.value = 0
            self._interface.i_write_data_byte_mask.value = 0
            self._interface.i_last_byte.value = True
    
    async def _run_read(self, num_bytes):
        index = 0
        self._data._array = []
        try:
            self._interface.i_read_ready.value = 1
            self._interface.i_last_byte.value = (num_bytes <= 1)

            while True:
                await RisingEdge(self._interface.clk)
                if self._interface.o_read_valid.value == 1:
                    index += 1
                    self._data._array.append(self._interface.o_read_data.value.to_unsigned())

                    if index == num_bytes - 2:
                        self._interface.i_last_byte.value = True

        finally:
            # Clean up the interface when the task is cancelled.
            # This is triggered by the CancelledError exception being raised.
            self._interface.i_write_valid.value = 0
            self._interface.i_write_data.value = 0
            self._interface.i_write_data_byte_mask.value = 0
            self._interface.i_last_byte.value = True

    def start_write(self):
        assert self._task is None, "Driver is already running!"
        self._task = cocotb.start_soon(self._run_write())

    def start_read(self, num_bytes):
        assert self._task is None, "Driver is already running!"
        self._task = cocotb.start_soon(self._run_read(num_bytes))

    def stop(self):
        assert self._task is not None, "Driver is not running!"
        # Cancel the task to stop the Driver's execution.
        self._task.cancel()
        self._task = None
