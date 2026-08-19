`timescale 1ns / 100ps

module SPIController (
    input clk,
    input reset_neg,
    input go,

    // SPI Pins
    output o_bus_clock,
    output reg o_chip_select_neg,
    output o_reset,
    inout io_data0_manager_serial_in,
    inout io_data1_manager_serial_out,
    inout io_data2,
    inout io_data3
);

    localparam BITS_PER_SHIFT = 4;
    localparam BUFFER_SIZE = 16;
    localparam BYTE_SEL_WIDTH = $clog2(BUFFER_SIZE);
    localparam BYTE_SEL_LSB = $clog2(8 / BITS_PER_SHIFT);
    localparam BYTE_SEL_MSB = BYTE_SEL_LSB + BYTE_SEL_WIDTH - 1;
    localparam BYTE_SEL_LSB_SINGLE = $clog2(8);
    localparam BYTE_SEL_MSB_SINGLE = BYTE_SEL_LSB_SINGLE + BYTE_SEL_WIDTH - 1;
    localparam BUS_WIDTH = 4;
    localparam BUS_WIDTH_MSB = BUS_WIDTH - 1;

    // Pin tristate stuff
    wire                      en_bus_clock;
    wire                      en_data_out;
    reg     [BUS_WIDTH_MSB:0] data_out_reg;
    reg     [BUS_WIDTH_MSB:0] data_out_nxt;
    reg     [BUS_WIDTH_MSB:0] data_in;

    // Bus Clock
    reg                       clk_bus_nxt;
    integer                   clock_count_nxt;

    reg                       clk_bus_reg;
    integer                   clock_count_reg;

    // Logic stuff
    reg     [            7:0] opcode;
    reg     [           23:0] address;
    reg                       write_address;
    reg                       write_data;
    reg                       read_data;
    reg                       is_quad_mode;
    integer                   num_bits;
    integer                   state_reg;
    integer                   state_nxt;

    integer                   count_reg;
    integer                   count_nxt;
    wire                      clock_tick_pos;
    wire                      clock_tick_neg;
    integer                   buffer_count_reg;
    integer                   buffer_count_nxt;
    reg                       transmission_finished_nxt;
    reg                       transmission_finished_reg;

    reg     [            7:0] buffer                    [0:BUFFER_SIZE -1];

    // states
    localparam integer IDLE = 0;
    localparam integer SEND_OPCODE = 1;
    localparam integer SEND_ADDRESS = 2;
    localparam integer SEND_DATA = 3;
    localparam integer RECEIVE_DATA = 4;

    // constants
    localparam integer TIMER_COUNT = 2;
    localparam integer OPCODE_LENGTH = 8;
    localparam integer ADDRESS_LENGTH = 24;  // can also be 32

    assign en_bus_clock   = (state_reg != IDLE);
    assign clock_tick_pos = (clock_count_reg == 0 && ~clk_bus_reg);
    assign clock_tick_neg = (clock_count_reg == 0 && clk_bus_reg);
    assign en_data_out    = (state_reg != IDLE && state_reg != RECEIVE_DATA);

    assign o_bus_clock    = (en_bus_clock) ? clk_bus_reg : 1'b0;
    assign o_reset        = 1'b0;


    always @(*) begin : clock_handler_logic
        clk_bus_nxt = clk_bus_reg;
        clock_count_nxt = clock_count_reg;

        if (state_reg == IDLE) begin
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
        if (!reset_neg) begin
            clk_bus_reg <= 0;
            clock_count_reg <= 0;
        end else begin
            clk_bus_reg <= clk_bus_nxt;
            clock_count_reg <= clock_count_nxt;
        end
    end


    always @(*) begin : state_machine_logic
        state_nxt = state_reg;
        count_nxt = count_reg;
        buffer_count_nxt = buffer_count_reg;
        transmission_finished_nxt = 0;

        case (state_reg)
            IDLE: begin
                if (go) begin
                    state_nxt = SEND_OPCODE;
                    count_nxt = (is_quad_mode) ? OPCODE_LENGTH / BITS_PER_SHIFT - 1 : OPCODE_LENGTH - 1;
                end
            end

            SEND_OPCODE: begin
                if (clock_tick_neg) begin
                    count_nxt = count_reg - 1;
                    if (count_reg == 0) begin
                        if (write_address) begin
                            count_nxt = (is_quad_mode) ? ADDRESS_LENGTH / BITS_PER_SHIFT - 1 : ADDRESS_LENGTH - 1;
                            state_nxt = SEND_ADDRESS;
                        end else if (write_data) begin
                            count_nxt = (is_quad_mode) ? num_bits / BITS_PER_SHIFT - 1 : num_bits - 1;
                            state_nxt = SEND_DATA;
                        end else if (read_data) begin
                            count_nxt = (is_quad_mode) ? num_bits / BITS_PER_SHIFT - 1 : num_bits - 1;
                            buffer_count_nxt = 0;
                            state_nxt = RECEIVE_DATA;
                        end else state_nxt = IDLE;
                    end
                end
            end

            SEND_ADDRESS: begin
                if (clock_tick_neg) count_nxt = count_reg - 1;

                if (count_reg == 0 && clock_tick_neg) begin
                    count_nxt = (is_quad_mode) ? num_bits / BITS_PER_SHIFT - 1 : num_bits - 1;
                    buffer_count_nxt = 0;
                    if (write_data) state_nxt = SEND_DATA;
                    else if (read_data) state_nxt = RECEIVE_DATA;
                    else state_nxt = IDLE;
                end
            end

            RECEIVE_DATA: begin
                if (clock_tick_pos) begin
                    count_nxt = count_reg - 1;
                    buffer_count_nxt = buffer_count_reg + 1;
                end

                transmission_finished_nxt = (count_reg == 0 & clock_tick_neg) || transmission_finished_reg;
                if (transmission_finished_reg & clock_tick_neg) begin
                    state_nxt = IDLE;
                end
            end

            SEND_DATA: begin
                if (clock_tick_neg) begin
                    count_nxt = count_reg - 1;
                    buffer_count_nxt = buffer_count_reg + 1;
                end

                transmission_finished_nxt = (count_reg == 0 & clock_tick_pos) || transmission_finished_reg;
                if (transmission_finished_reg & clock_tick_neg) begin
                    state_nxt = IDLE;
                end
            end

            default: state_nxt = IDLE;
        endcase
    end


    always @(posedge clk) begin : state_machine_register
        if (!reset_neg) begin
            state_reg <= IDLE;
            count_reg <= 0;
            buffer_count_reg <= 0;
            o_chip_select_neg <= 1'b1;
            transmission_finished_reg <= 0;
        end else begin
            state_reg <= state_nxt;
            count_reg <= count_nxt;
            buffer_count_reg <= buffer_count_nxt;
            o_chip_select_neg <= ~(state_reg != IDLE);  // state_nxt possible for perfect sync with state
            transmission_finished_reg <= transmission_finished_nxt;
        end
    end


    assign io_data0_manager_serial_in  = (~en_data_out) ? 1'bZ :
                                        (is_quad_mode) ? data_out_reg[0] : 1'bZ;

    assign io_data1_manager_serial_out = (~en_data_out) ? 1'bZ :
                                        (is_quad_mode) ? data_out_reg[1] : data_out_reg[0];

    assign io_data2 = (~en_data_out) ? 1'bZ : (is_quad_mode) ? data_out_reg[2] : 1'bZ;
    assign io_data3 = (~en_data_out) ? 1'bZ : (is_quad_mode) ? data_out_reg[3] : 1'bZ;

    always @(*) begin : data_logic
        data_out_nxt = data_out_reg;

        data_in[0]   = io_data0_manager_serial_in;
        data_in[1]   = io_data1_manager_serial_out;
        data_in[2]   = io_data2;
        data_in[3]   = io_data3;

        case (state_reg)
            SEND_OPCODE: begin
                if (is_quad_mode) begin
                    data_out_nxt[0] = opcode[{count_reg[0], 2'd0}];
                    data_out_nxt[1] = opcode[{count_reg[0], 2'd1}];
                    data_out_nxt[2] = opcode[{count_reg[0], 2'd2}];
                    data_out_nxt[3] = opcode[{count_reg[0], 2'd3}];
                end else begin
                    data_out_nxt[0] = opcode[count_reg[2:0]];
                end
            end

            SEND_ADDRESS: begin
                if (is_quad_mode) begin
                    data_out_nxt[0] = address[{count_reg[2:0], 2'd0}];
                    data_out_nxt[1] = address[{count_reg[2:0], 2'd1}];
                    data_out_nxt[2] = address[{count_reg[2:0], 2'd2}];
                    data_out_nxt[3] = address[{count_reg[2:0], 2'd3}];
                end else begin
                    data_out_nxt[0] = address[count_reg[4:0]];
                end
            end

            SEND_DATA: begin
                if (is_quad_mode) begin
                    data_out_nxt[0] = buffer[buffer_count_reg[BYTE_SEL_MSB:BYTE_SEL_LSB]][{
                        count_reg[0], 2'd0
                    }];
                    data_out_nxt[1] = buffer[buffer_count_reg[BYTE_SEL_MSB:BYTE_SEL_LSB]][{
                        count_reg[0], 2'd1
                    }];
                    data_out_nxt[2] = buffer[buffer_count_reg[BYTE_SEL_MSB:BYTE_SEL_LSB]][{
                        count_reg[0], 2'd2
                    }];
                    data_out_nxt[3] = buffer[buffer_count_reg[BYTE_SEL_MSB:BYTE_SEL_LSB]][{
                        count_reg[0], 2'd3
                    }];
                end else begin
                    data_out_nxt[0] = buffer[buffer_count_reg[BYTE_SEL_MSB_SINGLE:BYTE_SEL_LSB_SINGLE]][count_reg[BYTE_SEL_LSB_SINGLE-1:0]];
                end
            end
        endcase
    end


    always @(posedge clk) begin : data_register
        if (!reset_neg) begin
            data_out_reg <= 0;
        end else begin
            data_out_reg <= data_out_nxt;

            if (state_reg == RECEIVE_DATA && clock_tick_pos) begin
                if (is_quad_mode) begin
                    buffer[buffer_count_reg[BYTE_SEL_MSB:BYTE_SEL_LSB]][{
                        count_reg[0], 2'd0
                    }] <= data_in[0];
                    buffer[buffer_count_reg[BYTE_SEL_MSB:BYTE_SEL_LSB]][{
                        count_reg[0], 2'd1
                    }] <= data_in[1];
                    buffer[buffer_count_reg[BYTE_SEL_MSB:BYTE_SEL_LSB]][{
                        count_reg[0], 2'd2
                    }] <= data_in[2];
                    buffer[buffer_count_reg[BYTE_SEL_MSB:BYTE_SEL_LSB]][{
                        count_reg[0], 2'd3
                    }] <= data_in[3];
                end else begin
                    buffer[buffer_count_reg[BYTE_SEL_MSB_SINGLE:BYTE_SEL_LSB_SINGLE]][count_reg[BYTE_SEL_LSB_SINGLE-1:0]] <= data_in[0];
                end
            end
        end
    end


    always @(posedge clk) begin : configuration_register
        if (!reset_neg) begin
            opcode <= 0;
            address <= 0;
            write_address <= 1'b1;
            write_data <= 1'b0;
            read_data <= 1'b1;
            num_bits <= 32;
            is_quad_mode <= 1'b1;
        end
    end


endmodule
