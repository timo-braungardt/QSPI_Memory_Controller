`timescale 1ns/100ps

module BasicSPI (
    input clk,
    input go,
    
    // SPI Pins
    output o_SpiClk,
    output reg o_ChipSelect_neg,
    output o_Reset,
    inout io_ManagerSerialIn,
    inout io_ManagerSerialOut
);

// Pin tristate stuff
reg  enClk;
reg  enSerialOut;
reg  SerialOut;
wire SerialIn;

assign o_SpiClk =            (enClk)        ? clk       : 1'b0;
assign io_ManagerSerialOut = (enSerialOut)  ? SerialOut : 1'bZ;
assign SerialIn =            io_ManagerSerialIn;

// Logic stuff
reg  [7:0] opcode;
reg [23:0] address;
integer state;

// states
parameter integer idle          = 0;
parameter integer cl_low        = 5;
parameter integer send_opcode_first_bit = 6;
parameter integer send_opcode_last_bit = 7;
parameter integer send_opcode   = 1;
parameter integer send_address  = 2;
parameter integer send_data     = 3;
parameter integer recieve_data  = 4;


initial begin : setup_registers
    opcode      <= 0;
    address     <= 0;
    enClk       <= 0;
    enSerialOut <= 0;
    SerialOut   <= 0;
    state       <= 0;
    o_ChipSelect_neg <= 1'b1;
end

integer count = 0;
always @(negedge clk) begin : sm_logic
    case (state)
        idle : begin
            o_ChipSelect_neg <= 1'b1;
            enClk <= 1'b0;
            if (go) state <= cl_low;
        end

        cl_low : begin
            o_ChipSelect_neg <= 1'b0;
            count <= 7;
            enSerialOut <= 1'b1;
            state <= send_opcode;
        end

        send_opcode : begin
            enClk <= 1'b1;

            SerialOut <= opcode[count];
            count <= count -1;
            if (count == 0) begin
                count <= 23; // otherwise underflow - can this be synthesised elegantly?
                state <= send_address;
            end
        end

        send_address : begin
            SerialOut <= address[count];
            count <= count -1;

            if (count == 0) begin
                count <= 31;
                state <= recieve_data;
            end
        end

        recieve_data : begin
            count <= count -1;
            if (count == 0) begin
                count <= 0; // otherwise underflow - can this be synthesised elegantly?
                state <= idle;
                o_ChipSelect_neg <= 1'b1;
            end
        end 

        default : 
            state <= idle;
    endcase
end
    
endmodule
