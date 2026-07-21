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
    wire en_serial_out;
    reg  serial_out_reg;
    reg  serial_out_nxt;
    wire serial_in;

    assign io_manager_serial_out = (en_serial_out) ? serial_out_reg : 1'bZ;
    assign serial_in             = io_manager_serial_in;

    // SPI Clock
    reg            clk_bus_nxt;
    integer        clock_count_nxt;

    reg            clk_bus_reg = 0;
    integer        clock_count_reg = 0;

    // Logic stuff
    reg     [ 7:0] opcode;
    reg     [23:0] address;
    reg            write_address;
    reg            write_data;
    reg            read_data;
    integer        num_bits;
    integer        state_reg;
    integer        state_nxt;

    integer        count_reg = 0;
    integer        count_nxt = 0;
    wire           clock_tick_pos;
    wire           clock_tick_neg;
    integer        buffer_count_reg = 0;
    integer        buffer_count_nxt = 0;
    reg            transmission_finished_nxt = 0;
    reg            transmission_finished_reg = 0;

    reg     [ 7:0] buffer               [0:BUFFER_SIZE -1];

    // states
    localparam integer idle = 0;
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
        state_reg         = 0;
        state_nxt         = 0;
        o_chip_select_neg = 1'b1;

        // the default case is reading from an address.
        write_address     = 1;
        write_data        = 0;
        read_data         = 1;
        num_bits          = 32;
    end


    assign en_bus_clock   = (state_reg != idle);
    assign clock_tick_pos = (clock_count_reg == 0 && ~clk_bus_reg);
    assign clock_tick_neg = (clock_count_reg == 0 && clk_bus_reg);
    assign en_serial_out = (state_reg != idle && state_reg != recieve_data);

    assign o_bus_clock    = (en_bus_clock) ? clk_bus_reg : 1'b0;

    always @(*) begin : clock_handler_logic
        if (state_reg == idle) begin
            clk_bus_nxt = 1'b0;
            clock_count_nxt = TIMER_COUNT;
        end else begin
            if (clock_count_reg == 0) begin
                clk_bus_nxt = ~clk_bus_reg;
                clock_count_nxt = TIMER_COUNT;
            end else begin
                clk_bus_nxt = clk_bus_reg;
                clock_count_nxt = clock_count_reg - 1;
            end
        end
    end


    always @(posedge clk) begin : clock_handler_register
        clk_bus_reg <= clk_bus_nxt;
        clock_count_reg <= clock_count_nxt;
    end


    always @(*) begin : state_machine_logic
        case (state_reg)
            idle: begin
                serial_out_nxt = 1'b0;
                if (go) begin
                    state_nxt = send_opcode;
                    count_nxt = OPCODE_LENGTH - 1;
                end
            end

            send_opcode: begin
                serial_out_nxt = opcode[count_reg];

                if (clock_tick_neg) begin
                    count_nxt = count_reg - 1;
                    if (count_reg == 0) begin
                        if (write_address) begin
                            count_nxt = ADDRESS_LENGTH - 1;
                            state_nxt = send_address;
                        end else if (write_data) begin
                            count_nxt = num_bits - 1;
                            state_nxt = send_data;
                        end else if (read_data) begin
                            count_nxt = num_bits - 1;
                            buffer_count_nxt = 0;
                            state_nxt = recieve_data;
                        end else state_nxt = idle;
                    end
                end
            end

            send_address: begin
                serial_out_nxt = address[count_reg];

                if (clock_tick_neg) count_nxt = count_reg - 1;

                if (count_reg == 0 && clock_tick_neg) begin
                    count_nxt = num_bits - 1;
                    buffer_count_nxt = 0;
                    if (write_data) state_nxt = send_data;
                    else if (read_data) state_nxt = recieve_data;
                    else state_nxt = idle;
                end
            end


            recieve_data: begin
                if (clock_tick_pos) begin
                    count_nxt = count_reg - 1;
                    buffer_count_nxt = buffer_count_reg + 1;
                    serial_out_nxt = serial_in;
                end

                transmission_finished_nxt = (count_reg == 0 & clock_tick_neg) || transmission_finished_reg;
                if (transmission_finished_reg & clock_tick_neg) begin
                    count_nxt = 0;  // otherwise underflow - can this be synthesised elegantly?
                    state_nxt = idle;
                    transmission_finished_nxt = 0;
                end
            end

            send_data: begin
                serial_out_nxt = buffer[buffer_count_reg[6:3]][count_reg[2:0]];
                if (clock_tick_neg) begin
                    count_nxt = count_reg - 1;
                    buffer_count_nxt = buffer_count_reg + 1;
                end

                transmission_finished_nxt = (count_reg == 0 & clock_tick_pos) || transmission_finished_reg;
                if (transmission_finished_reg & clock_tick_neg) begin
                    count_nxt = 0;  // otherwise underflow - can this be synthesised elegantly?
                    state_nxt = idle;
                    transmission_finished_nxt = 0;
                end
            end


            default: state_nxt = idle;
        endcase
    end

    always @(posedge clk) begin : state_machine_register
        state_reg <= state_nxt;
        count_reg <= count_nxt;
        buffer_count_reg <= buffer_count_nxt;
        o_chip_select_neg <= ~(state_reg != idle);
        serial_out_reg <= serial_out_nxt;
        transmission_finished_reg <= transmission_finished_nxt;

        if (state_reg == recieve_data && clock_tick_pos) begin
            buffer[buffer_count_reg[6:3]][count_reg[2:0]] <= serial_in;
        end
    end

endmodule
