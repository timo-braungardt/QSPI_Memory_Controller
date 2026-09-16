from HelperClasses import DummyData


def test_initialisation():
    data = DummyData()
    assert data.num_bytes == 0
    assert len(data._array) == 0

    data.generate_test_array(5)
    assert data.num_bytes == 5
    assert len(data._array) == 5

    data_new = DummyData(5)
    assert data_new.num_bytes == 5
    assert len(data_new._array) == 5


def test_endianness_get_number():
    test_array = [0] * 3
    test_array[0] = 1
    test_array[1] = 2
    test_array[2] = 3

    data = DummyData(3)
    data._array = test_array

    little_endian = 0x030201
    big_endian = 0x010203

    data.is_little_endian = True
    assert data.get_test_number() == little_endian
    assert data.get_test_number() != big_endian

    data.is_little_endian = False
    assert data.get_test_number() != little_endian
    assert data.get_test_number() == big_endian


def test_endianness_get_word():
    data = DummyData(8)
    data._array = range(8)

    data.is_little_endian = True
    little_endian = 0x03020100
    little_endian_next = 0x07060504
    assert data.get_test_number_word(0) == little_endian
    assert data.get_test_number_word(4) == little_endian_next

    data.is_little_endian = False
    big_endian = 0x00010203
    big_endian_next = 0x04050607
    assert data.get_test_number_word(0) == big_endian
    assert data.get_test_number_word(4) == big_endian_next
