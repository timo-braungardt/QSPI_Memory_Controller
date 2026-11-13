`timescale 1ps / 1ps

module Octal_SPI_Controller_wrapper #(
    // Width of data bus in bits
    parameter DATA_WIDTH = 32,
    // Width of address bus in bits
    parameter ADDR_WIDTH = 32,
    // Width of wstrb (width of data bus in words)
    parameter STRB_WIDTH = (DATA_WIDTH / 8),
    // Width of ID signal
    parameter ID_WIDTH = 8,
    // Extra pipeline register on output
    parameter PIPELINE_OUTPUT = 1'b0
);
    reg clk;
    reg go;
    reg reset_neg = 1'b0;
    integer test_number = 0;

    wire [7:0] data;
    wire data_strobe;
    wire [7:0] spi_i_data, spi_o_data;
    wire spi_i_data_strobe, spi_o_data_strobe;
    wire spi_data_output_enable, spi_data_strobe_output_enable;
    wire bus_clock, bus_clock_neg, chip_select_neg;
    wire o_finish,o_recieved_next_word;

    reg [ADDR_WIDTH-1:0] i_address;
    reg i_last_word;
    reg i_write_valid;
    reg [DATA_WIDTH-1:0] i_write_data;
    reg [STRB_WIDTH-1:0] i_write_data_word_mask;
    wire o_write_ready;
    reg [DATA_WIDTH-1:0] o_read_data;
    reg i_write_enable;

    localparam INFINEON_CHIP = 1;
    localparam APMEMORY_CHIP = 2;

    // the #1 delay is necessary for simulation, so that the data changes after the clock edge.
    // in hardware this has to be done with the timing constraints
    assign #1 data = (spi_data_output_enable) ? spi_o_data : 8'bz;
    assign spi_i_data = data;

    assign #1 data_strobe = (spi_data_strobe_output_enable) ? spi_o_data_strobe : 1'bz;
    assign spi_i_data_strobe = data_strobe;

    OctalSPIController #(
        .ADDRESS_LENGTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .CHIP_TYPE(INFINEON_CHIP)
    ) Controller (
        .clk(clk),
        .reset_neg(reset_neg),
        .go(go),

        .i_address(i_address),
        .i_write_enable(i_write_enable),
        .i_last_word(i_last_word),

        .i_write_valid(i_write_valid),
        .i_write_data(i_write_data),
        .i_write_data_word_mask(i_write_data_word_mask),
        .o_write_ready(o_write_ready),
        .o_read_data(o_read_data),
        .o_busy(busy),
        .o_recieved_next_word(o_recieved_next_word),

        .o_bus_clock(bus_clock),
        .o_bus_clock_neg(bus_clock_neg),
        .o_chip_select_neg(chip_select_neg),

        .i_spi_data_strobe(spi_i_data_strobe),
        .o_spi_data_strobe(spi_o_data_strobe),
        .o_spi_data_strobe_output_enable(spi_data_strobe_output_enable),

        .i_spi_data(spi_i_data),
        .o_spi_data(spi_o_data),
        .o_spi_data_output_enable(spi_data_output_enable)
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
