`timescale 1ns/100ps

module HyperRAM_wrapper;
    reg clk = 0;
    reg go  = 0;

    wire SerialClk;
    wire ChipSelect;
    wire [7:0] QD;
    wire DataStrobe;


    Hyperbus controller(
        .clk(clk),
        .go(go),
        .o_SpiClk(SerialClk),
        .o_SpiClk_neg(SerialClk_neg),
        .o_ChipSelect_neg(ChipSelect),
        .io_QD(QD),
        .io_Data_Strobe(DataStrobe)
        );


    s27kl0641 #(.TimingModel("S27KL0641DABHI000"))
    RAM (
        .DQ7(QD[7]),
        .DQ6(QD[6]),
        .DQ5(QD[5]),
        .DQ4(QD[4]),
        .DQ3(QD[3]),
        .DQ2(QD[2]),
        .DQ1(QD[1]),
        .DQ0(QD[0]),
        .RWDS(DataStrobe),
        .CSNeg(ChipSelect),
        .CK(SerialClk),
        .RESETNeg(1'b1)
    );

endmodule
