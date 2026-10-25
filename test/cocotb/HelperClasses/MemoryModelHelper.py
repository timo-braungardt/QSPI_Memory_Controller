from cocotb.handle import Immediate

class MemoryModelHelper:
    """This function does not handle uneven addresses or uneven data length yet."""
    def set_memory_s70kl1283(model, address, data):
        #is_odd_address = address % 2
        #is_odd_number = len(data) % 2

        word_array = []
        if len(data) == 1:
            word_array.append(data[0] << 8)
        else:
            for i in range(0, len(data), 2):
                temp = data[i] << 8
                temp = temp + data[i + 1]
                word_array.append(temp)

        num_words = (len(data) + 1) // 2
        for i in range(num_words):
            model.bottom.Mem[address + i].value = word_array[i]


    def get_memory_s70kl1283(model, address, num_bytes):
        data_array = []
        num_words = (num_bytes + 1) // 2

        for i in range(num_words):
            data = model.bottom.Mem[address + i].value
            data_lower = data % 256
            data_upper = data >> 8
            data_array.append(data_upper)
            data_array.append(data_lower)

        return data_array[:num_bytes]


    def set_variable_latency_s70kl1283(model):
        config = model.top.Config_reg0.value
        config[3] = 0
        model.top.Config_reg0.set(Immediate(config))

        config = model.bottom.Config_reg0.value
        config[3] = 0
        model.bottom.Config_reg0.set(Immediate(config))

        assert model.bottom.Config_reg0.value[3] == 0
        assert model.top.Config_reg0.value[3] == 0
