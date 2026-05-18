// path to the infineon memory model
`include "../../memory_models/infineon-s25hl512t-qspi-verilog-model-simulationmodels-en/s25hl512tRel/src/s25hl512t.sv"
`include "../../../src/basic_spi.v"

module testbench_basic_spi_read;
    parameter half_period = 10ns;
    parameter period = half_period * 2;

    reg clk, go;
    wire SerialIn, SerialOut, SerialClk, ChipSelect;

    BasicSPI DUT(
        .clk(clk),
        .go(go),
        .o_SpiClk(SerialClk),
        .o_ChipSelect(ChipSelect),
        .io_ManagerSerialIn(SerialOut),
        .io_ManagerSerialOut(SerialIn)
        );

    s25hl512t Memory ( 
        .SI(SerialIn),
        .SO(SerialOut),
        .SCK(SerialClk),
        .CSNeg(~ChipSelect),
        .RESETNeg(1'b1)
        );
    
    initial begin
        clk <= 1'b0;
        forever #half_period clk <= ~clk;
    end

    initial begin
        go <= 1'b0;
        DUT.opcode <= 8'h03;
        DUT.address <= 24'h010203;
        #500us;
        go <= 1'b1;
        #(period * 100) $finish;
    end
endmodule