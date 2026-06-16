`timescale 1ns/100ps

module QuadSPI (
    input clk,
    input go,
    
    // SPI Pins
    output o_SpiClk,
    output reg o_ChipSelect_neg,
    output o_Reset,
    inout io_ManagerSerialIn_QD0,
    inout io_ManagerSerialOut_QD1,
    inout io_DQ2,
    inout io_DQ3
);

// Pin tristate stuff
reg  enClk;
reg  enSerialOut;
reg  SerialOut0, SerialOut1, SerialOut2, SerialOut3;
wire SerialIn0, SerialIn1, SerialIn2, SerialIn3;

assign o_SpiClk                 = (enClk)        ? clk       : 1'b0;
assign io_ManagerSerialIn_QD0   = (enSerialOut)  ? SerialOut0 : 1'bZ;
assign io_ManagerSerialOut_QD1  = (enSerialOut)  ? SerialOut1 : 1'bZ;       // ToDo: this pin is not serial out for spi mode!
assign io_DQ2                   = (enSerialOut)  ? SerialOut2 : 1'bZ;
assign io_DQ3                   = (enSerialOut)  ? SerialOut3 : 1'bZ;
assign SerialIn0                = io_ManagerSerialIn_QD0;
assign SerialIn1                = io_ManagerSerialOut_QD1;
assign SerialIn2                = io_DQ2;
assign SerialIn3                = io_DQ3;

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
    SerialOut0  <= 0;
    SerialOut1  <= 0;
    SerialOut2  <= 0;
    SerialOut3  <= 0;
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

            SerialOut0 <= opcode[count-3];
            SerialOut1 <= opcode[count-2];
            SerialOut2 <= opcode[count-1];
            SerialOut3 <= opcode[count];
            count <= count -4;
            
            if (count == 3) begin
                count <= 23; // otherwise underflow - can this be synthesised elegantly?
                state <= send_address;
            end
        end

        send_address : begin
            SerialOut0 <= address[count-3];
            SerialOut1 <= address[count-2];
            SerialOut2 <= address[count-1];
            SerialOut3 <= address[count];
            count <= count -4;

            if (count == 3) begin
                count <= 31;
                state <= recieve_data;
            end
        end

        recieve_data : begin
            enSerialOut <= 1'b0;
            count <= count -1;

            if (count == 0) begin
                count <= 0; // otherwise underflow - can this be synthesised elegantly?
                state <= idle;
            end
        end 

        default : 
            state <= idle;
    endcase
end
    
endmodule
