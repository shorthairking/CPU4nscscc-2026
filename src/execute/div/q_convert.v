module q_convert(
input wire [31:0] Qa_in,
input wire [31:0] Qb_in,
input wire [2:0] Q,

output wire [31:0] Qa_out,
output wire [31:0] Qb_out
    );

    assign   Qa_out = (~Q[2]) ? {Qa_in[29:0], Q[1:0]} : {Qb_in[29:0], Q[1:0]};
    assign   Qb_out = (~Q[2]&(|Q[1:0])) ? {Qa_in[29:0], Q[2:1]} : {Qb_in[29:0], {Q[1]^~Q[0], ~Q[0]}};
endmodule
