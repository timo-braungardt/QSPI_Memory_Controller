`timescale 1ns / 100ps

module Quad_SPI_Controller_model_wrapper #(
    parameter ADDRESS_LENGTH = 24,
    parameter DATA_WIDTH = 8
);

    reg clk;
    reg go;
    reg reset_neg = 1'b0;
    wire busy;

    reg [ADDRESS_LENGTH-1:0] i_address;
    reg [DATA_WIDTH-1:0] i_data_write;
    reg [DATA_WIDTH-1:0] o_data_read;
    reg i_write_enable;
    reg i_last_word;
    integer num_bytes;

    wire [3:0] data;
    wire [3:0] spi_i_data, spi_o_data;
    wire spi_data_output_enable, spi_quad_mode_output_enable;
    wire bus_clock, chip_select_neg;

    assign spi_i_data = data;

    assign data[0] = (spi_data_output_enable) ? spi_o_data[0] : 1'bZ;   // MOSI
    assign data[1] = (spi_data_output_enable) ? (spi_quad_mode_output_enable) ? spi_o_data[1] : 1'bZ : 1'bZ;    // MISO
    assign data[2] = (spi_data_output_enable) ? (spi_quad_mode_output_enable) ? spi_o_data[2] : 1'bZ : 1'bZ;
    assign data[3] = (spi_data_output_enable) ? (spi_quad_mode_output_enable) ? spi_o_data[3] : 1'bZ : 1'bZ;


    QuadSPIController #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) Controller (
        .clk(clk),
        .reset_neg(reset_neg),
        .go(go),

        .i_address(i_address),
        .i_write_enable(i_write_enable),
        .i_num_bytes(num_bytes),
        .i_last_word(i_last_word),
        .i_data_write(i_data_write),
        .o_data_read(o_data_read),
        .o_busy(busy),
        .o_next_word(o_next_word),

        .o_bus_clock(bus_clock),
        .o_chip_select_neg(chip_select_neg),
        .i_spi_data(spi_i_data),
        .o_spi_data(spi_o_data),
        .o_spi_data_output_enable(spi_data_output_enable),
        .o_spi_quad_mode_output_enable(spi_quad_mode_output_enable)
    );


    s25hl512t Memory (
        .SCK(bus_clock),
        .RESETNeg(reset_neg),
        .CSNeg(chip_select_neg),
        .SI(data[0]),
        .SO(data[1]),
        .WPNeg(data[2]),
        .IO3_RESETNeg(data[3])
    );


endmodule
