`timescale 1ns / 100ps

module SPI_wrapper;
    reg clk;
    reg go;
    reg reset = 1'b1;

    wire manager_serial_out, manager_serial_in, bus_clock, chip_select_neg;

    BasicSPI Controller (
        .clk(clk),
        .reset(reset),
        .go(go),
        .o_bus_clock(bus_clock),
        .o_chip_select_neg(chip_select_neg),
        .io_manager_serial_in(manager_serial_in),
        .io_manager_serial_out(manager_serial_out)
    );


    s25hl512t Memory (
        .SI(manager_serial_out),
        .SO(manager_serial_in),
        .SCK(bus_clock),
        .CSNeg(chip_select_neg),
        .RESETNeg(~reset)
    );


endmodule
