`timescale 1ns / 100ps
/*
OSPI Controller

Module to handle the SPI-Flash interface via the SPI transmitter.
What it does:
 - prepare the correct opcode for the transmitter based on axi read/write
 - send a write enable before sending a write command
 - multiplex configuration bits instead of data to the transmitter
 - multiplex the bytes to the transmitter based on the burst length
 - counts how many bytes are transfered
*/

module OctalSPIController #(
    parameter ADDRESS_LENGTH = 32,
    parameter DATA_WIDTH = 32,
    parameter DATA_BYTES = DATA_WIDTH / 8,
    parameter STRB_WIDTH = DATA_WIDTH / 8,
    parameter CHIP_TYPE = -1  // 1 is Infineon, 2 is APMemory
) (
    input clk,
    input reset_neg,
    input go,

    /* verilator lint_off UNUSEDSIGNAL */
    // the lower 2 bits are not used, because we always write a word at the moment
    input  [ADDRESS_LENGTH-1:0] i_address,
    /* verilator lint_on UNUSEDSIGNAL */
    input                       i_write_enable,
    input                       i_write_last_word,
    input                       i_write_valid,
    input  [    STRB_WIDTH-1:0] i_write_data_word_mask,
    input  [    DATA_WIDTH-1:0] i_write_data,
    output                      o_write_ready,

    input                       i_read_last_word,
    input                       i_read_ready,
    output [    DATA_WIDTH-1:0] o_read_data,
    output                      o_read_valid,

    output                      o_busy,

    // SPI Pins
    output o_bus_clock,
    output o_bus_clock_neg,
    output o_chip_select_neg,
    output o_reset_neg,

    input  i_spi_data_strobe,
    output o_spi_data_strobe,
    output o_spi_data_strobe_output_enable,

    input [7:0] i_spi_data,
    output [7:0] o_spi_data,
    output o_spi_data_output_enable
);

    // constants
    localparam integer OPCODE_LENGTH = 8;
    localparam DELAY_CYCLES = 10;
    localparam BYTE = 8;

    // Chip specific hardcoded constants
    localparam CONFIG_ADDRESS = 32'h00800002;
    localparam CONFIG_QSPI_ENABLE = 8'b00000010;

    // derived constants
    localparam DATA_BYTES_MSB = $clog2(DATA_BYTES);

    // Logic stuff
    reg  [   OPCODE_LENGTH-1:0] opcode_nxt;
    reg  [   OPCODE_LENGTH-1:0] opcode_reg;
    reg  [  ADDRESS_LENGTH-1:0] address_nxt;
    reg  [  ADDRESS_LENGTH-1:0] address_reg;
    reg  [      DATA_WIDTH-1:0] config_data_nxt;
    reg  [      DATA_WIDTH-1:0] config_data_reg;
    reg  [      DATA_WIDTH-1:0] data_in_muxed_nxt;
    reg  [      DATA_WIDTH-1:0] data_in_muxed_reg;
    reg  [      STRB_WIDTH-1:0] data_mask_nxt;
    reg  [      STRB_WIDTH-1:0] data_mask_reg;
    reg  [      DATA_WIDTH-1:0] data_read_reg;
    reg                         read_valid_reg;
    reg                         read_valid_nxt;
    wire                        start_transmission;
    wire                        transmitter_finish;
    wire                        spi_read_next_byte;
    reg  [DATA_BYTES_MSB-1 : 0] byte_index_nxt;
    reg  [DATA_BYTES_MSB-1 : 0] byte_index_reg;
    reg  [            BYTE-1:0] byte_pointer;
    reg                         byte_pointer_mask;
    wire [            BYTE-1:0] read_byte;
    wire                        read_ready;
    reg                         write_last_byte_nxt;
    reg                         write_last_byte_reg;
    reg                         read_last_byte_nxt;
    reg                         read_last_byte_reg;
    wire [  ADDRESS_LENGTH-1:0] word_alligned_address;

    // Data Bus
    reg  [    DATA_WIDTH-1 : 0] write_data_reg;
    reg  [      STRB_WIDTH-1:0] write_data_byte_mask_reg;
    reg                         write_valid_reg;
    reg                         write_last_word_reg;
    wire                        is_transmitter_write_ready;

    assign o_write_ready = (is_transmitter_write_ready && (byte_index_reg == DATA_BYTES_MSB'(DATA_BYTES - 1))) || !write_valid_reg;

    // Config stuff - ToDo: this should be later configured using a second port (issue #16)
    wire                        config_write_address;
    wire                        config_write_data;
    wire                        config_read_data;
    reg                         config_is_config_operation;

    // states control FSM
    localparam NUM_STATES = 6;
    localparam INDEX_STATES_MSB = $clog2(NUM_STATES) - 1;
    localparam [INDEX_STATES_MSB:0] IDLE = 0;
    localparam [INDEX_STATES_MSB:0] READ = 1;
    localparam [INDEX_STATES_MSB:0] WRITE_ENABLE = 2;
    localparam [INDEX_STATES_MSB:0] WRITE = 3;
    localparam [INDEX_STATES_MSB:0] WRITE_CONFIG = 4;
    localparam [INDEX_STATES_MSB:0] WAIT = 5;

    (* dont_touch = "true" *)
    reg [INDEX_STATES_MSB:0] control_state_reg;
    reg [INDEX_STATES_MSB:0] control_state_nxt;

    // Chip specific opcodes
    localparam INFINEON_CHIP = 1;
    //localparam APMEMORY_CHIP = 2;

    localparam [OPCODE_LENGTH -1 : 0] OPCODE_READ_INFINEON = 8'hEE;   // Infineon
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_READ_APMEMORY = 8'h20;   // AP Memory
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_READ = (CHIP_TYPE == INFINEON_CHIP) ? OPCODE_READ_INFINEON : OPCODE_READ_APMEMORY;
    
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE_INFINEON = 8'hDE;  // Infineon
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE_APMEMORY = 8'hA0;  // AP Memory
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE = (CHIP_TYPE == INFINEON_CHIP) ? OPCODE_WRITE_INFINEON : OPCODE_WRITE_APMEMORY;

    // Other opcodes
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE_ENABLE = 8'h06;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE_ANY_REG = 8'h00;
    //localparam [OPCODE_LENGTH -1 : 0] OPCODE_LONG_ADDRESS_ENABLE = 8'h00;

    assign o_read_valid = read_valid_reg;
    localparam WORD_LENGTH = $clog2(DATA_BYTES);
    assign word_alligned_address = {i_address[ADDRESS_LENGTH-1 : WORD_LENGTH], {WORD_LENGTH{1'b0}}};

    assign read_ready = i_read_ready || !read_valid_reg;

    // Temp counter for correct reset
    reg reset_neg_spi;
    assign o_reset_neg = reset_neg_spi;
    integer reset_counter;

    always @(posedge clk) begin
        if (!reset_neg) begin
            reset_counter <= 0;
            reset_neg_spi <= 0;
        end
        else begin
            if (reset_counter != 20000) begin
                reset_counter <= reset_counter + 1;
                reset_neg_spi <= 1'b0;
            end else reset_neg_spi <= 1'b1;
        end
    end


    OctalSPITransmitter #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH),
        .CHIP_TYPE(CHIP_TYPE)
    ) SPI_Transmitter (
        .clk(clk),
        .reset_neg(reset_neg),
        .start_transmission(start_transmission),

        .i_address(address_reg),
        .i_opcode(opcode_reg),
        .i_config_read_data(config_read_data),
        .i_config_write_data(config_write_data),
        .i_config_write_address(config_write_address),

        .i_write_last_byte(write_last_byte_reg),
        .i_write_valid(write_valid_reg),
        .i_write_data_byte_mask(byte_pointer_mask),
        .i_write_data(byte_pointer),
        .o_write_ready(is_transmitter_write_ready),

        .i_read_last_byte(read_last_byte_reg),
        .i_read_ready(read_ready),
        .o_read_data(read_byte),
        .o_read_valid(spi_read_next_byte),

        .o_finish(transmitter_finish),

        // SPI Pins
        .o_bus_clock(o_bus_clock),
        .o_bus_clock_neg(o_bus_clock_neg),
        .o_chip_select_neg(o_chip_select_neg),

        .i_spi_data_strobe(i_spi_data_strobe),
        .o_spi_data_strobe(o_spi_data_strobe),
        .o_spi_data_strobe_output_enable(o_spi_data_strobe_output_enable),

        .i_spi_data(i_spi_data),
        .o_spi_data(o_spi_data),
        .o_spi_data_output_enable(o_spi_data_output_enable)
    );


    assign start_transmission = (control_state_reg != IDLE && control_state_reg != WAIT);
    assign config_read_data = (control_state_reg == READ);
    assign config_write_data = (control_state_reg == WRITE || control_state_reg == WRITE_CONFIG);
    assign config_write_address = (control_state_reg == READ || control_state_reg == WRITE || control_state_reg == WRITE_CONFIG);
    assign o_busy = (control_state_reg != IDLE);
    assign o_read_data = data_read_reg;


    integer delay_fsm;  // ToDo: make this more beautifull - the state machine probably needs multiple delays. (issue #10)
    always @(*) begin : control_logic
        address_nxt = address_reg;
        opcode_nxt = opcode_reg;
        control_state_nxt = control_state_reg;

        case (control_state_reg)
            IDLE: begin
                if (go) begin
                    address_nxt = ADDRESS_LENGTH'(word_alligned_address);
                    opcode_nxt = (i_write_enable | config_is_config_operation) ? OPCODE_WRITE_ENABLE : OPCODE_READ;
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
        if (!reset_neg) begin
            control_state_reg <= IDLE;
            address_reg <= 0;
            opcode_reg <= 0;
            config_is_config_operation <= 1'b0;
            delay_fsm <= 0;
        end else begin
            address_reg <= address_nxt;
            opcode_reg <= opcode_nxt;
            control_state_reg <= control_state_nxt;
            delay_fsm <= 0;

            if (control_state_reg == WAIT) begin
                delay_fsm <= delay_fsm + 1;
            end
        end
    end


    always @(*) begin : data_logic
        byte_index_nxt = byte_index_reg;
        read_valid_nxt = read_valid_reg;
        data_in_muxed_nxt = data_in_muxed_reg;
        data_mask_nxt = data_mask_reg;
        write_last_byte_nxt = write_last_byte_reg;
        read_last_byte_nxt = read_last_byte_reg;
        config_data_nxt = config_data_reg;

        // select which byte is transfered to the transmitter
        byte_pointer      = write_data_reg[byte_index_reg*8+:8]; // ToDo: has to be muxed with config data (issue #14)
        byte_pointer_mask = write_data_byte_mask_reg[byte_index_reg];

        // ToDo: the read and write should be either exclusive through logic or independant through more registers (issue #14)
        if (read_ready && spi_read_next_byte) begin
            if (byte_index_reg == DATA_BYTES_MSB'(DATA_BYTES - 1)) begin
                byte_index_nxt = 0;
                read_valid_nxt = 1;
            end else begin
                byte_index_nxt = byte_index_reg + 1;
                read_valid_nxt = 0;
            end
        end

        // when the data is not valid, we do not advance the byte index
        if (is_transmitter_write_ready && write_valid_reg) begin
            if (byte_index_reg == DATA_BYTES_MSB'(DATA_BYTES - 1)) begin
                byte_index_nxt = 0;
            end else begin
                byte_index_nxt = byte_index_reg + 1;
            end
        end

        // using byte_index_nxt here is not good, since we use blocking assignments, the order of the assignments matter.
        // so using write_last_byte_reg would be better but then we need an magic -2 instead of -1
        // or we compare with an _reg +1
        if (write_last_word_reg == 1 && byte_index_nxt == DATA_BYTES_MSB'(DATA_BYTES - 1))
            write_last_byte_nxt = 1;
        
        if (i_read_last_word && byte_index_nxt == DATA_BYTES_MSB'(DATA_BYTES - 1))
            read_last_byte_nxt = 1;
        
        // This is shitty - think about the state machine of the data bus! (issue #14)
        if (control_state_reg == IDLE) begin
            write_last_byte_nxt = 0;
            read_last_byte_nxt = 0;
        end
    end

    // problem: when an unalligned read is done, some old data still resides in the read register
    // either it should be reset to 0 or masked out by the byte strobe thingy (issue #18)

    always @(posedge clk) begin : data_register
        data_in_muxed_reg <= data_in_muxed_nxt;
        data_mask_reg <= data_mask_nxt;
        byte_index_reg <= byte_index_nxt;
        read_valid_reg <= read_valid_nxt;
        write_last_byte_reg <= write_last_byte_nxt;
        read_last_byte_reg <= read_last_byte_nxt;
        config_data_reg <= config_data_nxt;
        data_read_reg <= data_read_reg;
        write_data_reg <= write_data_reg;
        write_data_byte_mask_reg <= write_data_byte_mask_reg;
        write_valid_reg <= write_valid_reg;
        write_last_word_reg <= write_last_word_reg;

        if (read_ready) begin
            data_read_reg[byte_index_reg*8+:8] <= read_byte;
        end

        if (o_write_ready) begin
            write_data_reg <= i_write_data;
            write_data_byte_mask_reg <= i_write_data_word_mask;
            write_valid_reg <= i_write_valid;
            write_last_word_reg <= i_write_last_word;
        end

        if (!reset_neg) begin
            data_in_muxed_reg <= 0;
            data_mask_reg <= 0;
            byte_index_reg <= 0;
            write_last_byte_reg <= 0;
            read_last_byte_reg <= 0;
            data_read_reg <= 0;
            read_valid_reg <= 0;
            config_data_reg <= {
                24'd0, CONFIG_QSPI_ENABLE
            };  // this is set only on reset - it should be more configurable (issue #16)
            // problem is, that on the go signal, the transmitter is started. So on the next clock edge it will sample the data.
            // if the config_data_nxt is set to the correct value, then it arrives a cycle late.

            write_data_reg <= 0;
            write_data_byte_mask_reg <= 0;
            write_valid_reg <= 0;
            write_last_word_reg <= 0;
        end
    end


endmodule
