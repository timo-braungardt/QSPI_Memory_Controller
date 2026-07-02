`timescale 1ns/100ps

module HyperRAM_wrapper;
    reg clk   = 1'b0;
    reg go    = 1'b0;
    reg reset = 1'b1;

    wire SerialClk;
    wire ChipSelect;
    wire [7:0] DQ;
    wire DataStrobe;


    Hyperbus controller(
        .clk(clk),
        .go(go),
        .o_bus_clock(SerialClk),
        .o_bus_clock_neg(SerialClk_neg),
        .o_chip_select_neg(ChipSelect),
        .io_data(DQ),
        .io_data_strobe(DataStrobe)
        );


    s27kl0641 #(.TimingModel("S27KL0641DABHI000"))
    RAM (
        .DQ7(DQ[7]),
        .DQ6(DQ[6]),
        .DQ5(DQ[5]),
        .DQ4(DQ[4]),
        .DQ3(DQ[3]),
        .DQ2(DQ[2]),
        .DQ1(DQ[1]),
        .DQ0(DQ[0]),
        .RWDS(DataStrobe),
        .CSNeg(ChipSelect),
        .CK(SerialClk),
        .RESETNeg(reset)
    );

endmodule
