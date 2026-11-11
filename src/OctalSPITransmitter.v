`timescale 1ps / 1ps
/*
OSPI Transmitter

Implementation of the octal spi interface.

The bus clock is half the speed of the input clock.
Data is shifted out at every clock cycle.
The data is shifted out at the same time as the bus clock, therefore buffer have to be inserted on the outputs of the data line.
The data input does not have to be buffered. It can be sampled at the system clock edges.
*/

module OctalSPITransmitter #(
    parameter ADDRESS_LENGTH = 32,  // address is always 32 bit long
    parameter BYTE = 8,
    parameter CHIP_TYPE = -1  // 1 is Infineon, 2 is APMemory
) (
    input clk,
    input reset_neg,
    input start_transmission,

    input  [ADDRESS_LENGTH-1:0] i_address,
    input  [               7:0] i_opcode,
    input                       i_config_read_data,
    input                       i_config_write_data,
    input                       i_config_write_address,
    input                       i_last_byte,
    input                       i_write_data_byte_mask,
    input  [          BYTE-1:0] i_write_data,
    output [          BYTE-1:0] o_read_data,
    output                      o_finish,
    output                      o_write_next_byte,
    output                      o_read_next_byte,

    // OctalSPI Pins
    output     o_bus_clock,
    output     o_bus_clock_neg,
    output reg o_chip_select_neg,

    input  i_spi_data_strobe,
    output o_spi_data_strobe,
    output o_spi_data_strobe_output_enable,

    input  [BYTE-1:0] i_spi_data,
    output [BYTE-1:0] o_spi_data,
    output            o_spi_data_output_enable
);

    // constants
    localparam BUS_WIDTH = 8;

    // Pin tristate stuff
    reg en_data_out_reg;
    reg en_data_out_nxt;
    reg [BUS_WIDTH-1 : 0] data_out_reg;
    reg [BUS_WIDTH-1 : 0] data_out_nxt;

    wire en_data_strobe;
    reg data_strobe_out_reg;
    reg data_strobe_out_nxt;  // ToDo: The signal has to be driven for write (issue #15) 0 is write, 1 is mask
    (* dont_touch = "true" *)
    reg recieved_next_byte_reg;

    reg has_latency_reg;
    reg has_latency_nxt;

    // Bus Clock
    reg bus_clock_reg;
    reg bus_clock_nxt;
    reg bus_clock_p2_reg;  // the bus clock has to be shifted a bit to guarantee that the data is present on the bus
    reg bus_clock_p2_nxt;
    integer clock_count_reg;
    integer clock_count_nxt;
    wire is_transfer_even = bus_clock_p2_reg;

    // states transmission FSM
    localparam NUM_STATES = 9;
    localparam INDEX_STATES_MSB = $clog2(NUM_STATES) - 1;
    localparam [INDEX_STATES_MSB:0] IDLE = 0;
    localparam [INDEX_STATES_MSB:0] CS_LOW = 8;
    localparam [INDEX_STATES_MSB:0] SEND_OPCODE = 1;
    localparam [INDEX_STATES_MSB:0] SEND_ADDRESS = 2;
    localparam [INDEX_STATES_MSB:0] WAIT_LATENCY = 3;
    localparam [INDEX_STATES_MSB:0] SEND_DATA = 4;
    localparam [INDEX_STATES_MSB:0] RECEIVE_DATA = 5;
    localparam [INDEX_STATES_MSB:0] CS_HIGH = 6;
    localparam [INDEX_STATES_MSB:0] FINISH = 7;

    // Logic stuff
    (* dont_touch = "true" *)
    reg     [INDEX_STATES_MSB:0] state_reg;
    reg     [INDEX_STATES_MSB:0] state_nxt;

    integer                      count_reg;
    integer                      count_nxt;
    integer                      latency_offset;
    reg     [          BYTE-1:0] data_read_reg;

    assign o_read_data = data_read_reg;

    // constants
    localparam INFINEON_CHIP = 1;
    localparam APMEMORY_CHIP = 2;

    localparam integer ADDRESS_CYCLES = 4;
    localparam integer OPCODE_CYCLES = 2;

    localparam INFINEON_LATENCY_CYCLES = 7 * 2;
    localparam APMEMORY_LATENCY_CYCLES = 5 * 2;
    localparam INFINEON_LATENCY_OFFSET = 3;
    localparam APMEMORY_LATENCY_OFFSET = -1;
    // times two because of the two clock edges
    localparam integer LATENCY_CYCLES = (CHIP_TYPE == INFINEON_CHIP) ? INFINEON_LATENCY_CYCLES : APMEMORY_LATENCY_CYCLES;
    localparam integer LATENCY_OFFSET = (CHIP_TYPE == INFINEON_CHIP) ? INFINEON_LATENCY_OFFSET : APMEMORY_LATENCY_OFFSET;

    localparam integer NUM_SHORT_LATENCY_CYCLES = LATENCY_CYCLES + LATENCY_OFFSET;
    localparam integer NUM_LONG_LATENCY_CYCLES = 2 * LATENCY_CYCLES + LATENCY_OFFSET;
    //localparam integer READ_LATENCY_IN_CYCLE = 1; // (issue #15)
    localparam integer TEMP_OPERATION_CYCLES = 1;   // transfer 2 bytes

    // ToDo: why was this in en_data_strobe?: | state_reg == WAIT_LATENCY 
    assign en_data_strobe  = (state_reg == SEND_DATA | (~i_config_read_data & (state_reg == CS_HIGH | state_reg == FINISH)));   // FINISH is needed, because otherwise the model does not store the value

    (* dont_touch = "true" *)
    reg temp_data_strobe_debug;

    assign o_bus_clock = bus_clock_p2_reg;
    assign o_bus_clock_neg = ~bus_clock_p2_reg;
    assign o_finish = (state_reg == FINISH);
    assign o_read_next_byte = recieved_next_byte_reg;
    assign o_write_next_byte = (state_reg == SEND_DATA);
    assign o_spi_data_output_enable = en_data_out_reg;
    assign o_spi_data = data_out_reg;
    assign o_spi_data_strobe_output_enable = en_data_strobe;
    assign o_spi_data_strobe = data_strobe_out_reg;


    always @(*) begin : clock_logic
        bus_clock_nxt = 1'b0;
        bus_clock_p2_nxt = 1'b0;

        if (state_reg != IDLE & state_reg != CS_LOW & state_reg != CS_HIGH & state_reg != FINISH) begin
            bus_clock_nxt = ~bus_clock_reg;
            bus_clock_p2_nxt = bus_clock_reg;
        end
    end


    always @(posedge clk) begin : clock_register
        if (~reset_neg) begin
            bus_clock_reg <= 0;
            bus_clock_p2_reg <= 0;
        end else begin
            bus_clock_reg <= bus_clock_nxt;
            bus_clock_p2_reg <= bus_clock_p2_nxt;  // a delayed clock is needed so that the data is set before the clock edge goes out to the device
        end
    end


    always @(*) begin : state_machine_logic
        state_nxt = state_reg;
        count_nxt = OPCODE_CYCLES - 1;
        has_latency_nxt = has_latency_reg;
        en_data_out_nxt = en_data_out_reg;

        // the write needs to put the data on the bus two cycles early, therefore -2
        latency_offset = (i_config_write_data) ? -2 : 0;

        case (state_reg)
            IDLE: begin
                if (start_transmission) begin
                    state_nxt = CS_LOW;
                    en_data_out_nxt = 1'b1;
                end
            end

            CS_LOW: begin
                state_nxt = SEND_OPCODE;
                count_nxt = OPCODE_CYCLES - 1;
            end

            SEND_OPCODE: begin
                count_nxt = count_reg - 1;
                if (count_reg == 0) begin
                    if (i_config_write_address) begin
                        count_nxt = ADDRESS_CYCLES - 1;
                        state_nxt = SEND_ADDRESS;
                        has_latency_nxt = (CHIP_TYPE == INFINEON_CHIP) ? i_spi_data_strobe : 1'b0;
                    end else state_nxt = CS_HIGH;
                end
            end

            SEND_ADDRESS: begin
                count_nxt = count_reg - 1;

                if (count_reg == 0) begin
                    if (has_latency_reg) count_nxt = NUM_LONG_LATENCY_CYCLES + latency_offset;
                    else count_nxt = NUM_SHORT_LATENCY_CYCLES + latency_offset;

                    state_nxt = WAIT_LATENCY;
                end
            end

            WAIT_LATENCY: begin
                count_nxt = count_reg - 1;

                en_data_out_nxt = ~i_config_read_data;
                if (count_reg == 0) begin
                    count_nxt = TEMP_OPERATION_CYCLES;


                    if (i_config_read_data) state_nxt = RECEIVE_DATA;
                    else if (i_config_write_data) state_nxt = SEND_DATA;
                    else state_nxt = CS_HIGH;
                end
            end

            RECEIVE_DATA: begin
                count_nxt = count_reg - 1;

                if (i_last_byte) begin
                    state_nxt = CS_HIGH;
                end
            end

            SEND_DATA: begin
                count_nxt = 0;

                // we always have to send two bytes
                // additionally we check for the count - if we only write one byte the state machine would skip the transfer
                if (i_last_byte & is_transfer_even & count_reg == 0) begin
                    state_nxt = CS_HIGH;
                end
            end

            CS_HIGH: state_nxt = FINISH;
            FINISH:  state_nxt = IDLE;

            default: state_nxt = IDLE;
        endcase
    end


    always @(posedge clk) begin : state_machine_register
        if (~reset_neg) begin
            state_reg <= IDLE;
            count_reg <= 0;
            o_chip_select_neg <= 1'b1;
            has_latency_reg <= 0;
            data_strobe_out_reg <= 0;
            en_data_out_reg <= 0;
        end else begin
            state_reg <= state_nxt;
            count_reg <= count_nxt;
            o_chip_select_neg <= ~(state_nxt != IDLE);  // state_nxt for perfect sync with state
            has_latency_reg <= has_latency_nxt;
            data_strobe_out_reg <= data_strobe_out_nxt;
            en_data_out_reg <= en_data_out_nxt;
            temp_data_strobe_debug <= i_spi_data_strobe;
        end
    end


    always @(*) begin : data_logic
        integer i;
        data_out_nxt = data_out_reg;

        case (state_reg)
            SEND_OPCODE: begin
                for (i = 0; i < BUS_WIDTH; i = i + 1) data_out_nxt[i] = i_opcode[i[2:0]];
            end

            SEND_ADDRESS: begin
                for (i = 0; i < BUS_WIDTH; i = i + 1)
                data_out_nxt[i] = i_address[{count_reg[1:0], i[2:0]}];
            end

            SEND_DATA: begin
                data_out_nxt = i_write_data;
                // if we wrote the last byte and we wrote an uneven ammount of bytes, we have to mask the next byte transfer
                if (i_last_byte & ~is_transfer_even & count_reg == 0)
                    data_strobe_out_nxt = 1'b1;
                else
                    data_strobe_out_nxt = i_write_data_byte_mask;
            end

            default: ;
        endcase
    end


    always @(posedge clk) begin : data_register
        if (~reset_neg) begin
            data_out_reg <= 0;
            recieved_next_byte_reg <= 0;
            data_read_reg <= 0;
        end else begin
            data_out_reg <= data_out_nxt;
            recieved_next_byte_reg <= 1'b0;

            if (state_reg == RECEIVE_DATA) begin
                data_read_reg <= i_spi_data;
                recieved_next_byte_reg <= 1'b1;
            end
        end
    end


    // This is only force a valid value in the CHIP_TYPE parameter
    // generated by claude
    /* verilator lint_off MODMISSING */
    generate
        if (CHIP_TYPE != INFINEON_CHIP && CHIP_TYPE != APMEMORY_CHIP) begin : g_chip_check
            CHIP_must_be_set illegal_instance ();
        end
    endgenerate
    /* verilator lint_on MODMISSING */
endmodule
