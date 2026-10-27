`timescale 1ps / 1ps
/*
OctalSPI

Implementation of the octal spi interface.

The bus clock is half the speed of the input clock.
Data is shifted out at every clock cycle.
The data is shifted out at the same time as the bus clock, therefore buffer have to be inserted on the outputs of the data line.
The data input does not have to be buffered. It can be sampled at the system clock edges.
*/

module OctalSPI_quad #(
    parameter ADDRESS_LENGTH = 32,  // address is always 32 bit long
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH / 8,
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
    input                       i_last_word,
    input  [    STRB_WIDTH-1:0] i_data_word_mask,
    input  [    DATA_WIDTH-1:0] i_data_write,
    output [    DATA_WIDTH-1:0] o_data_read,
    output                      o_finish,
    output                      o_need_next_word,
    output                      o_recieved_next_word,

    // OctalSPI Pins
    output           o_bus_clock,
    output           o_bus_clock_neg,
    output reg [3:0] o_chip_select_neg,

    /* verilator lint_off UNUSEDSIGNAL */
    // the bits [3:1] are not used, because with the current setup we cannot react to the chips individually
    // for this we would need 4 seperated clocks
    // to fix this, we need to set the default delay of the chips to always be the same and not be dependant on the chip refresh.
    input  [3:0] i_data_strobe,
    /* verilator lint_on UNUSEDSIGNAL */
    output [3:0] o_data_strobe,
    output [3:0] o_data_strobe_output_enable, // 0 input, 1 output

    input [DATA_WIDTH-1:0] i_data,
    output [DATA_WIDTH-1:0] o_data,
    output [3:0] o_data_output_enable  // 0 input, 1 output
);

    // constants
    localparam BUS_WIDTH = 32;

    // Pin tristate stuff
    reg                    en_data_out_reg;
    reg                    en_data_out_nxt;
    reg  [BUS_WIDTH-1 : 0] data_out_reg;
    reg  [BUS_WIDTH-1 : 0] data_out_nxt;
    wire [BUS_WIDTH-1 : 0] data_in;

    wire                   en_data_strobe;
    reg  [ STRB_WIDTH-1:0] data_strobe_out_reg;
    reg  [ STRB_WIDTH-1:0] data_strobe_out_nxt;
    (* dont_touch = "true" *)
    wire                   data_strobe_in;
    reg                    recieved_next_word_reg;

    reg                    has_latency_reg;
    reg                    has_latency_nxt;

    assign o_data = data_out_reg;
    assign data_in = i_data;
    assign o_data_output_enable = {4{en_data_out_reg}};

    // Bus Clock
    reg bus_clock_reg;
    reg bus_clock_nxt;
    reg bus_clock_p2_reg;  // the bus clock has to be shifted a bit to guarantee that the data is present on the bus
    reg bus_clock_p2_nxt;

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
    reg     [    DATA_WIDTH-1:0] data_read_reg;
    reg                          need_next_word_nxt;
    reg                          need_next_word_reg;
    reg                          need_buffer_word_nxt;
    reg                          need_buffer_word_reg;

    assign o_data_read = data_read_reg;

    // constants
    localparam integer ADDRESS_CYCLES = 4;
    localparam integer OPCODE_CYCLES = 2;
    localparam INFINEON_LATENCY_CYCLES = 7;
    localparam APMEMORY_LATENCY_CYCLES = 5;
    // times two because of the two clock edges
    localparam integer LATENCY_CYCLES = (CHIP_TYPE == 1) ? INFINEON_LATENCY_CYCLES * 2 : APMEMORY_LATENCY_CYCLES * 2;    // ToDo think about a better switch (issue #12)
    // the first latency already begins after the sample point of the upper address
    // therefore we have to subtract one cycle (-2) from the latency
    localparam integer NUM_SHORT_LATENCY_CYCLES = (CHIP_TYPE == 1) ? LATENCY_CYCLES + 2 : LATENCY_CYCLES - 2;   // ToDo think about a better switch (issue #12)
    localparam integer NUM_LONG_LATENCY_CYCLES = LATENCY_CYCLES * 2 + 2;
    //localparam integer READ_LATENCY_IN_CYCLE = 1; // (issue #15)
    localparam integer TEMP_OPERATION_CYCLES = 1;   // transfer 2 bytes // ToDo: make dynamic handshake (issue #12)

    // ToDo: why was this in en_data_strobe?: | state_reg == WAIT_LATENCY 
    assign en_data_strobe  = (state_reg == SEND_DATA | (~i_config_read_data & (state_reg == CS_HIGH | state_reg == FINISH)));   // FINISH is needed, because otherwise the model does not store the value
    assign o_data_strobe = data_strobe_out_reg;
    assign data_strobe_in = i_data_strobe[0];   // ToDo: this is not perfect, because the chips may have different delays - better set them to fixed delay (issue #owas)
    assign o_data_strobe_output_enable = {4{en_data_strobe}};

    assign o_bus_clock = bus_clock_p2_reg;
    assign o_bus_clock_neg = ~bus_clock_p2_reg;
    assign o_finish = (state_reg == FINISH);
    assign o_recieved_next_word = recieved_next_word_reg;
    assign o_need_next_word = need_next_word_reg;


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

        // the read needs one more cycle after the latency until the memory puts out data
        // therefore +2
        latency_offset = (i_config_read_data) ? 1 : -1;     // ToDo change (issue #12)

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
                        has_latency_nxt = (CHIP_TYPE == 1) ? data_strobe_in : 1'b0;     // ToDo change (issue #12)
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
                    count_nxt = 1;
                    if (i_config_read_data) state_nxt = RECEIVE_DATA;
                    else if (i_config_write_data) state_nxt = SEND_DATA;
                    else state_nxt = CS_HIGH;
                end
            end

            RECEIVE_DATA: begin
                if (i_last_word) begin
                    state_nxt = CS_HIGH;
                end
            end

            SEND_DATA: begin
                count_nxt = 0;
                // we check the clock, because we always have to send two bytes
                // on the first byte sent out, the clock is always low  ToDo: (issue #12) maybe better description, maybe unnecessary because the clock shift is not needed?
                if (i_last_word & bus_clock_p2_reg & count_reg == 0) begin
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
            o_chip_select_neg <= 4'b1111;
            has_latency_reg <= 0;
            data_strobe_out_reg <= 0;
            en_data_out_reg <= 0;
        end else begin
            state_reg <= state_nxt;
            count_reg <= count_nxt;
            o_chip_select_neg <= {4{~(state_nxt != IDLE)}};  // state_nxt for perfect sync with state
            has_latency_reg <= has_latency_nxt;
            data_strobe_out_reg <= data_strobe_out_nxt;
            en_data_out_reg <= en_data_out_nxt;
        end
    end


    always @(*) begin : data_logic
        integer i, channel;
        data_out_nxt = data_out_reg;
        data_strobe_out_nxt = data_strobe_out_reg;
        need_buffer_word_nxt = need_buffer_word_reg;
        need_next_word_nxt = 1'b0;

        case (state_reg)
            SEND_OPCODE: begin
                for (channel = 0; channel < 4; channel = channel + 1) begin
                    for (i = 0; i < BUS_WIDTH; i = i + 1)
                    data_out_nxt[(channel*8)+i] = i_opcode[i[2:0]];
                end
            end

            SEND_ADDRESS: begin
                for (channel = 0; channel < 4; channel = channel + 1) begin
                    for (i = 0; i < BUS_WIDTH; i = i + 1)
                    data_out_nxt[(channel*8)+i] = i_address[{count_reg[1:0], i[2:0]}];
                end
            end

            // this could also be swapped to an combinatorial check for the state of SEND_DATA to assign to the output
            WAIT_LATENCY: begin
                if (i_config_write_data & count_reg == 0)
                need_next_word_nxt = 1'b1;
            end

            SEND_DATA: begin
                for (channel = 0; channel < 4; channel = channel + 1) begin
                    data_out_nxt[(channel*8)+:8] = i_data_write[(channel*8)+:8];
                    data_strobe_out_nxt[channel] = i_data_word_mask[channel];
                end
                need_next_word_nxt = 1'b1;
            end

            default: ;
        endcase
    end


    always @(posedge clk) begin : data_register
        if (~reset_neg) begin
            data_out_reg <= 0;
            recieved_next_word_reg <= 0;
            need_buffer_word_reg <= 0;
            need_next_word_reg <= 0;
        end else begin
            data_out_reg <= data_out_nxt;
            recieved_next_word_reg <= 1'b0;
            need_buffer_word_reg <= need_buffer_word_nxt;
            need_next_word_reg <= need_next_word_nxt;

            if (state_reg == RECEIVE_DATA) begin
                data_read_reg <= data_in;
                recieved_next_word_reg <= 1'b1;
            end
        end
    end


    // This is only force a valid value in the CHIP_TYPE parameter
    // generated by claude
    /* verilator lint_off MODMISSING */
    generate
        if (CHIP_TYPE != 1 && CHIP_TYPE != 2) begin : g_chip_check
            CHIP_must_be_set illegal_instance ();
        end

        if (DATA_WIDTH != 32) begin : g_data_width_check
            Data_width_must_be_32 illegal_instance ();
        end
    endgenerate
    /* verilator lint_on MODMISSING */
endmodule
