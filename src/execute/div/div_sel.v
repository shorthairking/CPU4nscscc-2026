module div_sel(
input wire [31:0] D,
input wire [2:0] Q,

output reg [32:0] M
    );
    
always @(*) begin
    case(Q)
        3'b000:M = 33'b0;
        3'b001:M = ~{1'b0 , D} + 1'b1;
        3'b010:M = (~{1'b0 , D} + 1'b1)<<1;
        3'b111:M = {1'b0 , D};
        3'b110:M = {1'b0 , D} << 1;
        default:M = 33'b0;
    endcase
end
endmodule