import random


class DummyData:
    def __init__(self, num_bytes=0, word_width=4):
        self.num_bytes = num_bytes
        self._array = []
        self.generate_test_array(num_bytes)
        self.is_little_endian = True
        self.word_width = word_width

    def generate_test_array(self, num_bytes):
        self._array = []
        self.num_bytes = num_bytes

        for _ in range(num_bytes):
            self._array.append(random.randrange(256))

    def get_test_array(self):
        return self._array

    def get_test_number(self):
        number = 0
        if self.is_little_endian:
            for i in self._array[::-1]:
                number = (number << 8) + i
        else:
            for i in self._array:
                number = (number << 8) + i

        return number

    def get_test_number_word(self, address, width=-1):
        if width == -1:
            width = self.word_width

        number = 0
        start = address
        end = address + width
        if self.is_little_endian:
            for i in self._array[end - 1 :: -1][: self.word_width]:
                number = (number << 8) + i
        else:
            for i in self._array[start:end]:
                number = (number << 8) + i
        return number
