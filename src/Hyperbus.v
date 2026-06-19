`timescale 1ns/100ps

module Hyperbus (
    input clk,
    input go,
    
    // Hyperbus Pins
    output reg              o_SpiClk,
    output reg              o_SpiClk_neg,
    output reg              o_ChipSelect_neg,
    output                  o_Reset,
    inout [BUS_WIDTH-1 : 0] io_QD,
    inout                   io_Data_Strobe
);

parameter BUS_WIDTH = 8;

// Pin tristate stuff
wire  enClk;
reg  enSerialOut;
reg  [BUS_WIDTH-1 : 0] SerialOut;
wire [BUS_WIDTH-1 : 0] SerialIn;

genvar i;
generate
    for (i = 0; i < BUS_WIDTH; i++) begin
        assign io_QD[i] = (enSerialOut) ? SerialOut[i] : 1'bZ;
        assign SerialIn[i] = io_QD[i];
    end
endgenerate

// Logic stuff
reg  [7:0] opcode;
reg [39:0] address;
reg        write_address;
reg        write_data;
reg        read_data;
integer    num_bits;
integer    state;

integer count           = 0;
integer clock_count     = 0;
reg     SpiClk          = 0;
wire    clock_tick;
integer buffer_count    = 0;

reg  [7:0] buffer [0:15];

// states
parameter integer idle          = 0;
parameter integer cl_low        = 5;
parameter integer cl_high       = 8;
parameter integer send_opcode   = 1;
parameter integer send_address  = 2;
parameter integer wait_latency1 = 9;
parameter integer wait_latency2 = 10;
parameter integer send_data     = 3;
parameter integer recieve_data  = 4;

// constants
parameter integer TIMER_COUNT       = 15;
parameter integer OPCODE_LENGTH     = 8;
parameter integer ADDRESS_LENGTH    = 5;
parameter integer LATENCY           = 4* TIMER_COUNT;


initial begin : setup_registers
    opcode              <= 0;
    address             <= 0;
    enSerialOut         <= 0;
    SerialOut           <= 8'd0;
    state               <= 0;
    o_ChipSelect_neg    <= 1'b1;
    o_SpiClk            <= 1'b0;
    o_SpiClk_neg        <= 1'b1;

    // the default case is reading from an address.
    write_address   <= 1;
    write_data      <= 0;
    read_data       <= 1;
    num_bits        <= 32;
end


assign enClk        = (state != idle)? 1'b1 : 1'b0;
assign clock_tick   = (clock_count == TIMER_COUNT / 2)? 1'b1 : 1'b0;
always @(posedge clk) begin: spi_clock
    o_SpiClk     <=  SpiClk;
    o_SpiClk_neg <= ~SpiClk;

    if (~enClk) begin
        SpiClk          <= 1'b0;
        clock_count     <= TIMER_COUNT;
    end
    else begin
        if (clock_count == 0) begin
            clock_count     <=  TIMER_COUNT;
            SpiClk          <= ~SpiClk;
        end
        else 
            clock_count <= clock_count -1;
    end
end


always @(posedge clk) begin : sm_logic
    case (state)
        idle : begin
            o_ChipSelect_neg <= 1'b1;
            enSerialOut <= 1'b0;
            if (go) state <= cl_low;
        end


        cl_low : begin
            o_ChipSelect_neg <= 1'b0;
            count <= OPCODE_LENGTH/4 -1;
            enSerialOut <= 1'b1;

            if (clock_tick)
                state <= send_opcode;
        end


        send_opcode : begin
            for (integer i = 0; i < BUS_WIDTH; i++) begin
                SerialOut[i] <= opcode[i];
            end
            
            if (clock_tick) begin
                count <= ADDRESS_LENGTH-1;
                state <= send_address;
            end
        end


        send_address : begin
            for (integer i = 0; i < BUS_WIDTH; i++) begin
                SerialOut[i] <= address[{count, i[2:0]}];
            end

            if (clock_tick)
                count <= count -1;
                
            if (count == 0 && clock_tick) begin
                buffer_count <= 0;
                if (io_Data_Strobe) begin
                    count <= LATENCY *2;
                    state <= wait_latency2;
                end
                else begin
                    count <= LATENCY;
                    state <= wait_latency1;
                end
            end
        end


        wait_latency1 : begin
            count <= count -1;
            
            if (count == 0) begin
                count <= num_bits/4-1;
                
                if (write_data)
                    state <= send_data;
                else
                    state <= recieve_data;
            end
        end


        wait_latency2 : begin
            count <= count -1;
            
            if (count == 0) begin
                count <= num_bits/4-1;
                
                if (write_data)
                    state <= send_data;
                else
                    state <= recieve_data;
            end
        end


        recieve_data : begin
            enSerialOut <= 1'b0;

            if (clock_tick) begin
                count <= count -1;
                buffer_count <= buffer_count +1;

                for (integer i = 0; i < BUS_WIDTH; i++) begin
                    buffer[buffer_count][i] <= SerialIn[i];
                end
            end

            if (count == 0 & clock_tick) begin
                count <= 0; // otherwise underflow - can this be synthesised elegantly?
                state <= cl_high;
            end
        end 


        send_data : begin
            if (clock_tick) begin
                count <= count -1;
                buffer_count <= buffer_count +1;
                for (integer i = 0; i < BUS_WIDTH; i++) begin
                    SerialOut[i] <= buffer[buffer_count][i];
                end
            end

            if (count == 0 & clock_tick) begin
                count <= 0; // otherwise underflow - can this be synthesised elegantly?
                state <= cl_high;
            end
        end


        cl_high : begin
            if (clock_tick) begin
                state <= idle;
                enSerialOut <= 1'b0;
            end
        end


        default : 
            state <= idle;
    endcase
end
    
endmodule
