`timescale 1ns / 100ps

module AXI_SPI_wrapper #(
    // Width of data bus in bits
    parameter DATA_WIDTH = 32,
    // Width of address bus in bits
    parameter ADDR_WIDTH = 16,
    // Width of wstrb (width of data bus in words)
    parameter STRB_WIDTH = (DATA_WIDTH / 8),
    // Width of ID signal
    parameter ID_WIDTH = 8,
    // Extra pipeline register on output
    parameter PIPELINE_OUTPUT = 1'b0
) (
    input wire clk,
    input wire rst,

    input  wire [  ID_WIDTH-1:0] s_axi_awid,
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [           7:0] s_axi_awlen,
    input  wire [           2:0] s_axi_awsize,
    input  wire [           1:0] s_axi_awburst,
    input  wire                  s_axi_awlock,
    input  wire [           3:0] s_axi_awcache,
    input  wire [           2:0] s_axi_awprot,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,
    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [STRB_WIDTH-1:0] s_axi_wstrb,
    input  wire                  s_axi_wlast,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,
    output wire [  ID_WIDTH-1:0] s_axi_bid,
    output wire [           1:0] s_axi_bresp,
    output wire                  s_axi_bvalid,
    input  wire                  s_axi_bready,
    input  wire [  ID_WIDTH-1:0] s_axi_arid,
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [           7:0] s_axi_arlen,
    input  wire [           2:0] s_axi_arsize,
    input  wire [           1:0] s_axi_arburst,
    input  wire                  s_axi_arlock,
    input  wire [           3:0] s_axi_arcache,
    input  wire [           2:0] s_axi_arprot,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,
    output wire [  ID_WIDTH-1:0] s_axi_rid,
    output wire [DATA_WIDTH-1:0] s_axi_rdata,
    output wire [           1:0] s_axi_rresp,
    output wire                  s_axi_rlast,
    output wire                  s_axi_rvalid,
    input  wire                  s_axi_rready
);

    wire s_spi_clock;
    wire s_spi_chip_select_neg;
    wire s_spi_reset;
    wire s_spi_manager_serial_in;
    wire s_spi_manager_serial_out;


    Basic_AXI_SPI #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .PIPELINE_OUTPUT(PIPELINE_OUTPUT)
    ) Controller (
        .clk(clk),
        .rst(rst),

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

        .s_axi_wdata (s_axi_wdata),
        .s_axi_wstrb (s_axi_wstrb),
        .s_axi_wlast (s_axi_wlast),
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
        .s_axi_rready(s_axi_rready),

        .s_spi_clock(s_spi_clock),
        .s_spi_chip_select_neg(s_spi_chip_select_neg),
        //.s_spi_reset(s_spi_reset),
        .s_spi_manager_serial_in(s_spi_manager_serial_in),
        .s_spi_manager_serial_out(s_spi_manager_serial_out)
    );


    s25hl512t Memory (
        .SI(s_spi_manager_serial_out),
        .SO(s_spi_manager_serial_in),
        .SCK(s_spi_clock),
        .CSNeg(s_spi_chip_select_neg),
        .RESETNeg(~rst)
    );

endmodule
