`timescale 1ns / 100ps

module SPIController_wrapper;
    reg clk;
    reg go;
    reg reset_neg = 1'b0;

    wire [3:0] data;
    wire bus_clock, chip_select_neg;

    SPIController Controller (
        .clk(clk),
        .reset_neg(reset_neg),
        .go(go),
        .o_bus_clock(bus_clock),
        .o_chip_select_neg(chip_select_neg),
        .io_data0_manager_serial_in(data[0]),
        .io_data1_manager_serial_out(data[1]),
        .io_data2(data[2]),
        .io_data3(data[3])
    );


    s25hl512t Memory (
        .SCK(bus_clock),
        .RESETNeg(reset_neg),
        .CSNeg(chip_select_neg),
        .SI(data[1]),
        .SO(data[0]),
        .WPNeg(data[2]),
        .IO3_RESETNeg(data[3])
    );


endmodule
