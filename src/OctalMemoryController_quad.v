`timescale 1ns / 100ps
/*
Memory Controller

Module to wrap all components together and connect the AXI to the SPI Controller.
*/

module OctalMemoryController_quad #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH = 8,
    parameter CHIP_TYPE = -1    // 1 is Infineon, 2 is APMemory
) (
    input clk,
    input reset,

    // SPI Pins
    output o_spi_bus_clock,
    output o_spi_bus_clock_neg,
    output [3:0] o_spi_chip_select_neg,
    output o_spi_reset_neg,
    
    input [3:0] i_data_strobe,
    output [3:0] o_data_strobe,
    output [3:0] o_data_strobe_output_enable,     // 0 input, 1 output

    input  [(8*4)-1:0] i_data,
    output  [(8*4)-1:0] o_data,
    output [3:0] o_data_output_enable,   // 0 input, 1 output

    // AXI Pins
    input  wire [  ID_WIDTH-1:0] s_axi_awid,     // write address channel
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [           7:0] s_axi_awlen,
    input  wire [           2:0] s_axi_awsize,
    input  wire [           1:0] s_axi_awburst,
    input  wire                  s_axi_awlock,
    input  wire [           3:0] s_axi_awcache,
    input  wire [           2:0] s_axi_awprot,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,

    input  wire [DATA_WIDTH-1:0] s_axi_wdata,   // write data channel
    input  wire [STRB_WIDTH-1:0] s_axi_wstrb,
    input  wire                  s_axi_wlast,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,

    output wire [ID_WIDTH-1:0] s_axi_bid,     // write response channel
    output wire [         1:0] s_axi_bresp,
    output wire                s_axi_bvalid,
    input  wire                s_axi_bready,

    input  wire [  ID_WIDTH-1:0] s_axi_arid,     // read address channel
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [           7:0] s_axi_arlen,
    input  wire [           2:0] s_axi_arsize,
    input  wire [           1:0] s_axi_arburst,
    input  wire                  s_axi_arlock,
    input  wire [           3:0] s_axi_arcache,
    input  wire [           2:0] s_axi_arprot,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,

    output wire [  ID_WIDTH-1:0] s_axi_rid,     // read data channel
    output wire [DATA_WIDTH-1:0] s_axi_rdata,
    output wire [           1:0] s_axi_rresp,
    output wire                  s_axi_rlast,
    output wire                  s_axi_rvalid,
    input  wire                  s_axi_rready
);

    wire spi_busy;
    wire spi_next_word;
    wire spi_recieved_next_word;
    wire [ADDR_WIDTH-1:0] axi_address;
    wire [DATA_WIDTH-1:0] axi_data_read;
    wire [DATA_WIDTH-1:0] axi_data_write;
    wire axi_write_enable;
    wire axi_last_word;
    wire axi_start_transaction;


    OSPIController_quad #(
        .ADDRESS_LENGTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .CHIP_TYPE(CHIP_TYPE)
    ) SPI_Controller (
        .clk(clk),
        .reset_neg(!reset),
        .go(axi_start_transaction),

        .i_address(axi_address),
        .i_write_enable(axi_write_enable),
        .i_last_word(axi_last_word),
        .i_data_write(axi_data_write),
        .i_data_word_mask(~s_axi_wstrb), // the axi write strobe signals are inverted to the octal-spi signals
        .o_data_read(axi_data_read),
        .o_busy(spi_busy),
        .o_next_word(spi_next_word),
        .o_recieved_next_word(spi_recieved_next_word),

        // SPI Pins
        .o_bus_clock(o_spi_bus_clock),
        .o_bus_clock_neg(o_spi_bus_clock_neg),
        .o_chip_select_neg(o_spi_chip_select_neg),
        .o_reset_neg(o_spi_reset_neg),
        .i_data_strobe(i_data_strobe),
        .o_data_strobe(o_data_strobe),
        .o_data_strobe_output_enable(o_data_strobe_output_enable),
        .i_data(i_data),
        .o_data(o_data),
        .o_data_output_enable(o_data_output_enable)
    );


    AXIInterface #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH  (ID_WIDTH),
        .STRB_WIDTH(STRB_WIDTH)
    ) AXI_Interface (
        .clk(clk),
        .rst_neg(!reset),

        // Control Interface Pins
        .i_write_word_ready(spi_next_word),
        .i_read_word_ready(spi_recieved_next_word),
        .i_busy(spi_busy),
        .o_last_word(axi_last_word),
        .o_write_enable(axi_write_enable),
        .o_start_transaction(axi_start_transaction),
        .o_address(axi_address),
        .o_write_data(axi_data_write),
        .i_read_data(axi_data_read),

        // AXI Pins
        .s_axi_awid(s_axi_awid),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(s_axi_awlen),
        .s_axi_awsize(s_axi_awsize),
        .s_axi_awburst(s_axi_awburst),
        .s_axi_awlock(s_axi_awlock),
        .s_axi_awcache(s_axi_awcache),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wlast(s_axi_wlast),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bid(s_axi_bid),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_arid(s_axi_arid),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(s_axi_arlen),
        .s_axi_arsize(s_axi_arsize),
        .s_axi_arburst(s_axi_arburst),
        .s_axi_arlock(s_axi_arlock),
        .s_axi_arcache(s_axi_arcache),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rid(s_axi_rid),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready)
    );


endmodule
