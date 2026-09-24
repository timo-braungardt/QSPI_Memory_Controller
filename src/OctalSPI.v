`timescale 1ps / 1ps
/*
OctalSPI

Implementation of the octal spi interface.

The bus clock is half the speed of the input clock.
Data is shifted out at every clock cycle.
The data is shifted out at the same time as the bus clock, therefore buffer have to be inserted on the outputs of the data line.
The data input does not have to be buffered. It can be sampled at the system clock edges.
*/

module OctalSPI (
    input clk,
    input reset_neg,
    input go,

    // OctalSPI Pins
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
    wire en_data_out;
    reg [BUS_WIDTH-1 : 0] data_out_reg;
    reg [BUS_WIDTH-1 : 0] data_out_nxt;
    wire [BUS_WIDTH-1 : 0] data_in;

    wire en_data_strobe;
    reg data_strobe_out_reg;
    reg data_strobe_out_nxt = 0;  // ToDo: The signal has to be driven for write (issue #15)
    wire data_strobe_in;

    reg has_latency_reg;
    reg has_latency_nxt;

    genvar x;
    generate
        for (x = 0; x < BUS_WIDTH; x = x + 1) begin
            assign io_data[x] = (en_data_out) ? data_out_reg[x] : 1'bZ;
            assign data_in[x] = io_data[x];
        end
    endgenerate

    // Bus Clock
    reg            bus_clock_reg;
    reg            bus_clock_nxt;
    integer        clock_count_reg;
    integer        clock_count_nxt;

    // Logic stuff
    reg            is_read;
    reg            is_register_space;
    reg            is_linear_burst;
    reg     [31:0] address;
    wire    [47:0] command_address;
    integer        num_bits;
    integer        state_reg;
    integer        state_nxt;

    integer        count_reg;
    integer        count_nxt;
    integer        latency_offset;
    integer        buffer_count_reg;
    integer        buffer_count_nxt;

    reg     [ 7:0] buffer            [0:BUFFER_SIZE -1];

    // Magic Numbers
    localparam integer CA_IS_READ_BIT = 47;
    localparam integer CA_IS_REGISTER_BIT = 46;
    localparam integer CA_IS_LINEAR_BURST_BIT = 45;
    localparam integer CA_ADDRESS_UPPER_MSB = 44;
    localparam integer CA_ADDRESS_UPPER_LSB = 16;
    localparam integer CA_ADDRESS_UNUSED_MSB = 15;
    localparam integer CA_ADDRESS_UNUSED_LSB = 3;
    localparam integer CA_ADDRESS_LOWER_MSB = 2;
    localparam integer CA_ADDRESS_LOWER_LSB = 0;


    assign command_address[CA_IS_READ_BIT]                                = is_read;
    assign command_address[CA_IS_REGISTER_BIT]                            = is_register_space;
    assign command_address[CA_IS_LINEAR_BURST_BIT]                        = is_linear_burst;
    assign command_address[CA_ADDRESS_UPPER_MSB : CA_ADDRESS_UPPER_LSB]   = address[31:3];
    assign command_address[CA_ADDRESS_UNUSED_MSB : CA_ADDRESS_UNUSED_LSB] = 13'd0;
    assign command_address[CA_ADDRESS_LOWER_MSB : CA_ADDRESS_LOWER_LSB]   = address[2:0];


    // states
    localparam integer IDLE = 0;
    localparam integer SEND_COMMAND_ADDRESS = 11;
    localparam integer WAIT_LATENCY = 9;
    localparam integer SEND_DATA = 3;
    localparam integer RECEIVE_DATA = 4;
    localparam integer CS_HIGH = 5;
    localparam integer CS_HIGH2 = 6;

    // constants
    localparam integer TIMER_COUNT = 15;
    localparam integer ADDRESS_CYCLES = 6;
    // times two because of the two clock edges
    localparam integer LATENCY_CYCLES = 4 * 2;
    // the first latency already begins after the sample point of the upper address
    // therefore we have to subtract one cycle (-2) from the latency
    localparam integer NUM_SHORT_LATENCY_CYCLES = LATENCY_CYCLES - 6;
    localparam integer NUM_LONG_LATENCY_CYCLES = LATENCY_CYCLES + NUM_SHORT_LATENCY_CYCLES;
    localparam integer READ_LATENCY_IN_CYCLE = 1;

    assign en_data_strobe  = (state_reg == SEND_DATA | (~is_read & state_reg == CS_HIGH));
    assign io_data_strobe  = (en_data_strobe) ? data_strobe_out_reg : 1'bZ;
    assign data_strobe_in  = io_data_strobe;
    assign en_data_out     = (state_reg != IDLE && state_reg != RECEIVE_DATA);

    assign o_bus_clock     = bus_clock_reg;
    assign o_bus_clock_neg = ~bus_clock_reg;
    assign o_reset         = 1'b0;


    always @(*) begin : clock_logic
        bus_clock_nxt = 1'b0;

        if (state_reg != IDLE & state_reg != CS_HIGH2) begin
            bus_clock_nxt = ~bus_clock_reg;
        end
    end


    always @(posedge clk) begin : clock_register
        if (~reset_neg) begin
            bus_clock_reg <= 0;
        end else begin
            bus_clock_reg <= bus_clock_nxt;
        end
    end


    integer i;
    always @(*) begin : state_machine_logic
        state_nxt = state_reg;
        count_nxt = ADDRESS_CYCLES - 1;
        buffer_count_nxt = buffer_count_reg;
        has_latency_nxt = has_latency_reg;

        // the read needs one more cycle after the latency until the memory puts out data
        // therefore +2
        latency_offset = (is_read) ? 1 : -1;

        case (state_reg)
            IDLE: begin
                if (go) begin
                    state_nxt = SEND_COMMAND_ADDRESS;
                    count_nxt = count_nxt - 1;
                    for (i = 0; i < BUS_WIDTH; i = i + 1)
                    data_out_nxt[i] = command_address[{count_reg[2:0], i[2:0]}];
                end
            end

            SEND_COMMAND_ADDRESS: begin
                has_latency_nxt = 1'b1;  // ToDo: always set latency to long latency (issue #15)
                count_nxt = count_reg - 1;

                if (count_reg == 0) begin
                    buffer_count_nxt = 0;
                    if (has_latency_reg) count_nxt = NUM_LONG_LATENCY_CYCLES + latency_offset;
                    else count_nxt = NUM_SHORT_LATENCY_CYCLES + latency_offset;

                    state_nxt = WAIT_LATENCY;
                end
                /* (issue #15)
                if (count_reg == (ADDRESS_CYCLES - READ_LATENCY_IN_CYCLE)) begin
                    has_latency_nxt = 1'b1;
                end
                */
            end

            WAIT_LATENCY: begin
                count_nxt = count_reg - 1;

                if (count_reg == 0) begin
                    count_nxt = num_bits / BUS_WIDTH - 1;

                    if (is_read) state_nxt = RECEIVE_DATA;
                    else state_nxt = SEND_DATA;
                end
            end

            RECEIVE_DATA: begin
                count_nxt = count_reg - 1;
                buffer_count_nxt = buffer_count_reg + 1;

                if (count_reg == 0) begin
                    state_nxt = CS_HIGH;
                end
            end

            SEND_DATA: begin

                count_nxt = count_reg - 1;
                buffer_count_nxt = buffer_count_reg + 1;


                if (count_reg == 0) begin
                    count_nxt = 0;  // otherwise underflow - can this be synthesised elegantly?
                    state_nxt = CS_HIGH;
                end
            end

            CS_HIGH:  state_nxt <= CS_HIGH2;
            CS_HIGH2: state_nxt <= IDLE;

            default: state_nxt = IDLE;
        endcase
    end


    always @(posedge clk) begin : state_machine_register
        if (~reset_neg) begin
            state_reg <= IDLE;
            count_reg <= 0;
            buffer_count_reg <= 0;
            o_chip_select_neg <= 1'b1;
            has_latency_reg <= 0;
            data_strobe_out_reg <= 0;
        end else begin
            state_reg <= state_nxt;
            count_reg <= count_nxt;
            buffer_count_reg <= buffer_count_nxt;
            o_chip_select_neg <= ~(state_nxt != IDLE);  // state_nxt for perfect sync with state
            has_latency_reg <= has_latency_nxt;
            data_strobe_out_reg <= data_strobe_out_nxt;
        end
    end


    always @(*) begin : data_logic
        data_out_nxt = data_out_reg;

        case (state_reg)
            SEND_COMMAND_ADDRESS: begin
                for (i = 0; i < BUS_WIDTH; i = i + 1)
                data_out_nxt[i] = command_address[{count_reg[2:0], i[2:0]}];
            end

            SEND_DATA: begin
                for (i = 0; i < BUS_WIDTH; i = i + 1) begin
                    data_out_nxt[i] = buffer[buffer_count_reg][i];
                end
            end

            default: ;
        endcase
    end


    always @(posedge clk) begin : data_register
        if (~reset_neg) begin
            data_out_reg <= 0;
        end else begin
            data_out_reg <= data_out_nxt;

            if (state_reg == RECEIVE_DATA) begin
                for (i = 0; i < BUS_WIDTH; i = i + 1) begin
                    buffer[buffer_count_reg][i] <= data_in[i];
                end
            end
        end
    end


    always @(posedge clk) begin : configuration_register
        if (~reset_neg) begin
            is_read <= 0;
            is_register_space <= 0;
            is_linear_burst <= 0;
            address <= 0;
            num_bits <= 32;
        end
    end

endmodule
