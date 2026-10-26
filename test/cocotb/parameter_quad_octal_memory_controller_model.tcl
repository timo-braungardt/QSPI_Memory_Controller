log -r /*;
add wave sim:/Quad_Octal_Memory_Controller_wrapper/clk;
add wave sim:/Quad_Octal_Memory_Controller_wrapper/reset;
add wave sim:/Quad_Octal_Memory_Controller_wrapper/test_number
add wave sim:/Quad_Octal_Memory_Controller_wrapper/bus_clock;
add wave sim:/Quad_Octal_Memory_Controller_wrapper/chip_select_neg;
add wave sim:/Quad_Octal_Memory_Controller_wrapper/mem_data;
add wave sim:/Quad_Octal_Memory_Controller_wrapper/control_data_output_enable
add wave sim:/Quad_Octal_Memory_Controller_wrapper/mem_data_strobe;
add wave sim:/Quad_Octal_Memory_Controller_wrapper/control_strobe_output_enable
add wave -position end  sim:/Quad_Octal_Memory_Controller_wrapper/Controller/SPI_Controller/SPI_Transmitter/state_reg
add wave -position end  sim:/Quad_Octal_Memory_Controller_wrapper/Controller/SPI_Controller/control_state_reg
add wave -position end  sim:/Quad_Octal_Memory_Controller_wrapper/gen_memory[3]/Memory/bottom/Address
add wave -position end  sim:/Quad_Octal_Memory_Controller_wrapper/gen_memory[3]/Memory/bottom/Data_in
run -all;
wave zoom full
