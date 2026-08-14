module normalizer(
input wire [31:0] Z_in,
input wire [31:0] D_in,
input wire op_1,//u_sign
input wire rstn,

output reg [63:0] Z_out,
output reg [31:0] D_out,
output reg [4:0] diff,
output reg final1,
output reg q_sign,
output reg r_sign
    );
    
reg [31:0] Z;
reg [31:0] D;

always @(*) begin
    if(!op_1) begin
        q_sign <= D_in[31] ^ Z_in[31];
        r_sign <= Z_in[31];
        Z <= Z_in[31] ? (~Z_in + 1) : Z_in;
        D <= D_in[31] ? (~D_in + 1) : D_in;
    end
    else begin
        q_sign <= 1'b0;
        r_sign <= 1'b0;
        Z <= Z_in;
        D <= D_in;
    end
end

always @(*) begin
    if(!rstn) begin
        Z_out <= 64'b0;
        D_out <= 32'b0;
        diff <= 5'b0;
        final1 <= 1'b0;
    end
    else begin
        if(D_in == 32'b0) begin
            Z_out <= 64'b1;
            D_out <= 32'b0;
            diff <= 5'b0;
            final1 <= 1'b1;
        end
        else begin
            final1 <= 1'b0;
                casex(D)
                    32'b1xxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx:diff <=5'b00000;
                    32'b01xx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx:diff <=5'b00001;
                    32'b001x_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx:diff <=5'b00010;
                    32'b0001_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx:diff <=5'b00011;
    
                    32'b0000_1xxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx:diff <=5'b00100;
                    32'b0000_01xx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx:diff <=5'b00101;
                    32'b0000_001x_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx:diff <=5'b00110;
                    32'b0000_0001_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx:diff <=5'b00111;
                    32'b0000_0000_1xxx_xxxx_xxxx_xxxx_xxxx_xxxx:diff <=5'b01000;
    
                    32'b0000_0000_01xx_xxxx_xxxx_xxxx_xxxx_xxxx:diff <=5'b01001;
                    32'b0000_0000_001x_xxxx_xxxx_xxxx_xxxx_xxxx:diff <=5'b01010;
                    32'b0000_0000_0001_xxxx_xxxx_xxxx_xxxx_xxxx:diff <=5'b01011;
                    32'b0000_0000_0000_1xxx_xxxx_xxxx_xxxx_xxxx:diff <=5'b01100;
    
                    32'b0000_0000_0000_01xx_xxxx_xxxx_xxxx_xxxx:diff <=5'b01101;
                    32'b0000_0000_0000_001x_xxxx_xxxx_xxxx_xxxx:diff <=5'b01110;
                    32'b0000_0000_0000_0001_xxxx_xxxx_xxxx_xxxx:diff <=5'b01111;
                    32'b0000_0000_0000_0000_1xxx_xxxx_xxxx_xxxx:diff <=5'b10000;
                    32'b0000_0000_0000_0000_01xx_xxxx_xxxx_xxxx:diff <=5'b10001;
    
                    32'b0000_0000_0000_0000_001x_xxxx_xxxx_xxxx:diff <=5'b10010;
                    32'b0000_0000_0000_0000_0001_xxxx_xxxx_xxxx:diff <=5'b10011;
                    32'b0000_0000_0000_0000_0000_1xxx_xxxx_xxxx:diff <=5'b10100;
                    32'b0000_0000_0000_0000_0000_01xx_xxxx_xxxx:diff <=5'b10101;
    
                    32'b0000_0000_0000_0000_0000_001x_xxxx_xxxx:diff <=5'b10110;
                    32'b0000_0000_0000_0000_0000_0001_xxxx_xxxx:diff <=5'b10111;
                    32'b0000_0000_0000_0000_0000_0000_1xxx_xxxx:diff <=5'b11000;
                    32'b0000_0000_0000_0000_0000_0000_01xx_xxxx:diff <=5'b11001;
    
                    32'b0000_0000_0000_0000_0000_0000_001x_xxxx:diff <=5'b11010;
                    32'b0000_0000_0000_0000_0000_0000_0001_xxxx:diff <=5'b11011;
                    32'b0000_0000_0000_0000_0000_0000_0000_1xxx:diff <=5'b11100;
                    32'b0000_0000_0000_0000_0000_0000_0000_01xx:diff <=5'b11101;
    
                    32'b0000_0000_0000_0000_0000_0000_0000_001x:diff <=5'b11110;
                    32'b0000_0000_0000_0000_0000_0000_0000_0001:diff <=5'b11111;
                    default:diff <= 5'b0;
                endcase
            D_out <= D[31:0] << diff;
            Z_out <= {32'b0 , Z[31:0]} << diff;
        end
    end
end
    
endmodule
