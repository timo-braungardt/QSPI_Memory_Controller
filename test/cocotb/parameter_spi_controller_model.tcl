log -r /*;
add wave sim:/SPIController_wrapper/Memory/PoweredUp;
add wave sim:/SPIController_wrapper/data;
add wave sim:/SPIController_wrapper/chip_select_neg;
add wave sim:/SPIController_wrapper/bus_clock;
add wave sim:/SPIController_wrapper/Controller/opcode_reg;
add wave sim:/SPIController_wrapper/Controller/address_reg;
add wave sim:/SPIController_wrapper/Controller/data_in_reg;
add wave sim:/SPIController_wrapper/Controller/o_data_read;
add wave sim:/SPIController_wrapper/Controller/control_state_reg;
add wave sim:/SPIController_wrapper/Controller/SPI_Transmitter/state_reg;
add wave sim:/SPIController_wrapper/Controller/config_is_config_operation;
add wave sim:/SPIController_wrapper/Memory/data_out;
add wave sim:/SPIController_wrapper/Memory/SFDP_array;
add wave sim:/SPIController_wrapper/Memory/Instruct;
add wave sim:/SPIController_wrapper/Memory/QUADIT;
run -all;
wave zoom full
