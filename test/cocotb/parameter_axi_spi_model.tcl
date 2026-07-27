log -r /*;
add wave sim:/AXI_SPI_wrapper/clk;
add wave sim:/AXI_SPI_wrapper/Memory/PoweredUp;
add wave sim:/AXI_SPI_wrapper/s_spi_manager_serial_out ;
add wave sim:/AXI_SPI_wrapper/s_spi_manager_serial_in;
add wave sim:/AXI_SPI_wrapper/s_spi_chip_select_neg;
add wave sim:/AXI_SPI_wrapper/s_spi_clock;
add wave sim:/AXI_SPI_wrapper/Controller/SPI_Controller/state;
add wave sim:/AXI_SPI_wrapper/Memory/data_out;
add wave sim:/AXI_SPI_wrapper/Memory/Instruct;
add wave sim:/AXI_SPI_wrapper/Controller/read_state_reg;
add wave sim:/AXI_SPI_wrapper/Controller/write_state_reg;
add wave sim:/AXI_SPI_wrapper/rst;
run -all;
wave zoom full
