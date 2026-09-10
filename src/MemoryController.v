`timescale 1ns / 100ps
/*
Memory Controller

Module to wrap all components together and connect the AXI to the SPI Controller.
*/

module MemoryController #(
    parameter ADDR_WIDTH = 24,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 8

) (
    input clk,
    input reset,

    // SPI Pins
    output o_spi_bus_clock,
    output o_spi_chip_select_neg,
    output o_spi_reset,
    inout  io_spi_data0_manager_serial_out,
    inout  io_spi_data1_manager_serial_in,
    inout  io_spi_data2,
    inout  io_spi_data3,

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
    wire [ADDR_WIDTH-1:0]  axi_address;
    wire [DATA_WIDTH-1:0] axi_data_read;
    wire [DATA_WIDTH-1:0] axi_data_write;
    wire [2:0] axi_write_width;
    reg  [DATA_WIDTH/8-1:0] spi_number_bytes;
    wire axi_write_enable;
    wire axi_last_word;
    wire axi_start_transaction;

    /*
    assign spi_number_bytes =   (DATA_WIDTH/8)'((s_axi_awsize == 3'd0) ?  0 :
                                                (s_axi_awsize == 3'd1) ?  1 :
                                                (s_axi_awsize == 3'd2) ?  3 :
                                                (s_axi_awsize == 3'd3) ?  7 :
                                                (s_axi_awsize == 3'd4) ? 15 :
                                                (s_axi_awsize == 3'd5) ? 31 :
                                                (s_axi_awsize == 3'd6) ? 63 : 127);
                                                */
    // ToDo: arbitrary byte masking is not possible (yet?) with flash (issue #10)
    // ToDo: make it for arbitrary data width (issue #10)
    always @(*) begin
        if (axi_write_enable) begin
            spi_number_bytes =   (s_axi_wstrb == 4'b0001) ? 0 :
                                (s_axi_wstrb == 4'b0011) ? 1 :
                                (s_axi_wstrb == 4'b0111) ? 2 : 3;
        end 
        else begin
            spi_number_bytes =  (s_axi_arsize == 3'b000) ? 0 :
                                (s_axi_arsize == 3'b001) ? 1 :
                                (s_axi_arsize == 3'b010) ? 3 : 7;
        end
    end


    SPIController #(
        .ADDRESS_LENGTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) SPI_Controller (
        .clk(clk),
        .reset_neg(!reset),
        .go(axi_start_transaction),

        .i_address(axi_address),
        .i_write_enable(axi_write_enable),
        .i_last_word(axi_last_word),
        .i_num_bytes(spi_number_bytes),
        .i_data_write(axi_data_write),
        .o_data_read(axi_data_read),
        .o_busy(spi_busy),
        .o_next_word(spi_next_word),

        // SPI Pins
        .o_bus_clock(o_spi_bus_clock),
        .o_chip_select_neg(o_spi_chip_select_neg),
        .o_reset(o_spi_reset),
        .io_data0_manager_serial_out(io_spi_data0_manager_serial_out),
        .io_data1_manager_serial_in(io_spi_data1_manager_serial_in),
        .io_data2(io_spi_data2),
        .io_data3(io_spi_data3)
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
        .i_ready(spi_next_word),
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
