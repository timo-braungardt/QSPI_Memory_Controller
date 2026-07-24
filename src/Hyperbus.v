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
    wire en_data_out;
    reg [BUS_WIDTH-1 : 0] data_out_reg;
    reg [BUS_WIDTH-1 : 0] data_out_nxt;
    wire [BUS_WIDTH-1 : 0] data_in;

    wire en_data_strobe;
    reg data_strobe_out_reg;
    reg data_strobe_out_nxt;
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
    reg           bus_clock_reg = 0;
    reg           bus_clock_nxt = 0;
    integer       clock_count_reg = 0;
    integer       clock_count_nxt = 0;

    wire          clock_tick;

    // Logic stuff
    reg         is_read;
    reg         is_register_space;
    reg         is_linear_burst;
    reg  [31:0] address;
    wire [47:0] command_address;
    integer       num_bits;
    integer       state_reg;
    integer       state_nxt;

    integer       count_reg = 0;
    integer       count_nxt = 0;
    integer       buffer_count_reg = 0;
    integer       buffer_count_nxt = 0;
    reg           transmission_finished_nxt = 0;
    reg           transmission_finished_reg = 0;

    reg     [7:0] buffer           [0:BUFFER_SIZE -1];

    assign command_address[47]    = is_read;
    assign command_address[46]    = is_register_space;
    assign command_address[45]    = is_linear_burst;
    assign command_address[44:16] = address[31:3];
    assign command_address[15:3]  = 13'd0;
    assign command_address[2:0]   = address[2:0];


    // states
    localparam integer idle = 0;
    localparam integer send_command_address = 11;
    localparam integer wait_latency = 9;
    localparam integer send_data = 3;
    localparam integer receive_data = 4;

    // constants
    localparam integer TIMER_COUNT = 15;
    localparam integer OPCODE_LENGTH = 8;
    localparam integer ADDRESS_LENGTH = 6;
    localparam integer LATENCY_CYCLES = 6 * 2;  // times two because of the two clock edges

    initial begin : setup_registers
        data_out_reg          = 8'd0;
        data_out_nxt          = 8'd0;
        state_reg             = 0;
        o_chip_select_neg = 1'b1;
        num_bits          = 32;
        data_strobe_out_reg   = 1'b0;
    end


    assign en_data_strobe = (state_reg == send_data);
    assign io_data_strobe = (en_data_strobe) ? data_strobe_out_reg : 1'bZ;
    assign data_strobe_in = io_data_strobe;
    assign en_data_out  = (state_reg != idle && state_reg != receive_data);

    assign en_bus_clock    = (state_reg != idle);
    assign clock_tick      = (clock_count_reg == TIMER_COUNT / 2);

    assign o_bus_clock     = (en_bus_clock) ? bus_clock_reg : 1'b0;
    assign o_bus_clock_neg = (en_bus_clock) ? ~bus_clock_reg : 1'b1;
    assign o_reset         = 1'b0;


    always @(*) begin : clock_handler_logic
        bus_clock_nxt = bus_clock_reg;
        clock_count_nxt = clock_count_reg;

        if (state_reg == idle) begin
            bus_clock_nxt = 1'b0;
            clock_count_nxt = TIMER_COUNT;
        end else begin
            if (clock_count_reg == 0) begin
                bus_clock_nxt = ~bus_clock_reg;
                clock_count_nxt = TIMER_COUNT;
            end else begin
                bus_clock_nxt = bus_clock_reg;
                clock_count_nxt = clock_count_reg - 1;
            end
        end
    end


    always @(posedge clk) begin : clock_handler_register
        bus_clock_reg <= bus_clock_nxt;
        clock_count_reg <= clock_count_nxt;
    end


    integer i;
    always @(*) begin : state_machine_logic
        data_out_nxt = data_out_reg;
        state_nxt = state_reg;
        count_nxt = count_reg;
        buffer_count_nxt = buffer_count_reg;
        transmission_finished_nxt = 0;

        case (state_reg)
            idle: begin
                if (go) begin
                    state_nxt = send_command_address;
                    count_nxt = ADDRESS_LENGTH -1;
                end
            end

            send_command_address: begin
                for (i = 0; i < BUS_WIDTH; i = i + 1)
                data_out_nxt[i] = command_address[{count_reg[2:0], i[2:0]}];

                if (clock_tick) count_nxt = count_reg - 1;

                if (count_reg == 0 && clock_tick) begin
                    buffer_count_nxt = 0;
                    // the first latency already begins after the sample point of the upper address
                    // therefore we have to subtract one cycle (-2) from the latency
                    if (has_latency_reg) count_nxt = LATENCY_CYCLES * 2 - 3;
                    else count_nxt = LATENCY_CYCLES - 3;

                    state_nxt = wait_latency;
                end
            end

            wait_latency: begin
                if (clock_tick) count_nxt = count_reg - 1;

                if (count_reg == 0 && clock_tick) begin
                    count_nxt = num_bits / BUS_WIDTH - 1;

                    if (is_read) state_nxt = receive_data;
                    else state_nxt = send_data;
                end
            end

            receive_data: begin
                if (clock_tick) begin
                    count_nxt = count_reg - 1;
                    buffer_count_nxt = buffer_count_reg + 1;

                    for (i = 0; i < BUS_WIDTH; i = i + 1) begin
                        buffer[buffer_count_reg][i] = data_in[i];
                    end
                end

                transmission_finished_nxt = (count_reg == 0 & clock_tick) || transmission_finished_reg;
                if (transmission_finished_reg & clock_tick) begin
                    state_nxt = idle;
                end
            end

            send_data: begin
                for (i = 0; i < BUS_WIDTH; i = i + 1) begin
                    data_out_nxt[i] = buffer[buffer_count_reg][i];
                end

                if (clock_tick) begin
                    count_nxt = count_reg - 1;
                    buffer_count_nxt = buffer_count_reg + 1;
                end

                // This works, because clock_tick triggers at count/2 and not at 0.
                if (count_nxt == 0 & clock_tick) begin
                    count_nxt = 0;  // otherwise underflow - can this be synthesised elegantly?
                    state_nxt = idle;
                end
            end

            default: state_nxt = idle;
        endcase
    end


    always @(posedge clk) begin : state_machine_register
        state_reg <= state_nxt;
        count_reg <= count_nxt;
        buffer_count_reg <= buffer_count_nxt;
        o_chip_select_neg <= ~(state_reg != idle);  // state_nxt possible for perfect sync with state
        data_out_reg <= data_out_nxt;
        transmission_finished_reg <= transmission_finished_nxt;

        if (state_reg == receive_data && clock_tick) begin
            for (i = 0; i < BUS_WIDTH; i = i + 1) begin
                        buffer[buffer_count_reg][i] <= data_in[i];
            end
        end
    end

endmodule
