`timescale 1ns/100ps

module my_design (
    input clk,
    output reg signal
);

initial begin
    signal = 1'b0;
end

always @(posedge clk ) begin
    signal <= ~signal;
end
    
endmodule