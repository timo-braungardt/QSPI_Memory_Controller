`timescale 1ns/100ps

module QuadSPI (
    input clk,
    input go,
    
    // SPI Pins
    output reg o_SpiClk,
    output reg o_ChipSelect_neg,
    output o_Reset,
    inout io_ManagerSerialIn_QD0,
    inout io_ManagerSerialOut_QD1,
    inout io_DQ2,
    inout io_DQ3
);

// Pin tristate stuff
wire  enClk;
reg  enSerialOut;
reg  SerialOut0, SerialOut1, SerialOut2, SerialOut3;
wire SerialIn0, SerialIn1, SerialIn2, SerialIn3;

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
reg        write_address;
reg        write_data;
reg        read_data;
integer    num_bits;
integer    state;

reg  [7:0] buffer [0:15];

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
    enSerialOut <= 0;
    SerialOut0  <= 0;
    SerialOut1  <= 0;
    SerialOut2  <= 0;
    SerialOut3  <= 0;
    state       <= 0;
    o_ChipSelect_neg <= 1'b1;
    o_SpiClk    <= 1'b0;

    // the default case is reading from an address.
    write_address   <= 1;
    write_data      <= 0;
    read_data       <= 1;
    num_bits        <= 32;
end


assign enClk = (state != idle && state != cl_low)? 1'b1 : 1'b0;
always @(posedge clk) begin: spi_clock
    if (enClk)
        o_SpiClk <= ~o_SpiClk;
    else
        o_SpiClk <= 1'b0;
end


integer count = 0;
integer buffer_count = 0;
always @(posedge clk) begin : sm_logic
    case (state)
        idle : begin
            o_ChipSelect_neg <= 1'b1;
            enSerialOut <= 1'b0;
            if (go) state <= cl_low;
        end


        cl_low : begin
            o_ChipSelect_neg <= 1'b0;
            count <= 2;                // we have to write 8 bit in 16 clock edges - by setting this to one lower, the data changes on the negative clock edge
            enSerialOut <= 1'b1;
            SerialOut0 <= opcode[7];  // this is a bit shitty - but otherwise the old last sent value is sent out
            SerialOut1 <= opcode[6];
            SerialOut2 <= opcode[5];
            SerialOut3 <= opcode[4];
            state <= send_opcode;
        end


        send_opcode : begin
            SerialOut0 <= opcode[{count[29:1], 2'd0}];
            SerialOut1 <= opcode[{count[29:1], 2'd1}];
            SerialOut2 <= opcode[{count[29:1], 2'd2}];
            SerialOut3 <= opcode[{count[29:1], 2'd3}];
            count <= count -1;
            
            if (count == 0) begin
                count <= 11;            // what is the correct value?
                if (write_address)
                    state <= send_address;
                else if (write_data)
                    state <= send_data;
                else 
                    state <= idle;
            end
        end


        send_address : begin
            SerialOut0 <= address[{count[29:1], 2'd0}];
            SerialOut1 <= address[{count[29:1], 2'd1}];
            SerialOut2 <= address[{count[29:1], 2'd2}];
            SerialOut3 <= address[{count[29:1], 2'd3}];
            count <= count -1;

            if (count == 0) begin
                count <= num_bits;
                buffer_count <= 0;
                if (write_data)
                    state <= send_data;
                else if(read_data)
                    state <= recieve_data;
                else
                    state <= idle;
            end
        end


        recieve_data : begin
            enSerialOut <= 1'b0;
            count <= count -1;
            buffer_count <= buffer_count +1;

            // if the clock was 0, then now it is 1
            // so we sample on the positive clock edge
            if (~o_SpiClk) begin
                buffer[buffer_count[7:2]][{count[1], 2'd0}] <= SerialIn0;
                buffer[buffer_count[7:2]][{count[1], 2'd1}] <= SerialIn1;
                buffer[buffer_count[7:2]][{count[1], 2'd2}] <= SerialIn2;
                buffer[buffer_count[7:2]][{count[1], 2'd3}] <= SerialIn3;
            end

            if (count == 0) begin
                count <= 0; // otherwise underflow - can this be synthesised elegantly?
                state <= idle;
            end
        end 


        send_data : begin
            count <= count -1;
            buffer_count <= buffer_count +1;
            SerialOut0 <= buffer[buffer_count[7:2]][{count[1], 2'd0}];
            SerialOut1 <= buffer[buffer_count[7:2]][{count[1], 2'd1}];
            SerialOut2 <= buffer[buffer_count[7:2]][{count[1], 2'd2}];
            SerialOut3 <= buffer[buffer_count[7:2]][{count[1], 2'd3}];

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
