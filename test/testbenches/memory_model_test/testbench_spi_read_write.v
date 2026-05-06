// path to the infineon memory model
`include "../../memory_models/infineon-s25hl512t-qspi-verilog-model-simulationmodels-en/s25hl512tRel/src/s25hl512t.sv"

module testbench_spi_read_write;

    wire SlaveIn, SlaveOut, SlaveCLK, ChipSelectNeg, WriteEnableNeg, ResetNeg, io3_ResetNeg;

    s25hl512t DUT ( .SI(SlaveIn),
                    .SO(SlaveOut),
                    .SCK(SlaveCLK),
                    .CSNeg(ChipSelectNeg),
                    .WPNeg(WriteEnableNeg),
                    .RESETNeg(ResetNeg),
                    .IO3_RESETNeg(io3_ResetNeg)
                    );
    


endmodule