module extend(
    input wire [11:0] i_si12,
    input wire [4:0] i_ui5,
    input wire [19:0] i_si20,
    input wire [15:0] i_offs16,
    input wire [9:0] i_offs26,
    input wire [13:0] i_si14,
    input wire [6:0] i_sign,

    output reg [31:0] o_imm32,
    output reg [31:0] o_offs32
    );

wire [31:0] ui5_32;
wire [31:0] si12_32;
wire [31:0] si12_32_u;
wire [31:0] si20_32;
wire [31:0] offs16_32;
wire [31:0] offs26_32;
wire [31:0] si14_32;
assign ui5_32 = {27'b0 , i_ui5};
assign si12_32 = (i_si12[11] ? {20'b11111111111111111111 ,i_si12} : {20'b0 ,i_si12});
assign si12_32_u = {20'b0 ,i_si12};
assign si20_32 = {i_si20, 12'b0};
assign offs16_32 = (i_offs16[15] ? {14'b11111111111111 ,i_offs16 ,2'b0} : {14'b0, i_offs16, 2'b0});
assign offs26_32 = (i_offs26[9] ? {4'b1111, i_offs26, i_offs16, 2'b0} : {4'b0, i_offs26, i_offs16, 2'b0});
assign si14_32 = (i_si14[13] ? {16'b1111111111111111 , i_si14, 2'b0} : {16'b0 , i_si14, 2'b0});

// always@(*) begin
//     case(i_sign)
//         7'b0000000:begin
//             o_imm32 <= 32'b0;
//             o_offs32 <= 32'b0;
//         end
//         7'b0000001:begin
//             o_imm32 <= si14_32;
//             o_offs32 <= 32'b0;
//         end
//         7'b0000010:begin
//             o_imm32 <= 32'b100;
//             o_offs32 <= offs26_32;
//         end
//         7'b0000100:begin
//             o_imm32 <= 32'b100;
//             o_offs32 <= offs16_32;
//         end
//         7'b0001000:begin
//             o_imm32 <= si20_32;
//             o_offs32 <= 32'b0;
//         end
//         7'b0010000:begin
//             o_imm32 <= si12_32_u;
//             o_offs32 <= 32'b0;
//         end
//         7'b0100000:begin
//             o_imm32 <= si12_32;
//             o_offs32 <= 32'b0;
//         end
//         7'b1000000:begin
//             o_imm32 <= ui5_32;
//             o_offs32 <= 32'b0;
//         end
//     endcase
// end
  
 always@(*) begin
    case(i_sign)
        7'b0000000:begin
            o_imm32 <= 32'b0;
            o_offs32 <= 32'b0;
        end
        7'b0000001:begin
            o_imm32 <= si14_32;
            o_offs32 <= si14_32;
        end
        7'b0000010:begin
            o_imm32 <= offs26_32;
            o_offs32 <= offs26_32;
        end
        7'b0000100:begin
            o_imm32 <= offs16_32;
            o_offs32 <= offs16_32;
        end
        7'b0001000:begin
            o_imm32 <= si20_32;
            o_offs32 <= si20_32;
        end
        7'b0010000:begin
            o_imm32 <= si12_32_u;
            o_offs32 <= si12_32_u;
        end
        7'b0100000:begin
            o_imm32 <= si12_32;
            o_offs32 <= si12_32;
        end
        7'b1000000:begin
            o_imm32 <= ui5_32;
            o_offs32 <=ui5_32;
        end
    endcase
end
   
    
    
endmodule
