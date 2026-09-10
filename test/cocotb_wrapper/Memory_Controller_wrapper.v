`timescale 1ns / 100ps

module Memory_Controller_wrapper #(
    parameter ADDR_WIDTH = 24,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 8
) (
    input clk,
    input reset,

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

    wire [3:0] data;
    wire bus_clock, chip_select_neg;

    MemoryController #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) Controller (
        .clk(clk),
        .reset(reset),

        // SPI Pins
        .o_spi_bus_clock(bus_clock),
        .o_spi_chip_select_neg(chip_select_neg),
        .io_spi_data0_manager_serial_out(data[0]),
        .io_spi_data1_manager_serial_in(data[1]),
        .io_spi_data2(data[2]),
        .io_spi_data3(data[3]),

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


    s25hl512t Memory (
        .SCK(bus_clock),
        .RESETNeg(~reset),
        .CSNeg(chip_select_neg),
        .SI(data[0]),
        .SO(data[1]),
        .WPNeg(data[2]),
        .IO3_RESETNeg(data[3])
    );


endmodule
