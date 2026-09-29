log -r /*;
add wave sim:/Octal_Memory_Controller_wrapper/clk;
add wave sim:/Octal_Memory_Controller_wrapper/reset;
add wave sim:/Octal_Memory_Controller_wrapper/data_strobe;
add wave sim:/Octal_Memory_Controller_wrapper/data;
add wave sim:/Octal_Memory_Controller_wrapper/chip_select_neg;
add wave sim:/Octal_Memory_Controller_wrapper/bus_clock;
add wave sim:/Octal_Memory_Controller_wrapper/Controller/genblk1/SPI_Controller/SPI_Transmitter/state_reg;
add wave sim:/Octal_Memory_Controller_wrapper/Controller/genblk1/SPI_Controller/SPI_Transmitter/count_reg;
add wave sim:/Octal_Memory_Controller_wrapper/Memory/bottom/Dout;
add wave sim:/Octal_Memory_Controller_wrapper/Memory/bottom/PoweredUp;
add wave sim:/Octal_Memory_Controller_wrapper/Controller/genblk1/SPI_Controller/o_data_read;
add wave sim:/Octal_Memory_Controller_wrapper/Controller/genblk1/SPI_Controller/i_data_write;
run -all;
wave zoom full
