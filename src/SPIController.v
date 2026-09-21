`timescale 1ns / 100ps
/*
SPI Controller

Module to handle the SPI-Flash interface via the SPI transmitter.
What it does:
 - prepare the correct opcode for the transmitter based on axi read/write
 - send a write enable before sending a write command
 - multiplex configuration bits instead of data to the transmitter
 - multiplex the bytes to the transmitter based on the burst length
 - counts how many bytes are transfered
*/

module SPIController #(
    // Warining: the SPI flash chips start with a 24 bit address width.
    // ToDo: the automatic upgrade to 32bit address width is not yet implemented (issue #16)
    parameter ADDRESS_LENGTH = 24,
    parameter DATA_WIDTH = 32,
    parameter DATA_BYTES = DATA_WIDTH / 8,
    parameter MAX_NUM_BYTES = $clog2(256)
) (
    input clk,
    input reset_neg,
    input go,

    input  [ADDRESS_LENGTH-1:0] i_address,
    input                       i_write_enable,
    input                       i_last_word,
    input  [ MAX_NUM_BYTES-1:0] i_num_bytes,          // 0 based indexing
    input  [    DATA_WIDTH-1:0] i_data_write,
    output [    DATA_WIDTH-1:0] o_data_read,
    output                      o_busy,
    output                      o_next_word,
    output                      o_recieved_next_word,

    // SPI Pins
    output o_bus_clock,
    output o_chip_select_neg,
    output o_reset,
    inout  io_data0_manager_serial_out,
    inout  io_data1_manager_serial_in,
    inout  io_data2,
    inout  io_data3
);

    // constants
    localparam integer OPCODE_LENGTH = 8;
    localparam DELAY_CYCLES = 10;
    localparam BYTE = 8;
    localparam ARBITRARY_WIDTH = 32;

    // Chip specific hardcoded constants
    localparam CONFIG_ADDRESS = 32'h00800002;
    localparam CONFIG_QSPI_ENABLE = 8'b00000010;

    // Logic stuff
    reg  [    OPCODE_LENGTH-1:0] opcode_nxt;
    reg  [    OPCODE_LENGTH-1:0] opcode_reg;
    reg  [   ADDRESS_LENGTH-1:0] address_nxt;
    reg  [   ADDRESS_LENGTH-1:0] address_reg;
    reg  [       DATA_WIDTH-1:0] config_data_nxt;
    reg  [       DATA_WIDTH-1:0] config_data_reg;
    reg  [       DATA_WIDTH-1:0] data_in_muxed_nxt;
    reg  [       DATA_WIDTH-1:0] data_in_muxed_reg;
    reg  [       DATA_WIDTH-1:0] data_read_reg;
    wire                         start_transmission;
    wire                         transmitter_finish;
    wire                         spi_write_next_byte;
    wire                         spi_read_next_byte;
    reg                          write_next_word_nxt;
    reg                          write_next_word_reg;
    reg                          read_next_word_nxt;
    reg                          read_next_word_reg;
    reg  [ARBITRARY_WIDTH-1 : 0] byte_count_nxt;
    reg  [ARBITRARY_WIDTH-1 : 0] byte_count_reg;
    reg  [     DATA_BYTES-1 : 0] byte_index_nxt;
    reg  [     DATA_BYTES-1 : 0] byte_index_reg;
    reg  [             BYTE-1:0] byte_pointer;
    wire [             BYTE-1:0] read_byte;
    reg                          last_word_nxt;
    reg                          last_word_reg;

    // Config stuff - ToDo: this should be later configured using a second port (issue #16)
    wire                         config_write_address;
    wire                         config_write_data;
    wire                         config_read_data;
    reg  [                  2:0] config_quad_mode;
    reg  [                  4:0] config_dummy_cycles;
    reg                          config_is_config_operation;

    // states control FSM
    localparam NUM_STATES = 6;
    localparam INDEX_STATES_MSB = $clog2(NUM_STATES) - 1;
    localparam [INDEX_STATES_MSB:0] IDLE = 0;
    localparam [INDEX_STATES_MSB:0] READ = 1;
    localparam [INDEX_STATES_MSB:0] WRITE_ENABLE = 2;
    localparam [INDEX_STATES_MSB:0] WRITE = 3;
    localparam [INDEX_STATES_MSB:0] WRITE_CONFIG = 4;
    localparam [INDEX_STATES_MSB:0] WAIT = 5;

    reg [INDEX_STATES_MSB:0] control_state_reg;
    reg [INDEX_STATES_MSB:0] control_state_nxt;

    localparam [OPCODE_LENGTH -1 : 0] OPCODE_READ = 8'h03;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_READ_114 = 8'h6B;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE_ENABLE = 8'h06;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE = 8'h02;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE_ANY_REG = 8'h71;
    //localparam [OPCODE_LENGTH -1 : 0] OPCODE_LONG_ADDRESS_ENABLE = 8'hB7;

    assign o_reset = 1'b0;
    assign o_next_word = write_next_word_reg;
    assign o_recieved_next_word = read_next_word_reg;


    SPITransmitter #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH)
    ) SPI_Transmitter (
        .clk(clk),
        .reset_neg(reset_neg),
        .start_transmission(start_transmission),

        .i_address(address_reg),
        .i_opcode(opcode_reg),
        .i_config_read_data(config_read_data),
        .i_config_write_data(config_write_data),
        .i_config_write_address(config_write_address),
        .i_config_quad_mode(config_quad_mode),
        .i_last_word(last_word_reg),
        .i_config_dummy_cycles(config_dummy_cycles),    // ToDo: depending on the opcode, we need dummy cycles or not (issue #10)
        .i_data_write(byte_pointer),
        .o_data_read(read_byte),
        .o_finish(transmitter_finish),
        .o_need_next_byte(spi_write_next_byte),
        .o_recieved_next_byte(spi_read_next_byte),

        // SPI Pins
        .o_bus_clock(o_bus_clock),
        .o_chip_select_neg(o_chip_select_neg),
        .io_data0_manager_serial_out(io_data0_manager_serial_out),
        .io_data1_manager_serial_in(io_data1_manager_serial_in),
        .io_data2(io_data2),
        .io_data3(io_data3)
    );


    assign start_transmission = (control_state_reg != IDLE && control_state_reg != WAIT);
    assign config_read_data = (control_state_reg == READ);
    assign config_write_data = (control_state_reg == WRITE || control_state_reg == WRITE_CONFIG);
    assign config_write_address = (control_state_reg == READ || control_state_reg == WRITE || control_state_reg == WRITE_CONFIG);
    assign o_busy = (control_state_reg != IDLE);
    assign o_data_read = data_read_reg;


    integer delay_fsm;  // ToDo: make this more beautifull - the state machine probably needs multiple delays. (issue #10)
    always @(*) begin : control_logic
        address_nxt = address_reg;
        opcode_nxt = opcode_reg;
        control_state_nxt = control_state_reg;

        case (control_state_reg)
            IDLE: begin
                if (go) begin
                    address_nxt = ADDRESS_LENGTH'(i_address);
                    opcode_nxt = (i_write_enable | config_is_config_operation) ? OPCODE_WRITE_ENABLE : (config_quad_mode == 3'b000) ? OPCODE_READ : OPCODE_READ_114;
                    control_state_nxt = (i_write_enable | config_is_config_operation) ? WRITE_ENABLE : READ;

                    // ToDo: maybe this can be made more elegant (issue #10)
                    if (config_is_config_operation) begin
                        address_nxt = ADDRESS_LENGTH'(CONFIG_ADDRESS);
                    end
                end
            end

            READ: begin
                if (transmitter_finish) control_state_nxt = IDLE;
            end

            WRITE_ENABLE: begin
                if (transmitter_finish) begin
                    control_state_nxt = WAIT;
                end
            end

            WAIT: begin
                if (delay_fsm == DELAY_CYCLES) begin
                    control_state_nxt = (config_is_config_operation) ? WRITE_CONFIG : WRITE;
                    opcode_nxt = (config_is_config_operation) ? OPCODE_WRITE_ANY_REG : OPCODE_WRITE;
                end
            end

            WRITE: begin
                if (transmitter_finish) control_state_nxt = IDLE;
            end

            WRITE_CONFIG: begin
                if (transmitter_finish) control_state_nxt = IDLE;
            end

            default: control_state_nxt = IDLE;
        endcase

    end


    always @(posedge clk) begin : control_register
        address_reg <= address_nxt;
        opcode_reg <= opcode_nxt;
        control_state_reg <= control_state_nxt;
        delay_fsm <= 0;

        if (control_state_reg == WAIT) begin
            delay_fsm <= delay_fsm + 1;
        end

        if (!reset_neg) begin
            control_state_reg <= IDLE;
            address_reg <= 0;
            opcode_reg <= 0;
            config_quad_mode <= 3'b000;
            config_is_config_operation <= 1'b0;
            config_dummy_cycles <= 5'd0;
            config_data_reg <= 0;
        end
    end


    always @(*) begin : data_logic
        byte_index_nxt = byte_index_reg;
        byte_count_nxt = byte_count_reg;
        data_in_muxed_nxt = data_in_muxed_reg;
        last_word_nxt = last_word_reg;
        read_next_word_nxt = 0;
        write_next_word_nxt = 0;
        config_data_nxt = config_data_reg;

        // select which byte is transfered to the transmitter
        byte_pointer = data_in_muxed_reg[byte_index_reg*8+:8];

        // to get the first data byte
        if (control_state_reg == IDLE) begin
            if (go) begin
                data_in_muxed_nxt = (config_is_config_operation) ? config_data_reg : i_data_write;
                byte_count_nxt = (config_is_config_operation)? 0 : {{(ARBITRARY_WIDTH-MAX_NUM_BYTES){1'b0}}, i_num_bytes};
                byte_index_nxt = 0;
                last_word_nxt = 0;
            end
        end

        if (control_state_reg != IDLE & byte_count_reg == 0) last_word_nxt = 1;

        if (control_state_reg == WRITE | control_state_reg == READ | control_state_reg == WRITE_CONFIG) begin
            if (spi_write_next_byte | spi_read_next_byte) begin
                if (byte_index_reg == DATA_BYTES'(DATA_BYTES - 2)) write_next_word_nxt = 1;

                if (byte_index_reg == DATA_BYTES'(DATA_BYTES - 1) | byte_count_reg == 0) begin
                    byte_index_nxt = 0;
                    read_next_word_nxt = 1;
                end else byte_index_nxt = byte_index_reg + 1;

                data_in_muxed_nxt = (config_is_config_operation) ? config_data_reg : i_data_write;
                byte_count_nxt = byte_count_reg - 1;
            end
        end
    end

    // problem: when an unalligned read is done, some old data still resides in the read register
    // either it should be reset to 0 or masked out by the byte strobe thingy (issue #18)

    always @(posedge clk) begin : data_register
        data_in_muxed_reg <= data_in_muxed_nxt;
        byte_count_reg <= byte_count_nxt;
        byte_index_reg <= byte_index_nxt;
        last_word_reg <= last_word_nxt;
        read_next_word_reg <= read_next_word_nxt;
        write_next_word_reg <= write_next_word_nxt;
        config_data_reg <= config_data_nxt;

        if (spi_read_next_byte) begin
            data_read_reg[byte_index_reg*8+:8] <= read_byte;
        end

        if (!reset_neg) begin
            data_in_muxed_reg <= 0;
            byte_count_reg <= 0;
            byte_index_reg <= 0;
            last_word_reg <= 0;
            data_read_reg <= 0;
            read_next_word_reg <= 0;
            write_next_word_reg <= 0;
            config_data_reg <= {
                24'd0, CONFIG_QSPI_ENABLE
            };  // this is set only on reset - it should be more configurable (issue #16)
            // problem is, that on the go signal, the transmitter is started. So on the next clock edge it will sample the data.
            // if the config_data_nxt is set to the correct value, then it arrives a cycle late.
        end
    end


endmodule
