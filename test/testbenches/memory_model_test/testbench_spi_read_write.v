// path to the infineon memory model
`include "../../memory_models/infineon-s25hl512t-qspi-verilog-model-simulationmodels-en/s25hl512tRel/src/s25hl512t.sv"

module testbench_spi_read_write;
    parameter half_period = 10ns;
    parameter period = half_period * 2;

    reg clk;
    wire SerialIn_io, SerialOut_io, WriteEnableNeg_io, io3_ResetNeg_io, clk_io;
    reg  SerialIn,    SerialOut,    WriteEnableNeg,    io3_ResetNeg,
         ChipSelectNeg, ResetNeg;
    reg  enSerialIn, enClk;

    s25hl512t DUT ( .SI(SerialIn_io),
                    .SO(SerialOut_io),
                    .SCK(clk_io),
                    .CSNeg(ChipSelectNeg),
                    .WPNeg(WriteEnableNeg_io),
                    .RESETNeg(ResetNeg),
                    .IO3_RESETNeg(io3_ResetNeg_io)
                    );
    
    initial begin
        clk <= 1'b0;
        forever #half_period clk <= ~clk;
    end

    initial begin
        ResetNeg        <= 1'b1;
        ChipSelectNeg   <= 1'b1;
        WriteEnableNeg  <= 1'b1;
        enSerialIn      <= 1'b0;
        enClk           <= 1'b0;
        SerialIn <= 1'b0;
        #500us; // t power up

        // select chip and enable serial in
        #half_period;
        ChipSelectNeg   <= 1'b0;
        #half_period;
        enSerialIn      <= 1'b1;
        #half_period;   // t chip select
        enClk <= 1'b1;

        // sending the opcode 03
        #(period * 5) //6*5;
        SerialIn <= 1'b1;
        #(period * 2) //6*2;
        SerialIn <= 1'b0;

        // sending the address 0
        #(period * 25) // 24 bits (??);
        enSerialIn      <= 1'b0;

        // shift the data out
        #(period * 100) //6*24;

        $display("OK");
        $finish;
    end 

    assign clk_io =             (enClk) ? clk : 1'b0;
    assign SerialIn_io =        (enSerialIn) ? SerialIn          : 1'bZ;
    assign SerialOut_io =       (0) ? SerialOut         : 1'bZ;
    assign WriteEnableNeg_io =  (1) ? WriteEnableNeg    : 1'bZ;
    assign io3_ResetNeg_io =    (0) ? io3_ResetNeg      : 1'bZ;

endmodule