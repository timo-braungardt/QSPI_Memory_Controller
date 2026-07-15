`timescale 1ns / 100ps

module Hyperbus (
    input clk,
    input go,

    // Hyperbus Pins
    output             o_bus_clock,
    output             o_bus_clock_neg,
    output reg         o_chip_select_neg,
    output             o_reset,
    inout      [7 : 0] io_data,
    inout              io_data_strobe
);

    localparam BUS_WIDTH = 8;
    localparam BUFFER_SIZE = 16;

    // Pin tristate stuff
    wire en_bus_clock;
    reg en_data_out;
    reg [BUS_WIDTH-1 : 0] data_out;
    wire [BUS_WIDTH-1 : 0] data_in;
    wire en_data_strobe;
    reg data_strobe_out;
    wire data_strobe_in;
    reg has_latency;

    genvar x;
    generate
        for (x = 0; x < BUS_WIDTH; x = x + 1) begin
            assign io_data[x] = (en_data_out) ? data_out[x] : 1'bZ;
            assign data_in[x] = io_data[x];
        end
    endgenerate

    // Logic stuff
    reg         is_read;
    reg         is_register_space;
    reg         is_linear_burst;
    reg  [31:0] address;
    wire [47:0] command_address;

    assign command_address[47]    = is_read;
    assign command_address[46]    = is_register_space;
    assign command_address[45]    = is_linear_burst;
    assign command_address[44:16] = address[31:3];
    assign command_address[15:3]  = 13'd0;
    assign command_address[2:0]   = address[2:0];

    integer       num_bits;
    integer       state;

    integer       count = 0;
    integer       clock_count = 0;
    reg           bus_clock = 0;
    wire          clock_tick;
    integer       buffer_count = 0;

    reg     [7:0] buffer           [0:BUFFER_SIZE -1];

    // states
    localparam integer idle = 0;
    localparam integer cl_low = 5;
    localparam integer cl_high = 8;
    localparam integer send_command_address = 11;
    localparam integer wait_latency = 9;
    localparam integer send_data = 3;
    localparam integer send_data_setup = 12;
    localparam integer recieve_data = 4;

    // constants
    localparam integer TIMER_COUNT = 15;
    localparam integer OPCODE_LENGTH = 8;
    localparam integer ADDRESS_LENGTH = 6;
    localparam integer LATENCY_CYCLES = 6 * 2;  // times two because of the two clock edges

    assign en_data_strobe = (state == send_data || state == send_data_setup);
    assign io_data_strobe = (en_data_strobe) ? data_strobe_out : 1'bZ;
    assign data_strobe_in = io_data_strobe;

    initial begin : setup_registers
        en_data_out       = 0;
        data_out          = 8'd0;
        state             = 0;
        o_chip_select_neg = 1'b1;
        num_bits          = 32;
        data_strobe_out   = 1'b0;
    end


    assign en_bus_clock    = (state != idle && state != cl_high) ? 1'b1 : 1'b0;
    assign clock_tick      = (clock_count == TIMER_COUNT / 2) ? 1'b1 : 1'b0;

    assign o_bus_clock     = (en_bus_clock) ? bus_clock : 1'b0;
    assign o_bus_clock_neg = (en_bus_clock) ? ~bus_clock : 1'b1;

    always @(posedge clk) begin : spi_clock
        if (state == idle) begin
            bus_clock   <= 1'b0;
            clock_count <= TIMER_COUNT;
        end else begin
            if (clock_count == 0) begin
                clock_count <= TIMER_COUNT;
                bus_clock   <= ~bus_clock;
            end else clock_count <= clock_count - 1;
        end
    end

    integer i;
    always @(posedge clk) begin : sm_logic
        case (state)
            idle: begin
                o_chip_select_neg <= 1'b1;
                en_data_out       <= 1'b0;
                if (go) state <= cl_low;
            end


            cl_low: begin
                o_chip_select_neg <= 1'b0;
                count             <= ADDRESS_LENGTH - 1;
                en_data_out       <= 1'b1;

                if (clock_tick) begin
                    state <= send_command_address;
                    has_latency <= data_strobe_in;
                end
            end


            send_command_address: begin
                for (i = 0; i < BUS_WIDTH; i = i + 1)
                data_out[i] <= command_address[{count[2:0], i[2:0]}];

                if (clock_tick) count <= count - 1;

                if (count == 0 && clock_tick) begin
                    buffer_count <= 0;
                    // the first latency already begins after the sample point of the upper address
                    // therefore we have to subtract one cycle (-2) from the latency
                    if (has_latency) count <= LATENCY_CYCLES * 2 - 3;
                    else count <= LATENCY_CYCLES - 3;

                    state <= wait_latency;
                end
            end


            wait_latency: begin
                if (clock_tick) count <= count - 1;

                if (count == 0 && clock_tick) begin
                    count <= num_bits / BUS_WIDTH - 1;

                    if (is_read) state <= recieve_data;
                    else state <= send_data_setup;
                end
            end


            recieve_data: begin
                en_data_out <= 1'b0;

                if (clock_tick) begin
                    count <= count - 1;
                    buffer_count <= buffer_count + 1;

                    for (i = 0; i < BUS_WIDTH; i = i + 1) begin
                        buffer[buffer_count][i] <= data_in[i];
                    end
                end

                if (count == 0 & clock_tick) begin
                    count <= 0;  // otherwise underflow - can this be synthesised elegantly?
                    state <= cl_high;
                end
            end


            send_data_setup: begin
                buffer_count <= buffer_count + 1;
                for (i = 0; i < BUS_WIDTH; i = i + 1) begin
                    data_out[i] <= buffer[buffer_count][i];
                end
                state <= send_data;
            end


            send_data: begin
                if (clock_tick) begin
                    count <= count - 1;
                    buffer_count <= buffer_count + 1;
                    for (i = 0; i < BUS_WIDTH; i = i + 1) begin
                        data_out[i] <= buffer[buffer_count][i];
                    end
                end

                if (count == 0 & clock_tick) begin
                    count <= 0;  // otherwise underflow - can this be synthesised elegantly?
                    state <= cl_high;
                end
            end


            cl_high: begin
                en_data_out <= 1'b0;
                if (clock_tick) begin
                    state <= idle;
                    en_data_out <= 1'b0;
                end
            end


            default: state <= idle;
        endcase
    end

endmodule
