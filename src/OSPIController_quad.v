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

module OSPIController_quad #(
    parameter ADDRESS_LENGTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH / 8,
    parameter CHIP_TYPE = -1  // 1 is Infineon, 2 is APMemory
) (
    input clk,
    input reset_neg,
    input go,

    /* verilator lint_off UNUSEDSIGNAL */
    // because we have 4 chips in parallel, we discard the lowest 2 bits and always write/read and use byte masking
    input  [ADDRESS_LENGTH-1:0] i_address,
    /* verilator lint_on UNUSEDSIGNAL */
    input                       i_write_enable,
    input                       i_last_word,

    input  [    STRB_WIDTH-1:0] i_data_word_mask,
    input  [    DATA_WIDTH-1:0] i_data_write,
    input                       i_data_write_valid,
    output                      o_data_write_ready,

    output                      o_data_read_valid,
    input                       i_data_read_ready,
    output [    DATA_WIDTH-1:0] o_data_read,
    
    output                      o_busy,

    // SPI Pins
    output o_bus_clock,
    output o_bus_clock_neg,
    output [3:0] o_chip_select_neg,
    output o_reset_neg,

    input  [3:0] i_data_strobe,
    output [3:0] o_data_strobe,
    output [3:0] o_data_strobe_output_enable, // 0 input, 1 output

    input [DATA_WIDTH-1:0] i_data,
    output [DATA_WIDTH-1:0] o_data,
    output [3:0] o_data_output_enable  // 0 input, 1 output
);

    // constants
    localparam integer OPCODE_LENGTH = 8;
    localparam DELAY_CYCLES = 10;

    // Chip specific hardcoded constants
    localparam CONFIG_ADDRESS = 32'h00800002;
    localparam CONFIG_QSPI_ENABLE = 8'b00000010;

    // Logic stuff
    reg  [ OPCODE_LENGTH-1:0] opcode_nxt;
    reg  [ OPCODE_LENGTH-1:0] opcode_reg;
    reg  [ADDRESS_LENGTH-1:0] address_nxt;
    reg  [ADDRESS_LENGTH-1:0] address_reg;
    reg  [    DATA_WIDTH-1:0] config_data_nxt;
    reg  [    DATA_WIDTH-1:0] config_data_reg;
    reg  [    DATA_WIDTH-1:0] data_in_muxed_nxt;
    reg  [    DATA_WIDTH-1:0] data_in_muxed_reg;
    reg                       data_in_valid_muxed_nxt;
    reg                       data_in_valid_muxed_reg;
    reg  [    STRB_WIDTH-1:0] data_mask_nxt;
    reg  [    STRB_WIDTH-1:0] data_mask_reg;
    reg  [    DATA_WIDTH-1:0] data_read_nxt;
    reg  [    DATA_WIDTH-1:0] data_read_reg;
    wire                      spi_read_ready;
    wire                      start_transmission;
    wire                      transmitter_finish;
    wire                      spi_write_next_byte;
    wire                      spi_read_next_byte;
    reg                       data_read_valid_nxt;
    reg                       data_read_valid_reg;
    reg                       last_word_nxt;
    reg                       last_word_reg;
    wire [    DATA_WIDTH-1:0] read_word;

    // Config stuff - ToDo: this should be later configured using a second port (issue #16)
    wire                      config_write_address;
    wire                      config_write_data;
    wire                      config_read_data;
    reg                       config_is_config_operation;

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

    localparam [OPCODE_LENGTH -1 : 0] OPCODE_READ_INFINEON = 8'hEE;  // Infineon
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_READ_APMEMORY = 8'h20;    // AP Memory    ToDo: cleanup (issue #12)
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_READ = (CHIP_TYPE == 1) ? OPCODE_READ_INFINEON : OPCODE_READ_APMEMORY;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE_ENABLE = 8'h06;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE_INFINEON = 8'hDE;  // Infineon
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE_APMEMORY = 8'hA0;  // AP Memory
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE = (CHIP_TYPE == 1) ? OPCODE_WRITE_INFINEON : OPCODE_WRITE_APMEMORY;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE_ANY_REG = 8'h00;
    //localparam [OPCODE_LENGTH -1 : 0] OPCODE_LONG_ADDRESS_ENABLE = 8'h00;

    assign o_data_write_ready = (~data_in_valid_muxed_reg || spi_write_next_byte);
    assign spi_read_ready = (~data_read_valid_reg || i_data_read_ready);
    assign o_data_read_valid  = data_read_valid_reg;

    // Temp counter for correct reset
    reg reset_spi;
    assign o_reset_neg = reset_spi;
    integer reset_counter;

    always @(posedge clk) begin
        if (!reset_neg) reset_counter <= 0;
        else begin
            if (reset_counter != 20000) begin
                reset_counter <= reset_counter + 1;
                reset_spi <= 1'b0;
            end else reset_spi <= 1'b1;
        end
    end


    OctalSPI_quad #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH),
        .DATA_WIDTH(DATA_WIDTH),
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

        .i_last_word(last_word_reg),
        .o_finish(transmitter_finish),

        .i_data_word_mask(data_mask_reg),
        .i_data_write(data_in_muxed_reg),
        .i_data_write_valid(data_in_valid_muxed_reg),
        .o_data_write_ready(spi_write_next_byte),

        .o_data_read(read_word),
        .o_data_read_valid(spi_read_next_byte),
        .i_data_read_ready(spi_read_ready),

        // SPI Pins
        .o_bus_clock(o_bus_clock),
        .o_bus_clock_neg(o_bus_clock_neg),
        .o_chip_select_neg(o_chip_select_neg),

        .i_data_strobe(i_data_strobe),
        .o_data_strobe(o_data_strobe),
        .o_data_strobe_output_enable(o_data_strobe_output_enable),

        .i_data(i_data),
        .o_data(o_data),
        .o_data_output_enable(o_data_output_enable)
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
                    address_nxt = i_address;
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
            config_is_config_operation <= 1'b0;
        end
    end


    // implementation of an adapted valid-handshake pipeline logic
    always @(*) begin : data_logic
        last_word_nxt = last_word_reg;
        data_in_muxed_nxt = data_in_muxed_reg;
        data_in_valid_muxed_nxt = data_in_valid_muxed_reg;
        data_mask_nxt = data_mask_reg;
        data_read_valid_nxt = 0;
        config_data_nxt = config_data_reg;
        data_read_nxt = data_read_reg;

        if (o_data_write_ready) begin
            if (~config_is_config_operation) begin
                last_word_nxt = i_last_word;
                data_in_muxed_nxt = i_data_write;
                data_in_valid_muxed_nxt = i_data_write_valid;
                data_mask_nxt = i_data_word_mask;
            end else begin
                last_word_nxt = 1'b1;  // only ever write one word for config
                data_in_muxed_nxt = config_data_reg;
                data_in_valid_muxed_nxt = 1'b1;
                data_mask_nxt = {STRB_WIDTH{1'b1}};  // always write all data
            end
        end

        if (i_data_read_ready) begin
            last_word_nxt = i_last_word;
            data_read_valid_nxt = spi_read_next_byte;
            data_read_nxt = read_word;
        end
    end

    // problem: when an unalligned read is done, some old data still resides in the read register
    // either it should be reset to 0 or masked out by the byte strobe thingy (issue #18)

    always @(posedge clk) begin : data_register
        data_in_muxed_reg <= data_in_muxed_nxt;
        data_in_valid_muxed_reg <= data_in_valid_muxed_nxt;
        data_mask_reg <= data_mask_nxt;
        last_word_reg <= last_word_nxt;
        data_read_valid_reg <= data_read_valid_nxt;
        config_data_reg <= config_data_nxt;
        data_read_reg <= data_read_nxt;

        if (!reset_neg) begin
            data_in_muxed_reg <= 0;
            data_in_valid_muxed_reg <= 0;
            data_mask_reg <= 0;
            last_word_reg <= 0;
            data_read_reg <= 0;
            data_read_valid_reg <= 0;
            config_data_reg <= {
                24'd0, CONFIG_QSPI_ENABLE
            };  // this is set only on reset - it should be more configurable (issue #16)
            // problem is, that on the go signal, the transmitter is started. So on the next clock edge it will sample the data.
            // if the config_data_nxt is set to the correct value, then it arrives a cycle late.
        end
    end


endmodule
