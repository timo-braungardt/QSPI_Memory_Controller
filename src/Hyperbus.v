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
reg         is_read;
reg         is_register_space;
reg         is_linear_burst;
reg  [31:0] address;
wire [47:0] ca;

assign ca[47]    = is_read;
assign ca[46]    = is_register_space;
assign ca[45]    = is_linear_burst;
assign ca[44:16] = address[31:3];
assign ca[15:3]  = 13'd0;
assign ca[2:0]   = address[2:0];

integer     num_bits;
integer     state;

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
parameter integer send_ca       = 11;
parameter integer wait_latency1 = 9;
parameter integer wait_latency2 = 10;
parameter integer send_data     = 3;
parameter integer recieve_data  = 4;

// constants
parameter integer TIMER_COUNT       = 15;
parameter integer OPCODE_LENGTH     = 8;
parameter integer ADDRESS_LENGTH    = 6;
parameter integer LATENCY           = 4* TIMER_COUNT;


initial begin : setup_registers
    enSerialOut         <= 0;
    SerialOut           <= 8'd0;
    state               <= 0;
    o_ChipSelect_neg    <= 1'b1;
    o_SpiClk            <= 1'b0;
    o_SpiClk_neg        <= 1'b1;
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
            count <= ADDRESS_LENGTH-1;
            enSerialOut <= 1'b1;

            if (clock_tick)
                state <= send_ca;
        end


        send_ca : begin
            for (integer i = 0; i < BUS_WIDTH; i++)
                SerialOut[i] <= ca[{count, i[2:0]}];

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
                
                if (is_read)
                    state <= recieve_data;
                else
                    state <= send_data;
            end
        end


        wait_latency2 : begin
            count <= count -1;
            
            if (count == 0) begin
                count <= num_bits/4-1;
                
                if (is_read)
                    state <= recieve_data;
                else
                    state <= send_data;
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
