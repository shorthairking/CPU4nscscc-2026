module counter(
    input wire clk,
    input wire rstn,

    output reg [63:0] o_cnt_data_64,
    output wire [4:0] o_rand_index
);
//..................................................

always @(posedge clk or negedge rstn) begin
    if (~rstn) begin
        o_cnt_data_64 <= 64'b0;
    end else  begin
        o_cnt_data_64 <= o_cnt_data_64 + 64'b1;
    end
end

//..................................................

assign o_rand_index = o_cnt_data_64[4:0];

//..................................................
endmodule
