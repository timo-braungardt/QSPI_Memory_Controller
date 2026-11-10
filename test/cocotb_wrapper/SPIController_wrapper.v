`timescale 1ns / 100ps

module SPIController_wrapper #(
    parameter ADDRESS_LENGTH = 24,
    parameter DATA_WIDTH = 8,
    parameter MAX_NUM_BYTES = $clog2(256)
) (
    input clk,
    input reset_neg,
    input go,

    input  [ADDRESS_LENGTH-1:0] i_address,
    input                       i_write_enable,
    input                       i_last_word,
    input  [ MAX_NUM_BYTES-1:0] i_num_bytes,          // 0 based indexing
    input  [    DATA_WIDTH-1:0] i_data_write,
    output [    DATA_WIDTH-1:0] o_data_read,
    output                      o_busy,
    output                      o_next_word,
    output                      o_recieved_next_word,

    // SPI Pins
    output o_bus_clock,
    output o_chip_select_neg,
    output o_reset_neg,

    inout  io_data0_manager_serial_out,
    inout  io_data1_manager_serial_in,
    inout  io_data2,
    inout  io_data3
);

    wire [3:0] spi_i_data, spi_o_data;
    wire spi_data_output_enable, spi_quad_mode_output_enable;

    assign spi_i_data = {io_data3, io_data2, io_data1_manager_serial_in, io_data0_manager_serial_out};

    assign io_data0_manager_serial_out = (spi_data_output_enable) ? spi_o_data[0] : 1'bZ;  // MOSI
    assign io_data1_manager_serial_in = (spi_data_output_enable) ? (spi_quad_mode_output_enable) ? spi_o_data[1] : 1'bZ : 1'bZ;    // MISO
    assign io_data2 = (spi_data_output_enable) ? (spi_quad_mode_output_enable) ? spi_o_data[2] : 1'bZ : 1'bZ;
    assign io_data3 = (spi_data_output_enable) ? (spi_quad_mode_output_enable) ? spi_o_data[3] : 1'bZ : 1'bZ;


    SPIController #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) Controller (
        .clk(clk),
        .reset_neg(reset_neg),
        .go(go),

        .i_address(i_address),
        .i_write_enable(i_write_enable),
        .i_num_bytes(i_num_bytes),
        .i_last_word(i_last_word),
        .i_data_write(i_data_write),
        .o_data_read(o_data_read),
        .o_busy(o_busy),
        .o_next_word(o_next_word),
        .o_recieved_next_word(o_recieved_next_word),

        .o_bus_clock(o_bus_clock),
        .o_chip_select_neg(o_chip_select_neg),
        .i_spi_data(spi_i_data),
        .o_spi_data(spi_o_data),
        .o_spi_data_output_enable(spi_data_output_enable),
        .o_spi_quad_mode_output_enable(spi_quad_mode_output_enable)
    );

endmodule
