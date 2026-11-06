module ResetSynchronizer (
    input  clk,
    input  async_reset_neg, // asynchronous reset input signal
    output o_reset_neg      // synchronized reset output
);

    reg [1:0] flip_flop;
    assign o_reset_neg = flip_flop[1];

    always @(posedge clk or negedge async_reset_neg) begin
        if (!async_reset_neg) begin
            flip_flop <= 0;
        end else begin
            flip_flop[0] <= 1'b1;
            flip_flop[1] <= flip_flop[0];
        end
    end

endmodule
