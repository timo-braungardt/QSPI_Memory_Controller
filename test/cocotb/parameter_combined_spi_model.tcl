log -r /*;
add wave sim:/Combined_SPI_wrapper/Memory/PoweredUp;
add wave sim:/Combined_SPI_wrapper/data;
add wave sim:/Combined_SPI_wrapper/chip_select_neg;
add wave sim:/Combined_SPI_wrapper/bus_clock;
add wave sim:/Combined_SPI_wrapper/Controller/buffer;
add wave sim:/Combined_SPI_wrapper/Controller/state_reg;
add wave sim:/Combined_SPI_wrapper/Memory/data_out;
add wave sim:/Combined_SPI_wrapper/Memory/SFDP_array;
add wave sim:/Combined_SPI_wrapper/Memory/Instruct;
run -all;
wave zoom full
