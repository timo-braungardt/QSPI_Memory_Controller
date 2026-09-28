log -r /*;
add wave sim:/Octal_SPI_Controller_wrapper/Memory/top/PoweredUp
add wave sim:/Octal_SPI_Controller_wrapper/clk
add wave sim:/Octal_SPI_Controller_wrapper/data
add wave sim:/Octal_SPI_Controller_wrapper/Controller/SPI_Transmitter/data_out_reg
add wave sim:/Octal_SPI_Controller_wrapper/Controller/SPI_Transmitter/en_data_out_reg
add wave sim:/Octal_SPI_Controller_wrapper/data_strobe
add wave sim:/Octal_SPI_Controller_wrapper/Controller/SPI_Transmitter/en_data_strobe
add wave sim:/Octal_SPI_Controller_wrapper/bus_clock
add wave sim:/Octal_SPI_Controller_wrapper/chip_select_neg
add wave sim:/Octal_SPI_Controller_wrapper/i_address
add wave sim:/Octal_SPI_Controller_wrapper/i_data_write
add wave sim:/Octal_SPI_Controller_wrapper/Controller/opcode_reg
add wave sim:/Octal_SPI_Controller_wrapper/i_last_word
add wave sim:/Octal_SPI_Controller_wrapper/o_data_read
add wave sim:/Octal_SPI_Controller_wrapper/o_next_word
add wave sim:/Octal_SPI_Controller_wrapper/o_recieved_next_word
add wave sim:/Octal_SPI_Controller_wrapper/Controller/SPI_Transmitter/state_reg
add wave sim:/Octal_SPI_Controller_wrapper/Controller/SPI_Transmitter/has_latency_reg
add wave sim:/Octal_SPI_Controller_wrapper/Controller/SPI_Transmitter/count_reg
add wave sim:/Octal_SPI_Controller_wrapper/Memory/bottom/CMD
add wave sim:/Octal_SPI_Controller_wrapper/Memory/bottom/Address
add wave sim:/Octal_SPI_Controller_wrapper/Memory/bottom/LByteMask
add wave sim:/Octal_SPI_Controller_wrapper/Memory/bottom/UByteMask
add wave sim:/Octal_SPI_Controller_wrapper/Memory/bottom/Data_in
add wave -position end  sim:/Octal_SPI_Controller_wrapper/Memory/bottom/BurstDelay
add wave -position end  sim:/Octal_SPI_Controller_wrapper/Memory/bottom/RefreshDelay
add wave -position end  sim:/Octal_SPI_Controller_wrapper/Controller/control_state_reg
add wave -position end  sim:/Octal_SPI_Controller_wrapper/Controller/i_write_enable
run -all;
wave zoom full
