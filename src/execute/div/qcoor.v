module qcoor(
input wire [31:0] Q,
input wire [31:0] D,
input wire [32:0] s,
input wire [32:0] c,
input wire [4:0] diff,
input wire [1:0] state,
input wire rstn,
input wire q_sign,
input wire r_sign,
    
output reg [31:0] rel,
output reg [31:0] Q_out
    );
wire [32:0] m;
assign m = {1'b0, D};
wire [32:0] sum;
assign sum = s + {c[32:1], 1'b0};

always @(*) begin
    if(!rstn) begin
        rel <= 32'b0;
        Q_out <= 32'b0;
    end
    else begin
        if(state == 2'b11) begin
            if (sum[32]) begin
                rel <= r_sign ? (~((sum + m) >> diff) + 1) : ((sum + m) >> diff);
                Q_out <= q_sign ?  ~(Q - 2) : (Q - 1);
            end
            else begin
                rel <= r_sign ? (~(sum >> diff) + 1) : (sum >> diff);
                Q_out <= q_sign ?  (~Q + 1) : Q;
            end

        end
        else begin
            rel <= 32'b0;
            Q_out <= 32'b0;
        end
    end
end
endmodule
