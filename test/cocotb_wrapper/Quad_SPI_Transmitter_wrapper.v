`timescale 1ns / 100ps

module Quad_SPI_Transmitter_wrapper #(
    parameter ADDRESS_LENGTH = 24,
    parameter DATA_WIDTH = 8,
    parameter MAX_NUM_BYTES = $clog2(256)
) (
    input clk,
    input reset_neg,
    input start_transmission,

    input  [ADDRESS_LENGTH-1:0] i_address,
    input  [               7:0] i_opcode,
    input                       i_config_read_data,
    input                       i_config_write_data,
    input                       i_config_write_address,
    input  [               2:0] i_config_quad_mode,
    input                       i_last_byte,
    input  [               4:0] i_config_dummy_cycles,
    input  [               7:0] i_data_write,
    output [               7:0] o_data_read,
    output                      o_finish,
    output                      o_need_next_byte,
    output                      o_recieved_next_byte,

    // SPI Pins
    output o_bus_clock,
    output reg o_chip_select_neg,

    inout io_data0_manager_serial_out,
    inout io_data1_manager_serial_in,
    inout io_data2,
    inout io_data3
);

    wire [3:0] spi_i_data, spi_o_data;
    wire spi_data_output_enable, spi_quad_mode_output_enable;

    assign spi_i_data = {
        io_data3, io_data2, io_data1_manager_serial_in, io_data0_manager_serial_out
    };

    assign io_data0_manager_serial_out = (spi_data_output_enable) ? spi_o_data[0] : 1'bZ;  // MOSI
    assign io_data1_manager_serial_in = (spi_data_output_enable) ? (spi_quad_mode_output_enable) ? spi_o_data[1] : 1'bZ : 1'bZ;    // MISO
    assign io_data2 = (spi_data_output_enable) ? (spi_quad_mode_output_enable) ? spi_o_data[2] : 1'bZ : 1'bZ;
    assign io_data3 = (spi_data_output_enable) ? (spi_quad_mode_output_enable) ? spi_o_data[3] : 1'bZ : 1'bZ;


    QuadSPITransmitter #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH)
    ) Controller (
        .clk(clk),
        .reset_neg(reset_neg),
        .start_transmission(start_transmission),

        .i_address(i_address),
        .i_opcode(i_opcode),
        .i_config_read_data(i_config_read_data),
        .i_config_write_data(i_config_write_data),
        .i_config_write_address(i_config_write_address),
        .i_config_quad_mode(i_config_quad_mode),
        .i_last_byte(i_last_byte),
        .i_config_dummy_cycles(i_config_dummy_cycles),    // ToDo: depending on the opcode, we need dummy cycles or not (issue #10)
        .i_data_write(i_data_write),
        .o_data_read(o_data_read),
        .o_finish(o_finish),
        .o_need_next_byte(o_need_next_byte),
        .o_recieved_next_byte(o_recieved_next_byte),

        // SPI Pins
        .o_bus_clock(o_bus_clock),
        .o_chip_select_neg(o_chip_select_neg),

        .i_spi_data(spi_i_data),
        .o_spi_data(spi_o_data),
        .o_spi_data_output_enable(spi_data_output_enable),
        .o_spi_quad_mode_output_enable(spi_quad_mode_output_enable)
    );

endmodule
