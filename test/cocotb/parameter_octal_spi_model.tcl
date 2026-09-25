log -r /*;
add wave sim:/Octal_SPI_wrapper/Memory/top/PoweredUp
add wave sim:/Octal_SPI_wrapper/clk
add wave sim:/Octal_SPI_wrapper/data
add wave sim:/Octal_SPI_wrapper/Controller/data_out_reg
add wave sim:/Octal_SPI_wrapper/Controller/en_data_out_reg
add wave sim:/Octal_SPI_wrapper/data_strobe
add wave sim:/Octal_SPI_wrapper/Controller/en_data_strobe
add wave sim:/Octal_SPI_wrapper/bus_clock
add wave sim:/Octal_SPI_wrapper/chip_select_neg
add wave sim:/Octal_SPI_wrapper/i_address
add wave sim:/Octal_SPI_wrapper/i_data_write
add wave sim:/Octal_SPI_wrapper/i_opcode
add wave sim:/Octal_SPI_wrapper/i_last_word
add wave sim:/Octal_SPI_wrapper/o_data_read
add wave sim:/Octal_SPI_wrapper/o_need_next_byte
add wave sim:/Octal_SPI_wrapper/o_recieved_next_byte
add wave sim:/Octal_SPI_wrapper/Controller/state_reg
add wave sim:/Octal_SPI_wrapper/Controller/has_latency_reg
add wave sim:/Octal_SPI_wrapper/Controller/count_reg
add wave sim:/Octal_SPI_wrapper/Memory/bottom/CMD
add wave sim:/Octal_SPI_wrapper/Memory/bottom/Address
add wave sim:/Octal_SPI_wrapper/Memory/bottom/LByteMask
add wave sim:/Octal_SPI_wrapper/Memory/bottom/UByteMask
add wave sim:/Octal_SPI_wrapper/Memory/bottom/Data_in
add wave -position end  sim:/Octal_SPI_wrapper/Memory/bottom/BurstDelay
add wave -position end  sim:/Octal_SPI_wrapper/Memory/bottom/RefreshDelay
run -all;
wave zoom full
