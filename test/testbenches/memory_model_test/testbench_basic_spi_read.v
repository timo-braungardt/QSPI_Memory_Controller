// path to the infineon memory model
`include "../../memory_models/infineon-s25hl512t-qspi-verilog-model-simulationmodels-en/s25hl512tRel/src/s25hl512t.sv"
`include "../../../src/BasicSPI.v"

module testbench_basic_spi_read;
    parameter half_period = 10ns;
    parameter period = half_period * 2;
    parameter spi_period = period * 2;

    reg clk, go;
    wire SerialIn, SerialOut, SerialClk, ChipSelect;

    BasicSPI DUT(
        .clk(clk),
        .go(go),
        .o_SpiClk(SerialClk),
        .o_ChipSelect_neg(ChipSelect),
        .io_ManagerSerialIn(SerialOut),
        .io_ManagerSerialOut(SerialIn)
        );

    s25hl512t Memory ( 
        .SI(SerialIn),
        .SO(SerialOut),
        .SCK(SerialClk),
        .CSNeg(ChipSelect),
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
        #(spi_period * 32) 
        if(DUT.io_ManagerSerialIn !== 1'bZ) $fatal(1,"Data is wrong! Expected %h got %h", 1'bZ, DUT.io_ManagerSerialIn);
        #(spi_period * 1) 
        if(DUT.io_ManagerSerialIn !== 1'b1) $fatal(1,"Data is wrong! Expected %h got %h", 1'b1, DUT.io_ManagerSerialIn);
        #(spi_period * 32) 
        if(DUT.io_ManagerSerialIn !== 1'bZ) $fatal(1,"Data is wrong! Expected %h got %h", 1'bZ, DUT.io_ManagerSerialIn);

        $display("OK");
        $finish;
    end
endmodule
