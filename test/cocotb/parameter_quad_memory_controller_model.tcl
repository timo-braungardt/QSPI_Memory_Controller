log -r /*;
add wave sim:/Quad_Memory_Controller_model_wrapper/clk;
add wave sim:/Quad_Memory_Controller_model_wrapper/reset_neg;
add wave sim:/Quad_Memory_Controller_model_wrapper/data[0];
add wave sim:/Quad_Memory_Controller_model_wrapper/data[1];
add wave sim:/Quad_Memory_Controller_model_wrapper/data[2];
add wave sim:/Quad_Memory_Controller_model_wrapper/data[3];
add wave sim:/Quad_Memory_Controller_model_wrapper/chip_select_neg;
add wave sim:/Quad_Memory_Controller_model_wrapper/bus_clock;
add wave sim:/Quad_Memory_Controller_model_wrapper/Controller/SPI_Controller/SPI_Transmitter/state_reg;
add wave sim:/Quad_Memory_Controller_model_wrapper/Controller/SPI_Controller/SPI_Transmitter/count_reg;
add wave sim:/Quad_Memory_Controller_model_wrapper/Memory/data_out;
add wave sim:/Quad_Memory_Controller_model_wrapper/Memory/Instruct;
add wave sim:/Quad_Memory_Controller_model_wrapper/Memory/PoweredUp;
add wave sim:/Quad_Memory_Controller_model_wrapper/Controller/SPI_Controller/o_data_read;
add wave sim:/Quad_Memory_Controller_model_wrapper/Controller/SPI_Controller/i_data_write;
run -all;
wave zoom full
