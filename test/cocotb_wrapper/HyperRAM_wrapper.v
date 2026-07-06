`timescale 1ns / 100ps

module HyperRAM_wrapper;
    reg clk   = 1'b0;
    reg go    = 1'b0;
    reg reset = 1'b1;

    wire bus_clock;
    wire chip_select_neg;
    wire [7:0] data;
    wire data_strobe;


    Hyperbus controller (
        .clk(clk),
        .go(go),
        .o_bus_clock(bus_clock),
        .o_bus_clock_neg(SerialClk_neg),
        .o_chip_select_neg(chip_select_neg),
        .io_data(data),
        .io_data_strobe(data_strobe)
    );


    s27kl0641 #(
        .TimingModel("S27KL0641DABHI000")
    ) RAM (
        .DQ7(data[7]),
        .DQ6(data[6]),
        .DQ5(data[5]),
        .DQ4(data[4]),
        .DQ3(data[3]),
        .DQ2(data[2]),
        .DQ1(data[1]),
        .DQ0(data[0]),
        .RWDS(data_strobe),
        .CSNeg(chip_select_neg),
        .CK(bus_clock),
        .RESETNeg(reset)
    );

endmodule
