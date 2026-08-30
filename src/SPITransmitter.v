`timescale 1ns / 100ps

module SPITransmitter #(
    parameter ADDRESS_LENGTH = 24,
    parameter DATA_WIDTH = 32
) (
    input clk,
    input reset_neg,
    input start_transmission,

    input  [ADDRESS_LENGTH-1:0] i_address,
    input  [               7:0] i_opcode,
    input                       i_config_read_data,
    input                       i_config_write_data,
    input                       i_config_write_address,
    input  [               2:0] i_config_quad_mode,
    input  [(DATA_WIDTH/8)-1:0] i_num_bytes,    // 0 based indexing
    input  [               4:0] i_config_dummy_cycles,
    input  [    DATA_WIDTH-1:0] i_data_write,
    output [    DATA_WIDTH-1:0] o_data_read,
    output                      o_finish,

    // SPI Pins
    output o_bus_clock,
    output reg o_chip_select_neg,
    inout io_data0_manager_serial_out,
    inout io_data1_manager_serial_in,
    inout io_data2,
    inout io_data3
);

    // constants
    localparam integer TIMER_COUNT = 2;
    localparam integer OPCODE_LENGTH = 8;
    localparam BITS_PER_SHIFT = 4;
    localparam BYTE = 8;
    localparam DATA_SEL_MSB_QUAD = $clog2(DATA_WIDTH / BITS_PER_SHIFT) - 1;
    localparam DATA_SEL_MSB_SINGLE = $clog2(DATA_WIDTH) - 1;
    localparam BYTE_SEL_LSB_SINGLE = $clog2(BYTE);
    localparam BYTE_SEL_MSB_SINGLE = $clog2(DATA_WIDTH);
    localparam BYTE_SEL_LSB_QUAD = $clog2(BYTE / BITS_PER_SHIFT);
    localparam BYTE_SEL_MSB_QUAD = $clog2(DATA_WIDTH / BITS_PER_SHIFT);
    localparam ADDRESS_SEL_MSB_QUAD = $clog2(ADDRESS_LENGTH / BITS_PER_SHIFT) - 1;
    localparam ADDRESS_SEL_MSB_SINGLE = $clog2(ADDRESS_LENGTH) - 1;
    localparam BUS_WIDTH = 4;
    localparam BUS_WIDTH_MSB = BUS_WIDTH - 1;
    localparam QUAD_MODE_OPCODE = 2;
    localparam QUAD_MODE_ADDRESS = 1;
    localparam QUAD_MODE_DATA = 0;

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
    wire                      is_output_quad_mode;
    integer                   state_reg;
    integer                   state_nxt;

    integer                   count_reg;
    integer                   count_nxt;
    wire                      clock_tick_pos;
    wire                      clock_tick_neg;
    reg                       transmission_finished_nxt;
    reg                       transmission_finished_reg;

    reg     [ DATA_WIDTH-1:0] data_read_reg;
    assign o_data_read = data_read_reg;

    // ToDo: what should the size be? currently log(8 bits * 4 bytes)
    wire [4:0] transmission_num_cycles_single;
    assign transmission_num_cycles_single = (i_num_bytes + 1) * 8 - 1;  // for 8 bits we need 8 cycles
    wire [4:0] transmission_num_cycles;
    assign transmission_num_cycles = (i_num_bytes + 1) * 2 - 1;     // for 8 bits we need 2 cycles
    wire [BYTE -1:0] data_write_selected_byte;
    assign data_write_selected_byte = i_data_write[count_reg[BYTE_SEL_MSB_SINGLE:BYTE_SEL_LSB_SINGLE]*8 +: 8];
    wire [BYTE -1:0] data_write_selected_byte_quad;
    assign data_write_selected_byte_quad = i_data_write[count_reg[BYTE_SEL_MSB_QUAD:BYTE_SEL_LSB_QUAD]*8 +: 8];

    // states transmission FSM
    localparam integer IDLE = 0;
    localparam integer SEND_OPCODE = 1;
    localparam integer SEND_ADDRESS = 2;
    localparam integer DUMMY_CYCLES = 6;
    localparam integer SEND_DATA = 3;
    localparam integer RECEIVE_DATA = 4;
    localparam integer FINISH = 5;

    assign en_bus_clock   = (state_reg != IDLE);
    assign clock_tick_pos = (clock_count_reg == 0 && ~clk_bus_reg);
    assign clock_tick_neg = (clock_count_reg == 0 && clk_bus_reg);
    assign en_data_out    = (state_reg != IDLE && state_reg != RECEIVE_DATA && state_reg != FINISH);

    assign o_bus_clock    = (en_bus_clock) ? clk_bus_reg : 1'b0;
    assign is_output_quad_mode = (i_config_quad_mode[QUAD_MODE_OPCODE] && state_reg == SEND_OPCODE ||
                                  i_config_quad_mode[QUAD_MODE_ADDRESS] && state_reg == SEND_ADDRESS ||
                                  i_config_quad_mode[QUAD_MODE_DATA] && (state_reg == SEND_DATA));  // revieve is handled by the tristate, not necessary here


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


    assign o_finish = (state_reg == FINISH);

    always @(*) begin : transmission_logic
        state_nxt = state_reg;
        count_nxt = count_reg;
        transmission_finished_nxt = 0;

        case (state_reg)
            IDLE: begin
                if (start_transmission) begin
                    state_nxt = SEND_OPCODE;
                    count_nxt = (i_config_quad_mode[QUAD_MODE_OPCODE]) ? OPCODE_LENGTH / BITS_PER_SHIFT - 1 : OPCODE_LENGTH - 1;
                end
            end

            SEND_OPCODE: begin
                if (clock_tick_neg) begin
                    count_nxt = count_reg - 1;
                    if (count_reg == 0) begin
                        if (i_config_write_address) begin
                            count_nxt = (i_config_quad_mode[QUAD_MODE_ADDRESS]) ? ADDRESS_LENGTH / BITS_PER_SHIFT - 1 : ADDRESS_LENGTH - 1;
                            state_nxt = SEND_ADDRESS;
                        end else if (i_config_dummy_cycles != 0) begin
                            count_nxt = {27'd0, i_config_dummy_cycles - 5'd1};
                            state_nxt = DUMMY_CYCLES;
                        end else if (i_config_write_data) begin
                            count_nxt = (i_config_quad_mode[QUAD_MODE_DATA]) ? {27'd0, transmission_num_cycles} : {27'd0, transmission_num_cycles_single};
                            state_nxt = SEND_DATA;
                        end else if (i_config_read_data) begin
                            count_nxt = (i_config_quad_mode[QUAD_MODE_DATA]) ? {27'd0, transmission_num_cycles} : {27'd0, transmission_num_cycles_single};
                            state_nxt = RECEIVE_DATA;
                        end else state_nxt = FINISH;
                    end
                end
            end

            SEND_ADDRESS: begin
                if (clock_tick_neg) count_nxt = count_reg - 1;

                if (count_reg == 0 && clock_tick_neg) begin
                    count_nxt = (i_config_quad_mode[QUAD_MODE_DATA]) ? {27'd0, transmission_num_cycles} : {27'd0, transmission_num_cycles_single};
                    if (i_config_dummy_cycles != 0) begin
                            count_nxt = {27'd0, i_config_dummy_cycles - 5'd1};
                        state_nxt = DUMMY_CYCLES;
                    end else if (i_config_write_data) state_nxt = SEND_DATA;
                    else if (i_config_read_data) state_nxt = RECEIVE_DATA;
                    else state_nxt = FINISH;
                end
            end

            DUMMY_CYCLES: begin
                if (clock_tick_neg) count_nxt = count_reg - 1;

                if (count_reg == 0 && clock_tick_neg) begin
                    count_nxt = (i_config_quad_mode[QUAD_MODE_DATA]) ? {27'd0, transmission_num_cycles} : {27'd0, transmission_num_cycles_single};
                    if (i_config_write_data) state_nxt = SEND_DATA;
                    else if (i_config_read_data) state_nxt = RECEIVE_DATA;
                    else
                        state_nxt = FINISH;    // note: this path to finish should not be possible, it does not require dummy cycles
                end
            end

            RECEIVE_DATA: begin
                if (clock_tick_pos) begin
                    count_nxt = count_reg - 1;
                end

                transmission_finished_nxt = (count_reg == 0 & clock_tick_neg) || transmission_finished_reg;
                if (transmission_finished_reg & clock_tick_neg) begin
                    state_nxt = FINISH;
                end
            end

            SEND_DATA: begin
                if (clock_tick_neg) begin
                    count_nxt = count_reg - 1;
                end

                transmission_finished_nxt = (count_reg == 0 & clock_tick_pos) || transmission_finished_reg;
                if (transmission_finished_reg & clock_tick_neg) begin
                    state_nxt = FINISH;
                end
            end

            FINISH: state_nxt = IDLE;

            default: state_nxt = IDLE;
        endcase
    end


    always @(posedge clk) begin : transmission_register
        if (!reset_neg) begin
            state_reg <= IDLE;
            count_reg <= 0;
            o_chip_select_neg <= 1'b1;
            transmission_finished_reg <= 0;
        end else begin
            state_reg <= state_nxt;
            count_reg <= count_nxt;
            o_chip_select_neg <= ~(state_reg != IDLE);  // state_nxt possible for perfect sync with state
            transmission_finished_reg <= transmission_finished_nxt;
        end
    end


    assign io_data0_manager_serial_out  = (~en_data_out) ? 1'bZ : data_out_reg[0];
    assign io_data1_manager_serial_in = (~en_data_out) ? 1'bZ : (is_output_quad_mode) ? data_out_reg[1] : 1'bZ;
    assign io_data2 = (~en_data_out) ? 1'bZ : (is_output_quad_mode) ? data_out_reg[2] : 1'bZ;
    assign io_data3 = (~en_data_out) ? 1'bZ : (is_output_quad_mode) ? data_out_reg[3] : 1'bZ;

    wire [ADDRESS_SEL_MSB_QUAD:0] index_address_quad_mode = count_reg[ADDRESS_SEL_MSB_QUAD:0];
    wire [ADDRESS_SEL_MSB_SINGLE:0] index_address_single_mode = count_reg[ADDRESS_SEL_MSB_SINGLE:0];
    wire index_data_send_quad_mode = count_reg[BYTE_SEL_LSB_QUAD-1];
    wire [BYTE_SEL_LSB_SINGLE-1:0] index_data_send_single_mode = count_reg[BYTE_SEL_LSB_SINGLE-1:0];

    always @(*) begin : data_logic
        data_out_nxt = data_out_reg;

        data_in[0]   = io_data0_manager_serial_out;
        data_in[1]   = io_data1_manager_serial_in;
        data_in[2]   = io_data2;
        data_in[3]   = io_data3;

        case (state_reg)
            SEND_OPCODE: begin
                if (i_config_quad_mode[QUAD_MODE_OPCODE]) begin
                    data_out_nxt[0] = i_opcode[{count_reg[0], 2'd0}];
                    data_out_nxt[1] = i_opcode[{count_reg[0], 2'd1}];
                    data_out_nxt[2] = i_opcode[{count_reg[0], 2'd2}];
                    data_out_nxt[3] = i_opcode[{count_reg[0], 2'd3}];
                end else begin
                    data_out_nxt[0] = i_opcode[count_reg[2:0]];
                end
            end

            SEND_ADDRESS: begin
                if (i_config_quad_mode[QUAD_MODE_ADDRESS]) begin
                    data_out_nxt[0] = i_address[{index_address_quad_mode, 2'd0}];
                    data_out_nxt[1] = i_address[{index_address_quad_mode, 2'd1}];
                    data_out_nxt[2] = i_address[{index_address_quad_mode, 2'd2}];
                    data_out_nxt[3] = i_address[{index_address_quad_mode, 2'd3}];
                end else begin
                    data_out_nxt[0] = i_address[index_address_single_mode];
                end
            end

            SEND_DATA: begin
                if (i_config_quad_mode[QUAD_MODE_DATA]) begin
                    data_out_nxt[0] = data_write_selected_byte_quad[{index_data_send_quad_mode, 2'd0}];
                    data_out_nxt[1] = data_write_selected_byte_quad[{index_data_send_quad_mode, 2'd1}];
                    data_out_nxt[2] = data_write_selected_byte_quad[{index_data_send_quad_mode, 2'd2}];
                    data_out_nxt[3] = data_write_selected_byte_quad[{index_data_send_quad_mode, 2'd3}];
                end else begin
                    data_out_nxt[0] = data_write_selected_byte[index_data_send_single_mode];
                end
            end
        endcase
    end


    wire [DATA_SEL_MSB_QUAD:0] index_data_recieve_quad_mode = count_reg[DATA_SEL_MSB_QUAD:0];
    wire [DATA_SEL_MSB_SINGLE:0] index_data_recieve_single_mode = count_reg[DATA_SEL_MSB_SINGLE:0];

    always @(posedge clk) begin : data_register
        if (!reset_neg) begin
            data_out_reg <= 0;
            data_read_reg <= 0;
        end else begin
            data_out_reg <= data_out_nxt;

            if (state_reg == RECEIVE_DATA && clock_tick_pos) begin
                if (i_config_quad_mode[QUAD_MODE_DATA]) begin
                    data_read_reg[{index_data_recieve_quad_mode, 2'd0}] <= data_in[0];
                    data_read_reg[{index_data_recieve_quad_mode, 2'd1}] <= data_in[1];
                    data_read_reg[{index_data_recieve_quad_mode, 2'd2}] <= data_in[2];
                    data_read_reg[{index_data_recieve_quad_mode, 2'd3}] <= data_in[3];
                end else begin
                    data_read_reg[index_data_recieve_single_mode] <= data_in[1];
                end
            end
        end
    end


endmodule
