log -r /*;
add wave sim:/Quad_Octal_Memory_Controller_wrapper/clk;
add wave sim:/Quad_Octal_Memory_Controller_wrapper/reset;
add wave sim:/Quad_Octal_Memory_Controller_wrapper/test_number
add wave sim:/Quad_Octal_Memory_Controller_wrapper/mem_data_strobe;
add wave sim:/Quad_Octal_Memory_Controller_wrapper/mem_data;
add wave sim:/Quad_Octal_Memory_Controller_wrapper/mem_chip_select_neg;
add wave sim:/Quad_Octal_Memory_Controller_wrapper/bus_clock;
run -all;
wave zoom full
