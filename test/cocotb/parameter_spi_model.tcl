log -r /*;
add wave sim:/SPI_wrapper/Memory/PoweredUp;
add wave sim:/SPI_wrapper/manager_serial_out ;
add wave sim:/SPI_wrapper/manager_serial_in;
add wave sim:/SPI_wrapper/chip_select_neg;
add wave sim:/SPI_wrapper/bus_clock;
add wave sim:/SPI_wrapper/Controller/buffer;
add wave sim:/SPI_wrapper/Controller/state;
add wave sim:/SPI_wrapper/Memory/data_out;
add wave sim:/SPI_wrapper/Memory/SFDP_array;
add wave sim:/SPI_wrapper/Memory/Instruct;
run -all;
wave zoom full
