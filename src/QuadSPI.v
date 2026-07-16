`timescale 1ns / 100ps

module QuadSPI (
    input clk,
    input go,

    // SPI Pins
    output reg o_bus_clock,
    output reg o_chip_select_neg,
    output o_reset,
    inout io_dq0_manager_serial_in,
    inout io_dq1_manager_serial_out,
    inout io_dq2,
    inout io_dq3
);

    localparam BUFFER_SIZE = 16;

    // Pin tristate stuff
    wire en_bus_clock;
    reg  en_serial_out;
    reg serial_out_0, serial_out_1, serial_out_2, serial_out_3;
    wire serial_in_0, serial_in_1, serial_in_2, serial_in_3;

    assign io_dq0_manager_serial_in = (en_serial_out) ? serial_out_0 : 1'bZ;
    assign io_dq1_manager_serial_out  = (en_serial_out)  ? serial_out_1 : 1'bZ;       // ToDo: this pin is not serial out for spi mode!
    assign io_dq2 = (en_serial_out) ? serial_out_2 : 1'bZ;
    assign io_dq3 = (en_serial_out) ? serial_out_3 : 1'bZ;
    assign serial_in_0 = io_dq0_manager_serial_in;
    assign serial_in_1 = io_dq1_manager_serial_out;
    assign serial_in_2 = io_dq2;
    assign serial_in_3 = io_dq3;

    // Logic stuff
    reg     [ 7:0] opcode;
    reg     [23:0] address;
    reg            write_address;
    reg            write_data;
    reg            read_data;
    integer        num_bits;
    integer        state;

    integer        count = 0;
    integer        clock_count = 0;
    reg            bus_clock = 0;
    reg            clock_tick_pos = 0;
    reg            clock_tick_neg = 0;
    integer        buffer_count = 0;

    reg     [ 7:0] buffer             [0:BUFFER_SIZE -1];

    // states
    localparam integer idle = 0;
    localparam integer cl_low = 5;
    localparam integer cl_high = 8;
    localparam integer send_opcode = 1;
    localparam integer send_address = 2;
    localparam integer send_data = 3;
    localparam integer recieve_data = 4;

    // constants
    localparam integer TIMER_COUNT = 2;
    localparam integer OPCODE_LENGTH = 8;
    localparam integer ADDRESS_LENGTH = 24;  // can also be 32


    initial begin : setup_registers
        opcode            = 0;
        address           = 0;
        en_serial_out     = 0;
        serial_out_0      = 0;
        serial_out_1      = 0;
        serial_out_2      = 0;
        serial_out_3      = 0;
        state             = 0;
        o_chip_select_neg = 1'b1;
        o_bus_clock       = 1'b0;

        // the default case is reading from an address.
        write_address     = 1;
        write_data        = 0;
        read_data         = 1;
        num_bits          = 32;
    end


    assign en_bus_clock = (state != idle) ? 1'b1 : 1'b0;
    always @(posedge clk) begin : spi_clock
        o_bus_clock <= bus_clock;

        if (~en_bus_clock) begin
            bus_clock      <= 1'b0;
            clock_count    <= TIMER_COUNT;
            clock_tick_pos <= 1'b0;
            clock_tick_neg <= 1'b0;
        end else begin
            if (clock_count == 0) begin
                clock_count    <= TIMER_COUNT;
                clock_tick_pos <= ~bus_clock;
                clock_tick_neg <= bus_clock;
                bus_clock      <= ~bus_clock;
            end else begin
                clock_count    <= clock_count - 1;
                clock_tick_pos <= 1'b0;
                clock_tick_neg <= 1'b0;
            end
        end
    end


    always @(posedge clk) begin : sm_logic
        case (state)
            idle: begin
                o_chip_select_neg <= 1'b1;
                en_serial_out <= 1'b0;
                if (go) state <= cl_low;
            end


            cl_low: begin
                o_chip_select_neg <= 1'b0;
                count <= OPCODE_LENGTH / 4 - 1;
                en_serial_out <= 1'b1;
                serial_out_0 <= opcode[7];  // this is a bit shitty - but otherwise the old last sent value is sent out
                serial_out_1 <= opcode[6];
                serial_out_2 <= opcode[5];
                serial_out_3 <= opcode[4];
                state <= send_opcode;
            end


            send_opcode: begin
                serial_out_0 <= opcode[{count[0], 2'd0}];
                serial_out_1 <= opcode[{count[0], 2'd1}];
                serial_out_2 <= opcode[{count[0], 2'd2}];
                serial_out_3 <= opcode[{count[0], 2'd3}];

                if (clock_tick_neg) begin
                    count <= count - 1;
                    if (count == 0) begin
                        if (write_address) begin
                            count <= ADDRESS_LENGTH / 4 - 1;
                            state <= send_address;
                        end else if (write_data) begin
                            count <= num_bits / 4 - 1;
                            state <= send_data;
                        end else state <= cl_high;
                    end
                end
            end


            send_address: begin
                serial_out_0 <= address[{count[2:0], 2'd0}];
                serial_out_1 <= address[{count[2:0], 2'd1}];
                serial_out_2 <= address[{count[2:0], 2'd2}];
                serial_out_3 <= address[{count[2:0], 2'd3}];

                if (clock_tick_neg) count <= count - 1;

                if (count == 0 && clock_tick_pos) begin
                    count <= num_bits / 4 - 1;
                    buffer_count <= 0;
                    if (write_data) state <= send_data;
                    else if (read_data) state <= recieve_data;
                    else state <= cl_high;
                end
            end


            recieve_data: begin
                en_serial_out <= 1'b0;

                if (clock_tick_pos) begin
                    count <= count - 1;
                    buffer_count <= buffer_count + 1;

                    buffer[buffer_count[4:1]][{count[0], 2'd0}] <= serial_in_0;
                    buffer[buffer_count[4:1]][{count[0], 2'd1}] <= serial_in_1;
                    buffer[buffer_count[4:1]][{count[0], 2'd2}] <= serial_in_2;
                    buffer[buffer_count[4:1]][{count[0], 2'd3}] <= serial_in_3;
                end

                if (count == 0 & clock_tick_pos) begin
                    count <= 0;  // otherwise underflow - can this be synthesised elegantly?
                    state <= cl_high;
                end
            end


            send_data: begin
                if (clock_tick_neg) begin
                    count <= count - 1;
                    buffer_count <= buffer_count + 1;
                    serial_out_0 <= buffer[buffer_count[4:1]][{count[0], 2'd0}];
                    serial_out_1 <= buffer[buffer_count[4:1]][{count[0], 2'd1}];
                    serial_out_2 <= buffer[buffer_count[4:1]][{count[0], 2'd2}];
                    serial_out_3 <= buffer[buffer_count[4:1]][{count[0], 2'd3}];
                end

                if (count == 0 & clock_tick_neg) begin
                    count <= 0;  // otherwise underflow - can this be synthesised elegantly?
                    state <= cl_high;
                end
            end


            cl_high: begin
                if (clock_tick_neg) begin
                    state <= idle;
                    en_serial_out <= 1'b0;
                end
            end


            default: state <= idle;
        endcase
    end

endmodule
