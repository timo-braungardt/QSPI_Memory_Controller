/*
Copyright (c) 2018 Alex Forencich
Copyright (c) 2026 Timo Braungardt (modifications)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/

// Language: Verilog 2001
/*
AXI Interface module

Simple interface which accepts read and write requests.
Can create backpreasure so the SPI can write the data out.
*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

module AXIInterface #(
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
    input wire rst_neg,

    // Control Interface Pins
    input  wire                  i_ready,
    input  wire                  i_busy,
    output wire                  o_last_word,
    output wire                  o_write_enable,
    output wire                  o_start_transaction,
    output wire [ADDR_WIDTH-1:0] o_address,
    output wire [DATA_WIDTH-1:0] o_write_data,
    input  wire [DATA_WIDTH-1:0] i_read_data,

    // AXI Pins
    input  wire [  ID_WIDTH-1:0] s_axi_awid,    // write address channel
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [           7:0] s_axi_awlen,   // length of the transaction in words
    input  wire [           2:0] s_axi_awsize,  // number of bytes per transfer (1, 2, 4, 8, 16, 32, 64, 128)
    input  wire [           1:0] s_axi_awburst,
    input  wire                  s_axi_awlock,
    input  wire [           3:0] s_axi_awcache,
    input  wire [           2:0] s_axi_awprot,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,

    input  wire [DATA_WIDTH-1:0] s_axi_wdata,   // write data channel
    input  wire [STRB_WIDTH-1:0] s_axi_wstrb,   // data strobe for bitmasking
    input  wire                  s_axi_wlast,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,

    output wire [  ID_WIDTH-1:0] s_axi_bid,     // write response channel
    output wire [           1:0] s_axi_bresp,
    output wire                  s_axi_bvalid,
    input  wire                  s_axi_bready,

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

    parameter VALID_ADDR_WIDTH = ADDR_WIDTH - $clog2(STRB_WIDTH);
    parameter SHIFT_ADDR_BY = ADDR_WIDTH - VALID_ADDR_WIDTH;
    parameter WORD_WIDTH = STRB_WIDTH;
    parameter WORD_SIZE = DATA_WIDTH / WORD_WIDTH;

    // bus width assertions
    initial begin
        if (WORD_SIZE * STRB_WIDTH != DATA_WIDTH) begin
            $error("Error: AXI data width not evenly divisble (instance %m)");
            $finish;
        end

        if (2 ** $clog2(WORD_WIDTH) != WORD_WIDTH) begin
            $error("Error: AXI word width must be even power of two (instance %m)");
            $finish;
        end
    end

    // Read FSM
    localparam [0:0] READ_STATE_IDLE = 1'd0;
    localparam [0:0] READ_STATE_BURST = 1'd1;

    reg [0:0] read_state_reg; 
    reg [0:0] read_state_next;

    // Write FSM
    localparam [1:0] WRITE_STATE_IDLE = 2'd0;
    localparam [1:0] WRITE_STATE_BURST = 2'd1;
    localparam [1:0] WRITE_STATE_RESP = 2'd2;

    reg [1:0] write_state_reg;
    reg [1:0] write_state_next;

    reg mem_wr_en;
    reg mem_rd_en;

    reg [ID_WIDTH-1:0] read_id_reg, read_id_next;
    reg [ADDR_WIDTH-1:0] read_addr_reg, read_addr_next;
    reg [7:0] read_count_reg, read_count_next;
    reg [2:0] read_size_reg, read_size_next;
    reg [1:0] read_burst_reg, read_burst_next;
    reg [ID_WIDTH-1:0] write_id_reg, write_id_next;
    reg [ADDR_WIDTH-1:0] write_addr_reg, write_addr_next;
    reg [7:0] write_count_reg, write_count_next;
    reg [2:0] write_size_reg, write_size_next;
    reg [1:0] write_burst_reg, write_burst_next;

    reg s_axi_awready_reg, s_axi_awready_next;
    reg s_axi_wready_reg, s_axi_wready_next;
    reg [ID_WIDTH-1:0] s_axi_bid_reg, s_axi_bid_next;
    reg s_axi_bvalid_reg, s_axi_bvalid_next;
    reg s_axi_arready_reg, s_axi_arready_next;
    reg [ID_WIDTH-1:0] s_axi_rid_reg, s_axi_rid_next;
    reg [DATA_WIDTH-1:0] s_axi_rdata_reg;
    reg s_axi_rlast_reg, s_axi_rlast_next;
    reg s_axi_rvalid_reg, s_axi_rvalid_next;
    reg [ID_WIDTH-1:0] s_axi_rid_pipe_reg;
    reg [DATA_WIDTH-1:0] s_axi_rdata_pipe_reg;
    reg s_axi_rlast_pipe_reg;
    reg s_axi_rvalid_pipe_reg;

    //wire [VALID_ADDR_WIDTH-1:0] s_axi_awaddr_valid = VALID_ADDR_WIDTH'(s_axi_awaddr >> SHIFT_ADDR_BY);    // unused, maybe needed later?
    //wire [VALID_ADDR_WIDTH-1:0] s_axi_araddr_valid = VALID_ADDR_WIDTH'(s_axi_araddr >> SHIFT_ADDR_BY);
    wire [VALID_ADDR_WIDTH-1:0] read_addr_valid = VALID_ADDR_WIDTH'(read_addr_reg >> SHIFT_ADDR_BY);
    wire [VALID_ADDR_WIDTH-1:0] write_addr_valid = VALID_ADDR_WIDTH'(write_addr_reg >> SHIFT_ADDR_BY);

    assign s_axi_awready = s_axi_awready_reg;
    assign s_axi_wready = s_axi_wready_reg;
    assign s_axi_bid = s_axi_bid_reg;
    assign s_axi_bresp = 2'b00;
    assign s_axi_bvalid = s_axi_bvalid_reg;
    assign s_axi_arready = s_axi_arready_reg;
    assign s_axi_rid = PIPELINE_OUTPUT ? s_axi_rid_pipe_reg : s_axi_rid_reg;
    assign s_axi_rdata = PIPELINE_OUTPUT ? s_axi_rdata_pipe_reg : s_axi_rdata_reg;
    assign s_axi_rresp = 2'b00;
    assign s_axi_rlast = s_axi_rlast_reg;//PIPELINE_OUTPUT ? s_axi_rlast_pipe_reg : s_axi_rlast_reg;
    assign s_axi_rvalid = PIPELINE_OUTPUT ? s_axi_rvalid_pipe_reg : s_axi_rvalid_reg;

    assign o_last_word = (s_axi_awvalid | write_state_reg != WRITE_STATE_IDLE) ? s_axi_wlast : s_axi_rlast;
    assign o_write_enable = (s_axi_awvalid | write_state_reg != WRITE_STATE_IDLE);
    assign o_address = (s_axi_awvalid | write_state_reg != WRITE_STATE_IDLE) ? write_addr_next : read_addr_next;
    assign o_write_data = s_axi_wdata;
    assign o_start_transaction = ((s_axi_awready && s_axi_awvalid) | (s_axi_arready && s_axi_arvalid));


    always @* begin
        write_state_next = WRITE_STATE_IDLE;

        mem_wr_en = 1'b0;

        write_id_next = write_id_reg;
        write_addr_next = write_addr_reg;
        write_count_next = write_count_reg;
        write_size_next = write_size_reg;
        write_burst_next = write_burst_reg;

        s_axi_awready_next = 1'b0;
        s_axi_wready_next = 1'b0;
        s_axi_bid_next = s_axi_bid_reg;
        s_axi_bvalid_next = s_axi_bvalid_reg && !s_axi_bready;

        case (write_state_reg)
            WRITE_STATE_IDLE: begin
                s_axi_awready_next = ~i_busy;

                // reviece address etc. of the transaction
                if (s_axi_awready && s_axi_awvalid) begin
                    write_id_next = s_axi_awid;
                    write_addr_next = s_axi_awaddr;
                    write_count_next = s_axi_awlen;
                    write_size_next = s_axi_awsize < 3'($clog2(STRB_WIDTH)) ? s_axi_awsize :
                        3'($clog2(STRB_WIDTH));
                    write_burst_next = s_axi_awburst;

                    s_axi_awready_next = 1'b0;
                    s_axi_wready_next = i_ready;    // ToDo: this could be a problem, when the spi is not ready yet
                    write_state_next = WRITE_STATE_BURST;
                end else begin
                    write_state_next = WRITE_STATE_IDLE;
                end
            end
            WRITE_STATE_BURST: begin
                s_axi_wready_next = i_ready;

                if (s_axi_wready && s_axi_wvalid) begin
                    mem_wr_en = 1'b1;
                    if (write_burst_reg != 2'b00) begin
                        write_addr_next = write_addr_reg + (1 << write_size_reg);
                    end
                    write_count_next = write_count_reg - 1;
                    if (write_count_reg > 0) begin
                        write_state_next = WRITE_STATE_BURST;
                    end else begin
                        s_axi_wready_next = 1'b0;
                        if (s_axi_bready || !s_axi_bvalid) begin
                            s_axi_bid_next = write_id_reg;
                            s_axi_bvalid_next = 1'b1;
                            s_axi_awready_next = 1'b1;
                            write_state_next = WRITE_STATE_IDLE;
                        end else begin
                            write_state_next = WRITE_STATE_RESP;
                        end
                    end
                end else begin
                    write_state_next = WRITE_STATE_BURST;
                end
            end
            WRITE_STATE_RESP: begin
                if (s_axi_bready || !s_axi_bvalid) begin
                    s_axi_bid_next = write_id_reg;
                    s_axi_bvalid_next = 1'b1;
                    s_axi_awready_next = 1'b1;
                    write_state_next = WRITE_STATE_IDLE;
                end else begin
                    write_state_next = WRITE_STATE_RESP;
                end
            end
            default: begin
                write_state_next = WRITE_STATE_IDLE;
            end
        endcase
    end

    always @(posedge clk) begin
        write_state_reg <= write_state_next;

        write_id_reg <= write_id_next;
        write_addr_reg <= write_addr_next;
        write_count_reg <= write_count_next;
        write_size_reg <= write_size_next;
        write_burst_reg <= write_burst_next;

        s_axi_awready_reg <= s_axi_awready_next;
        s_axi_wready_reg <= s_axi_wready_next;
        s_axi_bid_reg <= s_axi_bid_next;
        s_axi_bvalid_reg <= s_axi_bvalid_next;

        if (!rst_neg) begin
            write_state_reg   <= WRITE_STATE_IDLE;
            write_id_reg      <= {ID_WIDTH{1'b0}};
            write_addr_reg    <= {ADDR_WIDTH{1'b0}};
            write_count_reg   <= 8'd0;
            write_size_reg    <= 3'd0;
            write_burst_reg   <= 2'd0;

            s_axi_awready_reg <= 1'b0;
            s_axi_wready_reg  <= 1'b0;
            s_axi_bvalid_reg  <= 1'b0;
            s_axi_bid_reg     <= {ID_WIDTH{1'b0}};
        end
    end

    always @* begin
        read_state_next = READ_STATE_IDLE;

        mem_rd_en = 1'b0;

        s_axi_rid_next = s_axi_rid_reg;
        s_axi_rlast_next = s_axi_rlast_reg;
        s_axi_rvalid_next = s_axi_rvalid_reg && !(s_axi_rready || (PIPELINE_OUTPUT && !s_axi_rvalid_pipe_reg));

        read_id_next = read_id_reg;
        read_addr_next = read_addr_reg;
        read_count_next = read_count_reg;
        read_size_next = read_size_reg;
        read_burst_next = read_burst_reg;

        s_axi_arready_next = 1'b0;

        case (read_state_reg)
            READ_STATE_IDLE: begin
                s_axi_arready_next = ~i_busy;

                if (s_axi_arready && s_axi_arvalid) begin
                    read_id_next = s_axi_arid;
                    read_addr_next = s_axi_araddr;
                    read_count_next = s_axi_arlen;
                    read_size_next = s_axi_arsize < 3'($clog2(STRB_WIDTH)) ? s_axi_arsize :
                        3'($clog2(STRB_WIDTH));
                    read_burst_next = s_axi_arburst;

                    s_axi_arready_next = 1'b0;
                    read_state_next = READ_STATE_BURST;
                end else begin
                    read_state_next = READ_STATE_IDLE;
                end
            end
            READ_STATE_BURST: begin
                s_axi_rlast_next = (read_count_reg == 0);
                if (s_axi_rready & i_ready) begin
                    mem_rd_en = 1'b1;
                    s_axi_rvalid_next = i_ready;
                    s_axi_rid_next = read_id_reg;
                    if (read_burst_reg != 2'b00) begin
                        read_addr_next = read_addr_reg + (1 << read_size_reg);
                    end
                    read_count_next = read_count_reg - 1;
                    if (read_count_reg > 0) begin
                        read_state_next = READ_STATE_BURST;
                    end else begin
                        s_axi_arready_next = 1'b1;
                        read_state_next = READ_STATE_IDLE;
                    end
                end else begin
                    read_state_next = READ_STATE_BURST;
                end
            end
        endcase
    end

    always @(posedge clk) begin
        read_state_reg <= read_state_next;

        read_id_reg <= read_id_next;
        read_addr_reg <= read_addr_next;
        read_count_reg <= read_count_next;
        read_size_reg <= read_size_next;
        read_burst_reg <= read_burst_next;

        s_axi_arready_reg <= s_axi_arready_next;
        s_axi_rid_reg <= s_axi_rid_next;
        s_axi_rlast_reg <= s_axi_rlast_next;
        s_axi_rvalid_reg <= s_axi_rvalid_next;

        if (mem_rd_en) begin
            s_axi_rdata_reg <= i_read_data;
        end

        if (!s_axi_rvalid_pipe_reg || s_axi_rready) begin
            s_axi_rid_pipe_reg <= s_axi_rid_reg;
            s_axi_rdata_pipe_reg <= s_axi_rdata_reg;
            s_axi_rlast_pipe_reg <= s_axi_rlast_reg;
            s_axi_rvalid_pipe_reg <= s_axi_rvalid_reg;
        end

        if (!rst_neg) begin
            read_state_reg        <= READ_STATE_IDLE;
            read_id_reg           <= {ID_WIDTH{1'b0}};
            read_addr_reg         <= {ADDR_WIDTH{1'b0}};
            read_count_reg        <= 8'd0;
            read_size_reg         <= 3'd0;
            read_burst_reg        <= 2'd0;

            s_axi_arready_reg     <= 1'b0;
            s_axi_rvalid_reg      <= 1'b0;
            s_axi_rvalid_pipe_reg <= 1'b0;
            s_axi_rlast_reg       <= 1'b0;
            s_axi_rid_reg         <= {ID_WIDTH{1'b0}};
            s_axi_rid_pipe_reg    <= {ID_WIDTH{1'b0}};
            s_axi_rdata_reg       <= {DATA_WIDTH{1'b0}};
            s_axi_rdata_pipe_reg  <= {DATA_WIDTH{1'b0}};
            s_axi_rlast_pipe_reg  <= 1'b0;
        end
    end


endmodule

`resetall
