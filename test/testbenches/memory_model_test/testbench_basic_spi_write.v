// path to the infineon memory model
`include "../../memory_models/infineon-s25hl512t-qspi-verilog-model-simulationmodels-en/s25hl512tRel/src/s25hl512t.sv"
`include "../../../src/BasicSPI.v"

module testbench_basic_spi_write;
    parameter half_period = 10ns;
    parameter period = half_period * 2;
    parameter spi_period = period * 6;

    reg clk, go;
    wire SerialIn, SerialOut, SerialClk, ChipSelect;

    BasicSPI DUT (
        .clk(clk),
        .go(go),
        .o_bus_clock(SerialClk),
        .o_chip_select_neg(ChipSelect),
        .io_manager_serial_in(SerialOut),
        .io_manager_serial_out(SerialIn)
    );

    wire WriteEnableNeg_io;
    assign WriteEnableNeg_io = (1) ? 1'b1 : 1'bZ;
    assign io3_ResetNeg_io   = 1'bZ;

    s25hl512t Memory (
        .SI(SerialIn),
        .SO(SerialOut),
        .SCK(SerialClk),
        .CSNeg(ChipSelect),
        .WPNeg(WriteEnableNeg_io),
        .RESETNeg(1'b1),
        .IO3_RESETNeg(io3_ResetNeg_io)
    );

    initial begin
        clk <= 1'b0;
        forever #half_period clk <= ~clk;
    end

    parameter OPCODE_WRITE_ENABLE = 8'h06;
    parameter OPCODE_WRITE_DISABLE = 8'h04;
    parameter OPCODE_PROGRAM = 8'h02;
    parameter OPCODE_ERASE_4KB = 8'h20;
    parameter OPCODE_ERASE_256B = 8'hD8;
    parameter OPCODE_READ = 8'h03;

    initial begin
        go <= 1'b0;
        #500us;

        DUT.opcode        = OPCODE_WRITE_ENABLE;
        DUT.address       = 24'h000000;
        DUT.write_address = 1'b0;
        DUT.write_data    = 1'b0;
        DUT.read_data     = 1'b0;
        go                = 1'b1;
        #(spi_period * 1) go <= 1'b0;
        #(spi_period * 9) DUT.opcode = OPCODE_ERASE_4KB;
        DUT.address       = 24'h000000;
        DUT.write_address = 1'b1;
        DUT.write_data    = 1'b0;
        DUT.read_data     = 1'b0;
        go                = 1'b1;
        #(spi_period * 1) go <= 1'b0;
        #(spi_period * 31)

        #42ms  // typical sector erase time

        DUT.opcode = OPCODE_READ;
        DUT.address       = 24'h000000;
        DUT.write_address = 1'b1;
        DUT.write_data    = 1'b0;
        DUT.read_data     = 1'b1;
        DUT.num_bits      = 16;
        go                = 1'b1;
        #(spi_period * 1) go <= 1'b0;
        #(spi_period * 32)
        #(spi_period * 16)

        if (DUT.buffer[0] !== 8'hff)
            $fatal(1, "Data is wrong! Expected %h got %h", 8'hff, DUT.buffer[0]);
        if (DUT.buffer[1] !== 8'hff)
            $fatal(1, "Data is wrong! Expected %h got %h", 8'hff, DUT.buffer[1]);

        DUT.opcode        = OPCODE_WRITE_ENABLE;
        DUT.address       = 24'h000000;
        DUT.write_address = 1'b0;
        DUT.write_data    = 1'b0;
        DUT.read_data     = 1'b0;
        go                = 1'b1;
        #(spi_period * 1) go <= 1'b0;
        #(spi_period * 9) DUT.opcode = OPCODE_PROGRAM;
        DUT.buffer        = '{default: '0};
        DUT.address       = 24'h000000;
        DUT.write_address = 1'b1;
        DUT.write_data    = 1'b1;
        DUT.read_data     = 1'b0;
        DUT.num_bits      = 16;
        go                = 1'b1;
        #(spi_period * 1) go <= 1'b0;
        #(spi_period * 31)
        // write data
        #(spi_period * DUT.num_bits)

        #1700us  // t Page Program Operation

        DUT.opcode = OPCODE_WRITE_DISABLE;
        DUT.address       = 24'h000000;
        DUT.write_address = 1'b0;
        DUT.write_data    = 1'b0;
        DUT.read_data     = 1'b0;
        go                = 1'b1;
        #(spi_period * 1) go <= 1'b0;
        #(spi_period * 9) DUT.opcode = OPCODE_READ;
        DUT.address       = 24'h000000;
        DUT.write_address = 1'b1;
        DUT.write_data    = 1'b0;
        DUT.read_data     = 1'b1;
        DUT.num_bits      = 128;
        go                = 1'b1;
        #(spi_period * 1) go <= 1'b0;
        #(spi_period * 32)
        #(spi_period * 16)

        #(spi_period * 128)

        if (DUT.buffer[0] !== 8'h00)
            $fatal(1, "Data is wrong! Expected %h got %h", 8'h00, DUT.buffer[0]);
        if (DUT.buffer[1] !== 8'h00)
            $fatal(1, "Data is wrong! Expected %h got %h", 8'h00, DUT.buffer[1]);
        if (DUT.buffer[2] !== 8'hff)
            $fatal(1, "Data is wrong! Expected %h got %h", 8'hff, DUT.buffer[2]);

        $display("OK");
        $finish;
    end
endmodule
