`timescale 1ns / 100ps

module SPIController (
    input clk,
    input reset_neg,
    input go,

    input  [31:0] i_address,
    input         i_write_enable,
    input  [15:0] i_data_write,
    output [15:0] o_data_read,
    output        o_busy,

    // SPI Pins
    output o_bus_clock,
    output o_chip_select_neg,
    output o_reset,
    inout  io_data0_manager_serial_in,
    inout  io_data1_manager_serial_out,
    inout  io_data2,
    inout  io_data3
);

    // constants
    localparam integer OPCODE_LENGTH = 8;
    localparam integer ADDRESS_LENGTH = 24;  // can also be 32

    // Logic stuff
    reg  [               7:0] opcode_nxt;
    reg  [               7:0] opcode_reg;
    reg  [ADDRESS_LENGTH-1:0] address_nxt;
    reg  [ADDRESS_LENGTH-1:0] address_reg;
    wire                      config_write_address;
    wire                      config_write_data;
    wire                      config_read_data;
    wire                      start_transmission;
    wire                      transmitter_finish;

    // states control FSM
    localparam integer IDLE = 0;
    localparam integer READ = 1;
    localparam integer WRITE_ENABLE = 2;
    localparam integer WAIT = 4;
    localparam integer WRITE = 3;

    integer control_state_reg;
    integer control_state_nxt;

    localparam [OPCODE_LENGTH -1 : 0] OPCODE_READ = 8'h03;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE_ENABLE = 8'h06;
    localparam [OPCODE_LENGTH -1 : 0] OPCODE_WRITE = 8'h02;

    assign o_reset = 1'b0;


    SPITransmitter SPI_Transmitter (
        .clk(clk),
        .reset_neg(reset_neg),
        .start_transmission(start_transmission),

        .i_address(address_reg),
        .i_opcode(opcode_reg),
        .i_config_read_data(config_read_data),
        .i_config_write_data(config_write_data),
        .i_config_write_address(config_write_address),
        .i_data_write(i_data_write),
        .o_data_read(o_data_read),
        .o_finish(transmitter_finish),

        // SPI Pins
        .o_bus_clock(o_bus_clock),
        .o_chip_select_neg(o_chip_select_neg),
        .io_data0_manager_serial_in(io_data0_manager_serial_in),
        .io_data1_manager_serial_out(io_data1_manager_serial_out),
        .io_data2(io_data2),
        .io_data3(io_data3)
    );


    assign start_transmission = (control_state_reg != IDLE && control_state_reg != WAIT);
    assign config_read_data = (control_state_reg == READ);
    assign config_write_data = (control_state_reg == WRITE);
    assign config_write_address = (control_state_reg == READ || control_state_reg == WRITE);
    assign o_busy = (control_state_reg != IDLE);


    integer delay_fsm;  // ToDo: make this more beautifull - the state machine probably needs multiple delays.
    always @(*) begin : control_logic
        address_nxt = address_reg;
        opcode_nxt = opcode_reg;
        control_state_nxt = control_state_reg;

        case (control_state_reg)
            IDLE: begin
                if (go) begin
                    address_nxt = ADDRESS_LENGTH'(i_address);   // ToDo: the code should run with the address width of the project.
                    opcode_nxt = (i_write_enable) ? OPCODE_WRITE_ENABLE : OPCODE_READ;
                    control_state_nxt = (i_write_enable) ? WRITE_ENABLE : READ;
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
                if (delay_fsm == 10) begin
                    control_state_nxt = WRITE;
                    opcode_nxt = OPCODE_WRITE;
                end
            end

            WRITE: begin
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
            address_reg <= 0;
            opcode_reg  <= 0;
        end
    end


endmodule
