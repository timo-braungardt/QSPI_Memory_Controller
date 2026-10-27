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
    output [    DATA_WIDTH-1:0] o_data_read,
    output                      o_busy,
    output                      o_next_word,
    output                      o_recieved_next_word,

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
    reg  [    STRB_WIDTH-1:0] data_mask_nxt;
    reg  [    STRB_WIDTH-1:0] data_mask_reg;
    reg  [    DATA_WIDTH-1:0] data_read_reg;
    wire                      start_transmission;
    wire                      transmitter_finish;
    wire                      spi_write_next_byte;
    wire                      spi_read_next_byte;
    reg                       write_next_word_nxt;
    reg                       write_next_word_reg;
    reg                       read_next_word_nxt;
    reg                       read_next_word_reg;
    reg                       last_word_nxt;
    reg                       last_word_reg;
    wire [    DATA_WIDTH-1:0] read_word;
    reg                       last_byte_nxt;
    reg                       last_byte_reg;

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

    assign o_next_word = (write_next_word_reg | spi_write_next_byte);
    assign o_recieved_next_word = read_next_word_reg;

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
        .i_last_word(last_byte_reg),
        .i_data_word_mask(data_mask_reg),
        .i_data_write(data_in_muxed_reg),
        .o_data_read(read_word),
        .o_finish(transmitter_finish),
        .o_need_next_word(spi_write_next_byte),
        .o_recieved_next_word(spi_read_next_byte),

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


    always @(*) begin : data_logic
        last_word_nxt = last_word_reg;
        data_in_muxed_nxt = data_in_muxed_reg;
        data_mask_nxt = data_mask_reg;
        last_byte_nxt = last_byte_reg;
        read_next_word_nxt = 0;
        write_next_word_nxt = 0;
        config_data_nxt = config_data_reg;

        // to get the first data byte
        if (control_state_reg == IDLE) begin
            if (go) begin
                data_in_muxed_nxt = (config_is_config_operation) ? config_data_reg : i_data_write;
                data_mask_nxt = i_data_word_mask;
                write_next_word_nxt = 1;    // save the data and request the next data on the bus
                last_word_nxt = (config_is_config_operation) ? 1'b1 : i_last_word;
                last_byte_nxt = 0;
            end
        end

        if (control_state_reg != IDLE & (last_word_reg == 1)) last_byte_nxt = 1;

        if (control_state_reg == WRITE | control_state_reg == READ | control_state_reg == WRITE_CONFIG) begin
            if (spi_write_next_byte | spi_read_next_byte) begin
                write_next_word_nxt = 1;     // ToDo: the DATA_BYTES can make problems, when it is too small (issue #10)

                read_next_word_nxt = 1;

                data_in_muxed_nxt = (config_is_config_operation) ? config_data_reg : i_data_write;
                data_mask_nxt = i_data_word_mask;
                last_word_nxt = i_last_word;
            end
        end
    end

    // problem: when an unalligned read is done, some old data still resides in the read register
    // either it should be reset to 0 or masked out by the byte strobe thingy (issue #18)

    always @(posedge clk) begin : data_register
        data_in_muxed_reg <= data_in_muxed_nxt;
        data_mask_reg <= data_mask_nxt;
        last_word_reg <= last_word_nxt;
        last_byte_reg <= last_byte_nxt;
        read_next_word_reg <= read_next_word_nxt;
        write_next_word_reg <= write_next_word_nxt;
        config_data_reg <= config_data_nxt;

        if (spi_read_next_byte & ~last_byte_reg) begin
            data_read_reg <= read_word;
        end

        if (!reset_neg) begin
            data_in_muxed_reg <= 0;
            data_mask_reg <= 0;
            last_word_reg <= 0;
            last_byte_reg <= 0;
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
