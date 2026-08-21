`timescale 1ns / 100ps

module SPITransmitter (
    input clk,
    input reset_neg,
    input go,

    input [31:0]    i_address,
    input           i_write_enable,
    input [15:0]    i_data_write,
    output[15:0]    o_data_read,
    output          o_busy,

    // SPI Pins
    output o_bus_clock,
    output reg o_chip_select_neg,
    output o_reset,
    inout io_data0_manager_serial_in,
    inout io_data1_manager_serial_out,
    inout io_data2,
    inout io_data3
);

    // constants
    localparam integer TIMER_COUNT = 2;
    localparam integer OPCODE_LENGTH = 8;
    localparam integer ADDRESS_LENGTH = 24;  // can also be 32
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
    reg     [               7:0] opcode_nxt;
    reg     [               7:0] opcode_reg;
    reg     [ADDRESS_LENGTH-1:0] address_nxt;
    reg     [ADDRESS_LENGTH-1:0] address_reg;
    wire                       config_write_address;
    wire                       config_write_data;
    wire                       config_read_data;
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
    wire                      start_transmission;

    reg     [            7:0] buffer                    [0:BUFFER_SIZE -1];
    assign o_data_read = {buffer[0], buffer[1]};

    // states transmission FSM
    localparam integer IDLE = 0;
    localparam integer SEND_OPCODE = 1;
    localparam integer SEND_ADDRESS = 2;
    localparam integer SEND_DATA = 3;
    localparam integer RECEIVE_DATA = 4;
    localparam integer FINISH = 5;

    // states control FSM
    localparam integer C_IDLE = 0;
    localparam integer C_READ = 1;
    localparam integer C_WRITE_ENABLE = 2;
    localparam integer C_WAIT = 4;
    localparam integer C_WRITE = 3;

    integer control_state_reg;
    integer control_state_nxt;

    localparam [OPCODE_LENGTH -1 : 0] OPCODE_READ           = 8'h03;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE_ENABLE   = 8'h06;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE          = 8'h02;

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


    assign start_transmission = (control_state_reg != C_IDLE && control_state_reg != C_WAIT);
    assign config_read_data = (control_state_reg == C_READ);
    assign config_write_data = (control_state_reg == C_WRITE);
    assign config_write_address = (control_state_reg == C_READ || control_state_reg == C_WRITE);
    assign o_busy = (control_state_reg != IDLE);

    integer delay_fsm;  // ToDo: make this more beautifull - the state machine probably needs multiple delays.
    always @(*) begin : control_logic
        address_nxt = address_reg;
        opcode_nxt = opcode_reg;
        control_state_nxt = control_state_reg;
        
        case (control_state_reg)
            C_IDLE: begin
                if (go) begin
                    address_nxt = ADDRESS_LENGTH'(i_address);   // ToDo: the code should run with the address width of the project.
                    opcode_nxt = (i_write_enable) ? OPCODE_WRITE_ENABLE : OPCODE_READ;
                    control_state_nxt = (i_write_enable) ? C_WRITE_ENABLE : C_READ;
                end
            end

            C_READ: begin
                if (state_reg == FINISH)
                control_state_nxt = C_IDLE;
            end

            C_WRITE_ENABLE: begin
                if (state_reg == FINISH) begin
                    control_state_nxt = C_WAIT;
                end
            end

            C_WAIT: begin
                if (delay_fsm == 10) begin
                control_state_nxt = C_WRITE;
                opcode_nxt = OPCODE_WRITE;
                end
            end

            C_WRITE: begin
                if (state_reg == FINISH)
                control_state_nxt = C_IDLE;
            end

            default: control_state_nxt = C_IDLE;
        endcase
        
    end


    always @(posedge clk) begin : control_register
        address_reg <= address_nxt;
        opcode_reg <= opcode_nxt;
        control_state_reg <= control_state_nxt;
        delay_fsm <= 0;

        if (control_state_reg == C_WAIT) begin
            delay_fsm <= delay_fsm +1;
        end

        if (!reset_neg) begin
            address_reg <= 0;
            opcode_reg <= 0;
        end
    end


    always @(*) begin : transmission_logic
        state_nxt = state_reg;
        count_nxt = count_reg;
        buffer_count_nxt = buffer_count_reg;
        transmission_finished_nxt = 0;

        case (state_reg)
            IDLE: begin
                if (start_transmission) begin
                    state_nxt = SEND_OPCODE;
                    count_nxt = (is_quad_mode) ? OPCODE_LENGTH / BITS_PER_SHIFT - 1 : OPCODE_LENGTH - 1;
                end
            end

            SEND_OPCODE: begin
                if (clock_tick_neg) begin
                    count_nxt = count_reg - 1;
                    if (count_reg == 0) begin
                        if (config_write_address) begin
                            count_nxt = (is_quad_mode) ? ADDRESS_LENGTH / BITS_PER_SHIFT - 1 : ADDRESS_LENGTH - 1;
                            state_nxt = SEND_ADDRESS;
                        end else if (config_write_data) begin
                            count_nxt = (is_quad_mode) ? num_bits / BITS_PER_SHIFT - 1 : num_bits - 1;
                            state_nxt = SEND_DATA;
                        end else if (config_read_data) begin
                            count_nxt = (is_quad_mode) ? num_bits / BITS_PER_SHIFT - 1 : num_bits - 1;
                            buffer_count_nxt = 0;
                            state_nxt = RECEIVE_DATA;
                        end else state_nxt = FINISH;
                    end
                end
            end

            SEND_ADDRESS: begin
                if (clock_tick_neg) count_nxt = count_reg - 1;

                if (count_reg == 0 && clock_tick_neg) begin
                    count_nxt = (is_quad_mode) ? num_bits / BITS_PER_SHIFT - 1 : num_bits - 1;
                    buffer_count_nxt = 0;
                    if (config_write_data) state_nxt = SEND_DATA;
                    else if (config_read_data) state_nxt = RECEIVE_DATA;
                    else state_nxt = FINISH;
                end
            end

            RECEIVE_DATA: begin
                if (clock_tick_pos) begin
                    count_nxt = count_reg - 1;
                    buffer_count_nxt = buffer_count_reg + 1;
                end

                transmission_finished_nxt = (count_reg == 0 & clock_tick_neg) || transmission_finished_reg;
                if (transmission_finished_reg & clock_tick_neg) begin
                    state_nxt = FINISH;
                end
            end

            SEND_DATA: begin
                if (clock_tick_neg) begin
                    count_nxt = count_reg - 1;
                    buffer_count_nxt = buffer_count_reg + 1;
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
                    data_out_nxt[0] = opcode_reg[{count_reg[0], 2'd0}];
                    data_out_nxt[1] = opcode_reg[{count_reg[0], 2'd1}];
                    data_out_nxt[2] = opcode_reg[{count_reg[0], 2'd2}];
                    data_out_nxt[3] = opcode_reg[{count_reg[0], 2'd3}];
                end else begin
                    data_out_nxt[0] = opcode_reg[count_reg[2:0]];
                end
            end

            SEND_ADDRESS: begin
                if (is_quad_mode) begin
                    data_out_nxt[0] = address_reg[{count_reg[2:0], 2'd0}];
                    data_out_nxt[1] = address_reg[{count_reg[2:0], 2'd1}];
                    data_out_nxt[2] = address_reg[{count_reg[2:0], 2'd2}];
                    data_out_nxt[3] = address_reg[{count_reg[2:0], 2'd3}];
                end else begin
                    data_out_nxt[0] = address_reg[count_reg[4:0]];
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
                    data_out_nxt[0] = i_data_write[count_reg[3:0]];
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
            num_bits <= 32;
            is_quad_mode <= 1'b1;
        end
    end


endmodule
