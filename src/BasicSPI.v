`timescale 1ns/100ps

module BasicSPI (
    input clk,
    input go,
    
    // SPI Pins
    output reg o_SpiClk,
    output reg o_ChipSelect_neg,
    output o_Reset,
    inout io_ManagerSerialIn,
    inout io_ManagerSerialOut
);

// Pin tristate stuff
wire enClk;
reg  enSerialOut;
reg  SerialOut;
wire SerialIn;

assign io_ManagerSerialOut = (enSerialOut)  ? SerialOut : 1'bZ;
assign SerialIn =            io_ManagerSerialIn;

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
    SerialOut   <= 0;
    state       <= 0;
    o_ChipSelect_neg <= 1'b1;
    o_SpiClk    <= 1'b0;

    // the default case is reading from an address.
    write_address   <= 1;
    write_data      <= 0;
    read_data       <= 1;
    num_bits        <= 31;
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
            count <= 14;                // we have to write 8 bit in 16 clock edges - by setting this to one lower, the data changes on the negative clock edge
            enSerialOut <= 1'b1;
            SerialOut <= opcode[7];     // this is a bit shitty - but otherwise the old last sent value is sent out
            state <= send_opcode;
        end

        send_opcode : begin
            SerialOut <= opcode[count[31:1]];
            count <= count -1;
            if (count == 0) begin
                count <= 47;
                if (write_address)
                    state <= send_address;
                else if (write_data)
                    state <= send_data;
                else 
                    state <= idle;
            end
        end

        send_address : begin
            SerialOut <= address[count[31:1]];
            count <= count -1;

            if (count == 0) begin
                count <= num_bits;
                buffer_count <= 0;
                if (write_data)
                    state <= send_data;
                else
                    state <= recieve_data;
            end
        end


        recieve_data : begin
            count <= count -1;
            buffer_count <= buffer_count +1;
            
            // if the clock was 0, then now it is 1
            // so we sample on the positive clock edge
            if (~o_SpiClk) begin
                buffer[buffer_count[7:4]][count[3:1]] <= SerialIn;
                SerialOut <= SerialIn;
            end

            if (count == 0) begin
                count <= 0; // otherwise underflow - can this be synthesised elegantly?
                state <= idle;
            end
        end


        send_data : begin
            count <= count -1;
            buffer_count <= buffer_count +1;
            SerialOut <= buffer[buffer_count[7:4]][count[3:1]];

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
