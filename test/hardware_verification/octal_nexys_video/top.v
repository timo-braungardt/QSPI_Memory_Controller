module top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH = 8,
    parameter MAX_NUM_BYTES = $clog2(256),
    parameter INTERFACE_TYPE = "OSPI"
) (
    input clk,
    input reset,

    // SPI Pins
    output o_spi_bus_clock,
    output o_spi_bus_clock_neg,
    output o_spi_chip_select_neg,
    output o_spi_reset,
    inout io_spi_data_strobe,
    inout [7:0] io_spi_data,

    // FMC Voltage Selection
    output [1:0] set_vadj,
    output vadj_en
);

    localparam volt33 = 2'b11;

    assign set_vadj = volt33;
    assign vadj_en  = 1'b1;

    wire aclk;
    wire aresetn;

    wire [0 : 0] axi_awid;
    wire [31 : 0] axi_awaddr;
    wire [7 : 0] axi_awlen;
    wire [2 : 0] axi_awsize;
    wire [1 : 0] axi_awburst;
    wire axi_awlock;
    wire [3 : 0] axi_awcache;
    wire [2 : 0] axi_awprot;
    wire [3 : 0] axi_awqos;
    wire axi_awvalid;
    wire axi_awready;
    wire [31 : 0] axi_wdata;
    wire [3 : 0] axi_wstrb;
    wire axi_wlast;
    wire axi_wvalid;
    wire axi_wready;
    wire [0 : 0] axi_bid;
    wire [1 : 0] axi_bresp;
    wire axi_bvalid;
    wire axi_bready;
    wire [0 : 0] axi_arid;
    wire [31 : 0] axi_araddr;
    wire [7 : 0] axi_arlen;
    wire [2 : 0] axi_arsize;
    wire [1 : 0] axi_arburst;
    wire axi_arlock;
    wire [3 : 0] axi_arcache;
    wire [2 : 0] axi_arprot;
    wire [3 : 0] axi_arqos;
    wire axi_arvalid;
    wire axi_arready;
    wire [0 : 0] axi_rid;
    wire [31 : 0] axi_rdata;
    wire [1 : 0] axi_rresp;
    wire axi_rlast;
    wire axi_rvalid;
    wire axi_rready;


    MemoryController #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .INTERFACE_TYPE("OSPI")
    ) Controller (
        .clk  (clk),
        .reset(reset),

        // SPI Pins
        .o_spi_bus_clock(bus_clock),
        .o_spi_bus_clock_neg(bus_clock_neg),
        .o_spi_chip_select_neg(chip_select_neg),
        .io_spi_data_strobe(data_strobe),
        .io_spi_data0_manager_serial_out(io_spi_data[0]),
        .io_spi_data1_manager_serial_in(io_spi_data[1]),
        .io_spi_data2(io_spi_data[2]),
        .io_spi_data3(io_spi_data[3]),
        .io_spi_data4(io_spi_data[4]),
        .io_spi_data5(io_spi_data[5]),
        .io_spi_data6(io_spi_data[6]),
        .io_spi_data7(io_spi_data[7]),

        // AXI Pins
        .s_axi_awid(axi_awid),
        .s_axi_awaddr(axi_awaddr),
        .s_axi_awlen(axi_awlen),
        .s_axi_awsize(axi_awsize),
        .s_axi_awburst(axi_awburst),
        .s_axi_awlock(axi_awlock),
        .s_axi_awcache(axi_awcache),
        .s_axi_awprot(axi_awprot),
        .s_axi_awvalid(axi_awvalid),
        .s_axi_awready(axi_awready),
        .s_axi_wdata(axi_wdata),
        .s_axi_wstrb(axi_wstrb),
        .s_axi_wlast(axi_wlast),
        .s_axi_wvalid(axi_wvalid),
        .s_axi_wready(axi_wready),
        .s_axi_bid(axi_bid),
        .s_axi_bresp(axi_bresp),
        .s_axi_bvalid(axi_bvalid),
        .s_axi_bready(axi_bready),
        .s_axi_arid(axi_arid),
        .s_axi_araddr(axi_araddr),
        .s_axi_arlen(axi_arlen),
        .s_axi_arsize(axi_arsize),
        .s_axi_arburst(axi_arburst),
        .s_axi_arlock(axi_arlock),
        .s_axi_arcache(axi_arcache),
        .s_axi_arprot(axi_arprot),
        .s_axi_arvalid(axi_arvalid),
        .s_axi_arready(axi_arready),
        .s_axi_rid(axi_rid),
        .s_axi_rdata(axi_rdata),
        .s_axi_rresp(axi_rresp),
        .s_axi_rlast(axi_rlast),
        .s_axi_rvalid(axi_rvalid),
        .s_axi_rready(axi_rready)
    );


    jtag_axi_0 JTAG_AXI_Module (
        .aclk(clk),
        .aresetn(reset),
        .m_axi_awid(axi_awid),
        .m_axi_awaddr(axi_awaddr),
        .m_axi_awlen(axi_awlen),
        .m_axi_awsize(axi_awsize),
        .m_axi_awburst(axi_awburst),
        .m_axi_awlock(axi_awlock),
        .m_axi_awcache(axi_awcache),
        .m_axi_awprot(axi_awprot),
        .m_axi_awqos(axi_awqos),
        .m_axi_awvalid(axi_awvalid),
        .m_axi_awready(axi_awready),
        .m_axi_wdata(axi_wdata),
        .m_axi_wstrb(axi_wstrb),
        .m_axi_wlast(axi_wlast),
        .m_axi_wvalid(axi_wvalid),
        .m_axi_wready(axi_wready),
        .m_axi_bid(axi_bid),
        .m_axi_bresp(axi_bresp),
        .m_axi_bvalid(axi_bvalid),
        .m_axi_bready(axi_bready),
        .m_axi_arid(axi_arid),
        .m_axi_araddr(axi_araddr),
        .m_axi_arlen(axi_arlen),
        .m_axi_arsize(axi_arsize),
        .m_axi_arburst(axi_arburst),
        .m_axi_arlock(axi_arlock),
        .m_axi_arcache(axi_arcache),
        .m_axi_arprot(axi_arprot),
        .m_axi_arqos(axi_arqos),
        .m_axi_arvalid(axi_arvalid),
        .m_axi_arready(axi_arvalid),
        .m_axi_rid(axi_rid),
        .m_axi_rdata(axi_rdata),
        .m_axi_rresp(axi_rresp),
        .m_axi_rlast(axi_rlast),
        .m_axi_rvalid(axi_rvalid),
        .m_axi_rready(axi_rready)
    );

endmodule
