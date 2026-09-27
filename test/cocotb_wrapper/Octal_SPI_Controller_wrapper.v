`timescale 1ps / 1ps

module Octal_SPI_Controller_wrapper #(
    // Width of data bus in bits
    parameter DATA_WIDTH = 8,
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

    wire [7:0] data;
    wire manager_serial_out, manager_serial_in, bus_clock, bus_clock_neg, chip_select_neg, data_strobe;
    wire i_config_read_data, i_config_write_data,i_config_write_address,o_finish,o_need_next_byte,o_recieved_next_byte;

    reg [ADDR_WIDTH-1:0] i_address;
    reg [DATA_WIDTH-1:0] i_data_write;
    reg [DATA_WIDTH-1:0] o_data_read;
    reg i_write_enable;
    reg i_last_word;

    OSPIController #(
        .ADDRESS_LENGTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) Controller (
        .clk(clk),
        .reset_neg(reset_neg),
        .go(go),

        .i_address(i_address),
        .i_write_enable(i_write_enable),
        .i_num_bytes(1),
        .i_last_word(1),
        .i_data_write(i_data_write),
        .o_data_read(o_data_read),
        .o_busy(busy),
        .o_next_word(o_next_word),

        .o_bus_clock(bus_clock),
        .o_bus_clock_neg(bus_clock_neg),
        .o_chip_select_neg(chip_select_neg),
        .io_data_strobe(data_strobe),
        .io_data0_manager_serial_out(data[0]),
        .io_data1_manager_serial_in(data[1]),
        .io_data2(data[2]),
        .io_data3(data[3]),
        .io_data4(data[4]),
        .io_data5(data[5]),
        .io_data6(data[6]),
        .io_data7(data[7])
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
