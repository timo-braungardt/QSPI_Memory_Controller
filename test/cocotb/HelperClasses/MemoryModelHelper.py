class MemoryModelHelper:
    def set_memory_s70kl1283(model, address, data):
        is_odd_address = address % 2
        is_odd_number = len(data) % 2

        change_this = data[0] << 8

        model.bottom.Mem[address].value = change_this # only one byte is written, not more


    def get_memory_s70kl1283(model, address, num_bytes):
        data_array = []
        num_words = (num_bytes + 1) // 2

        for i in range(num_words):
            data = model.bottom.Mem[address + i].value
            data_lower = data % 256
            data_upper = data >> 8
            data_array.append(data_lower)
            data_array.append(data_upper)

        return data_array[:num_bytes]
