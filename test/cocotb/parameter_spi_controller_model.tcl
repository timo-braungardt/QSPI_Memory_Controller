log -r /*;
add wave sim:/SPIController_wrapper/Memory/PoweredUp;
add wave sim:/SPIController_wrapper/data;
add wave sim:/SPIController_wrapper/chip_select_neg;
add wave sim:/SPIController_wrapper/bus_clock;
add wave sim:/SPIController_wrapper/Controller/buffer;
add wave sim:/SPIController_wrapper/Controller/state_reg;
add wave sim:/SPIController_wrapper/Memory/data_out;
add wave sim:/SPIController_wrapper/Memory/SFDP_array;
add wave sim:/SPIController_wrapper/Memory/Instruct;
run -all;
wave zoom full
