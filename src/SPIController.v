`timescale 1ns / 100ps

module SPIController #(
    // Warining: the SPI flash chips start with a 24 bit address width.
    // ToDo: the automatic upgrade to 32bit address width is not yet implemented
    parameter ADDRESS_LENGTH = 24,
    parameter DATA_WIDTH = 32
) (
    input clk,
    input reset_neg,
    input go,

    input  [ADDRESS_LENGTH-1:0] i_address,
    input                       i_write_enable,
    input  [    DATA_WIDTH-1:0] i_data_write,
    output [    DATA_WIDTH-1:0] o_data_read,
    output                      o_busy,

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

    // Chip specific hardcoded constants
    localparam CONFIG_ADDRESS = 32'h00800002;
    localparam CONFIG_QSPI_ENABLE = 8'b00000010;

    // Logic stuff
    reg  [ OPCODE_LENGTH-1:0] opcode_nxt;
    reg  [ OPCODE_LENGTH-1:0] opcode_reg;
    reg  [ADDRESS_LENGTH-1:0] address_nxt;
    reg  [ADDRESS_LENGTH-1:0] address_reg;
    reg  [    DATA_WIDTH-1:0] data_in_nxt;
    reg  [    DATA_WIDTH-1:0] data_in_reg;
    wire                      start_transmission;
    wire                      transmitter_finish;

    // Config stuff - ToDo: this should be later configured using a second port
    wire                      config_write_address;
    wire                      config_write_data;
    wire                      config_read_data;
    reg  [               2:0] config_quad_mode;
    reg  [               4:0] config_dummy_cycles;
    reg                       config_is_config_operation;

    // states control FSM
    localparam integer IDLE = 0;
    localparam integer READ = 1;
    localparam integer WRITE_ENABLE = 2;
    localparam integer WAIT = 4;
    localparam integer WRITE = 3;
    localparam integer WRITE_CONFIG = 5;

    integer control_state_reg;
    integer control_state_nxt;

    localparam [OPCODE_LENGTH -1 : 0] OPCODE_READ = 8'h03;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_READ_114 = 8'h6B;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE_ENABLE = 8'h06;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE = 8'h02;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE_ANY_REG = 8'h71;
    //localparam [OPCODE_LENGTH -1 : 0] OPCODE_LONG_ADDRESS_ENABLE = 8'hB7;

    assign o_reset = 1'b0;


    SPITransmitter #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH),
        .DATA_WIDTH(DATA_WIDTH)
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
        .i_num_bytes(0),
        .i_config_dummy_cycles(config_dummy_cycles),    // ToDo: depending on the opcode, we need dummy cycles or not
        .i_data_write(data_in_reg),
        .o_data_read(o_data_read),
        .o_finish(transmitter_finish),

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


    integer delay_fsm;  // ToDo: make this more beautifull - the state machine probably needs multiple delays.
    always @(*) begin : control_logic
        address_nxt = address_reg;
        opcode_nxt = opcode_reg;
        data_in_nxt = data_in_reg;
        control_state_nxt = control_state_reg;

        case (control_state_reg)
            IDLE: begin
                if (go) begin
                    address_nxt = ADDRESS_LENGTH'(i_address);
                    data_in_nxt = i_data_write;
                    opcode_nxt = (i_write_enable | config_is_config_operation) ? OPCODE_WRITE_ENABLE : (config_quad_mode == 3'b000) ? OPCODE_READ : OPCODE_READ_114;
                    control_state_nxt = (i_write_enable | config_is_config_operation) ? WRITE_ENABLE : READ;
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

                    if (config_is_config_operation) begin
                        address_nxt = ADDRESS_LENGTH'(CONFIG_ADDRESS);
                        data_in_nxt = CONFIG_QSPI_ENABLE;
                    end
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
        data_in_reg <= data_in_nxt;
        control_state_reg <= control_state_nxt;
        delay_fsm <= 0;

        if (control_state_reg == WAIT) begin
            delay_fsm <= delay_fsm + 1;
        end

        if (!reset_neg) begin
            address_reg <= 0;
            opcode_reg <= 0;
            config_quad_mode <= 3'b000;
            config_is_config_operation <= 1'b0;
            config_dummy_cycles <= 5'd0;
        end
    end


endmodule
