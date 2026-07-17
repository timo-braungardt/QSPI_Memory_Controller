`timescale 1ns / 100ps

module BasicSPI (
    input clk,
    input go,

    // SPI Pins
    output o_bus_clock,
    output reg o_chip_select_neg,
    output o_reset,
    inout io_manager_serial_in,
    inout io_manager_serial_out
);

    localparam BUFFER_SIZE = 16;

    // Pin tristate stuff
    wire en_bus_clock;
    reg  en_serial_out;
    reg  serial_out;
    wire serial_in;

    assign io_manager_serial_out = (en_serial_out) ? serial_out : 1'bZ;
    assign serial_in             = io_manager_serial_in;

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
    wire           clock_tick_pos;
    wire           clock_tick_neg;
    integer        buffer_count = 0;

    reg     [ 7:0] buffer           [0:BUFFER_SIZE -1];

    // states
    localparam integer idle = 0;
    localparam integer cl_low = 5;
    localparam integer cl_high = 8;
    localparam integer send_opcode = 1;
    localparam integer send_address = 2;
    localparam integer send_data = 3;
    localparam integer send_data_setup = 12;
    localparam integer recieve_data = 4;

    // constants
    localparam integer TIMER_COUNT = 2;
    localparam integer OPCODE_LENGTH = 8;
    localparam integer ADDRESS_LENGTH = 24;  // can also be 32


    initial begin : setup_registers
        opcode            = 0;
        address           = 0;
        en_serial_out     = 0;
        serial_out        = 0;
        state             = 0;
        o_chip_select_neg = 1'b1;

        // the default case is reading from an address.
        write_address     = 1;
        write_data        = 0;
        read_data         = 1;
        num_bits          = 32;
    end


    assign en_bus_clock   = (state != idle && state != cl_high) ? 1'b1 : 1'b0;
    assign clock_tick_pos = (clock_count == 0 && ~bus_clock) ? 1'b1 : 1'b0;
    assign clock_tick_neg = (clock_count == 0 && bus_clock) ? 1'b1 : 1'b0;

    assign o_bus_clock    = (en_bus_clock) ? bus_clock : 1'b0;

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


    always @(posedge clk) begin : sm_logic
        case (state)
            idle: begin
                o_chip_select_neg <= 1'b1;
                en_serial_out <= 1'b0;
                if (go) state <= cl_low;
            end

            cl_low: begin
                o_chip_select_neg <= 1'b0;
                count <= OPCODE_LENGTH - 1;
                en_serial_out <= 1'b1;
                serial_out <= opcode[OPCODE_LENGTH -1];     // this is a bit shitty - but otherwise the old last sent value is sent out // ToDo: still needed with counter-clock?
                state <= send_opcode;
            end

            send_opcode: begin
                serial_out <= opcode[count];

                if (clock_tick_neg) begin
                    count <= count - 1;
                    if (count == 0) begin
                        if (write_address) begin
                            count <= ADDRESS_LENGTH - 1;
                            state <= send_address;
                        end else if (write_data) begin
                            count <= num_bits - 1;
                            state <= send_data;
                        end else if (read_data) begin
                            count <= num_bits - 1;
                            buffer_count <= 0;
                            state <= recieve_data;
                        end else state <= cl_high;
                    end
                end
            end

            send_address: begin
                serial_out <= address[count];

                if (clock_tick_neg) count <= count - 1;

                if (count == 0 && clock_tick_neg) begin
                    count <= num_bits - 1;
                    buffer_count <= 0;
                    if (write_data) state <= send_data_setup;
                    else if (read_data) state <= recieve_data;
                    else state <= cl_high;
                end
            end


            recieve_data: begin
                if (clock_tick_pos) begin
                    count <= count - 1;
                    buffer_count <= buffer_count + 1;

                    buffer[buffer_count[6:3]][count[2:0]] <= serial_in;

                    serial_out <= serial_in;
                    //en_serial_out <= 1'b0;
                end

                // ToDo: the problem is, that when the count is 0, we still need to read one more bit
                // we would have to wait one more clock to output the last bit.
                if (count == -1 & clock_tick_pos) begin
                    count <= 0;  // otherwise underflow - can this be synthesised elegantly?
                    state <= cl_high;
                end
            end


            send_data_setup: begin
                count <= count - 1;
                buffer_count <= buffer_count + 1;
                serial_out <= buffer[buffer_count[6:3]][count[2:0]];
                state <= send_data;
            end

            // ToDo: the problem is, that the count is 0, we shift out the new value and then go to the next state, which deactivates the output and the clock
            // we would have to wait one more clock to output the last bit.
            send_data: begin
                if (clock_tick_neg) begin
                    count <= count - 1;
                    buffer_count <= buffer_count + 1;
                    serial_out <= buffer[buffer_count[6:3]][count[2:0]];
                end

                // ToDo: this is needed, otherwise the last bit is not transfered
                // this is not nice, but the file will hopefully be rewritten soon anyways...
                if (count == -1 & clock_tick_neg) begin
                    count <= 0;  // otherwise underflow - can this be synthesised elegantly?
                    state <= cl_high;
                end
            end


            cl_high: begin
                if (clock_tick_pos) begin
                    state <= idle;
                    en_serial_out <= 1'b0;
                end
            end


            default: state <= idle;
        endcase
    end

endmodule
