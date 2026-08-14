module full_adder
(
    input wire a,
    input wire b,
    input wire x,
    output reg s,
    output reg c
);

always @(*) begin
    s <= a ^ b ^ x;
    c <= (a & b) | (a & x) | (b & x);
end

endmodule
