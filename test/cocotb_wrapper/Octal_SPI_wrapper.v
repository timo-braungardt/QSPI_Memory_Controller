`timescale 1ps / 1ps

module Octal_SPI_wrapper;
    reg clk;
    reg go;
    reg reset_neg = 1'b0;

    wire [7:0] data;
    wire manager_serial_out, manager_serial_in, bus_clock, bus_clock_neg, chip_select_neg, data_strobe;

    OctalSPI Controller (
        .clk(clk),
        .reset_neg(reset_neg),
        .go(go),

        .o_bus_clock(bus_clock),
        .o_bus_clock_neg(bus_clock_neg),
        .o_chip_select_neg(chip_select_neg),
        .io_data(data),
        .io_data_strobe(data_strobe)
    );


    s70kl1283 Memory (
        .DQ7 (data[7]),
        .DQ6 (data[6]),
        .DQ5 (data[5]),
        .DQ4 (data[4]),
        .DQ3 (data[3]),
        .DQ2 (data[2]),
        .DQ1 (data[1]),
        .DQ0 (data[0]),
        .RWDS(data_strobe),

        .CSNeg(chip_select_neg),
        .CK(bus_clock),
        .CKn(bus_clock_neg),
        .RESETNeg(reset_neg)
    );


endmodule
