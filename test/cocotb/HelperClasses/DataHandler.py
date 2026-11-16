import cocotb
from cocotb.triggers import RisingEdge


class DataHandler:
    def __init__(self, interface, data):
        self._interface = interface
        self._task = None
        self._data = data

    async def _run(self):
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

    def start(self):
        assert self._task is None, "Driver is already running!"
        self._task = cocotb.start_soon(self._run())

    def stop(self):
        assert self._task is not None, "Driver is not running!"
        # Cancel the task to stop the Driver's execution.
        self._task.cancel()
        self._task = None
