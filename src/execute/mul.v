//新的乘法器单元：涵盖了有符号数和无符号数
// 100MHz 3周期出结�?(拉高ready信号应该在p得到数据的时候，其实应该�?3周期)
module mul (
    input           clk,        // 时钟
    input           rst_n,      // 低电平复�?
    input           mul_en ,       // 乘法使能信号
    input  [31:0]   a,          // 32位有符号输入A
    input  [31:0]   b,          // 32位有符号输入B
    // input           mul_signed , //1-signed�? 0-unsigned   //将这个数据放到内部信号，我们统一引入mul的opcode
    output reg      mul_ready ,
    input           flush, 
    output wire     mul_done ,
    // output reg [63:0] p         // 64位有符号输出 //我们将mul的op也添加进来，�?后输出就是这条指令要数据，�?�不再�?�过exe-top来完成�?�择对应�?32还是�?32位数�?
    input   [2:0]              mul_op,
    output wire [31:0]    mul_result  
);

wire mul_signed = mul_op[2] ; //mul中，1-有符号数�?0-无符号数
reg [63:0] p; // 64位有符号内部输出

// 拆分32位输入为�?16�?+16位：因为dsp的B端口只有18位，而B�?17】是符号位，当执行mulhu指令的时候，出现问题
wire  [15:0] a_high = a[31:16];
wire  [15:0] a_low  = a[15:0];
wire  [15:0] b_high = b[31:16];
wire  [15:0] b_low  = b[15:0];
//根据mul_signed进行扩展
wire [24:0]a_high_ext,a_low_ext ;
wire [17:0]b_high_ext ,b_low_ext ;
assign a_high_ext = mul_signed ? {{9{a_high[15]}},a_high} : {9'b0, a_high} ;
assign a_low_ext  = {9'b0, a_low} ;
assign b_high_ext = mul_signed ? {{2{b_high[15]}}, b_high} : {2'b0, b_high};
assign b_low_ext  = {2'b0, b_low};

// 例化4个DSP48E1（MREG=0，PREG=1�?
wire signed [34:0] mul_hh,mul_hl, mul_lh, mul_ll;//�?�?32位，留出符号位余�?

// // DSP1: A高×B�? (16×16)
// DSP48E1 #(
//     .USE_MULT("MULTIPLY"),
//     .AREG(1), .BREG(1), .MREG(0), .PREG(1),  // MREG=0，PREG=1
//     .ACASCREG(0), .BCASCREG(0)
// ) dsp_hh (
//     .CLK(clk), .CE(1'b1), .RST(~rst_n),
//     .A(a_high_ext),  // A端口25位补0
//     .B(b_high_ext),   // B端口18位补0
//     .P(mul_hh),
//     .CARRYIN(1'b0), .OPMODE(7'b0100011), .ALUMODE(4'b0000)
// );

// // DSP2: A高×B�? (16×16)
// DSP48E1 #(
//     .USE_MULT("MULTIPLY"),
//     .AREG(1), .BREG(1), .MREG(0), .PREG(1)
// ) dsp_hl (
//     .CLK(clk), .CE(1'b1), .RST(~rst_n),
//     .A(a_high_ext),
//     .B(b_low_ext),
//     .P(mul_hl),
//     .CARRYIN(1'b0), .OPMODE(7'b0100011), .ALUMODE(4'b0000)
// );

// // DSP3: A低×B�? (16×16)
// DSP48E1 #(
//     .USE_MULT("MULTIPLY"),
//     .AREG(1), .BREG(1), .MREG(0), .PREG(1)
// ) dsp_lh (
//     .CLK(clk), .CE(1'b1), .RST(~rst_n),
//     .A(a_low_ext    ),
//     .B(b_high_ext   ),
//     .P(mul_lh),
//     .CARRYIN(1'b0), .OPMODE(7'b0100011), .ALUMODE(4'b0000)
// );

// // DSP4: A低×B�? (16×16)
// DSP48E1 #(
//     .USE_MULT("MULTIPLY"),
//     .AREG(1), .BREG(1), .MREG(0), .PREG(1)
// ) dsp_ll (
//     .CLK(clk), .CE(1'b1), .RST(~rst_n),
//     .A(a_low_ext),
//     .B(b_low_ext),
//     .P(mul_ll),
//     .CARRYIN(1'b0), .OPMODE(7'b0100011), .ALUMODE(4'b0000)
// );

// // DSP1: A高×B�? (16×16)
// DSP48E1 #(
//     .USE_MULT("MULTIPLY"),
//     .AREG(1), .BREG(1), .MREG(0), .PREG(1),
//     .ACASCREG(1)
// ) dsp_hh (
//     .CLK    (clk),
//     .A      (a_high_ext),
//     .B      (b_high_ext),
//     .C      (48'b0),
//     .D      (25'b0),
//     .CARRYIN(1'b0),
//     .OPMODE (7'b0100011),
//     .ALUMODE(4'b0000),
//     .CEA1   (1'b1),
//     .CEA2   (1'b0),
//     .CEB1   (1'b1),
//     .CEB2   (1'b0),
//     .CEC    (1'b0),
//     .CEM    (1'b0),
//     .CEP    (1'b1),
//     .RSTA   (~rst_n),
//     .RSTB   (~rst_n),
//     .RSTC   (1'b0),
//     .RSTM   (1'b0),
//     .RSTP   (~rst_n),
//     .P      (mul_hh)
// );

// // DSP2: A高×B�? (16×16)
// DSP48E1 #(
//     .USE_MULT("MULTIPLY"),
//     .AREG(1), .BREG(1), .MREG(0), .PREG(1), .ACASCREG(1)
// ) dsp_hl (
//     .CLK    (clk),
//     .A      (a_high_ext),
//     .B      (b_low_ext),
//     .C      (48'b0),
//     .D      (25'b0),
//     .CARRYIN(1'b0),
//     .OPMODE (7'b0100011),
//     .ALUMODE(4'b0000),
//     .CEA1   (1'b1),
//     .CEA2   (1'b0),
//     .CEB1   (1'b1),
//     .CEB2   (1'b0),
//     .CEC    (1'b0),
//     .CEM    (1'b0),
//     .CEP    (1'b1),
//     .RSTA   (~rst_n),
//     .RSTB   (~rst_n),
//     .RSTC   (1'b0),
//     .RSTM   (1'b0),
//     .RSTP   (~rst_n),
//     .P      (mul_hl)
// );

// // DSP3: A低×B�? (16×16)
// DSP48E1 #(
//     .USE_MULT("MULTIPLY"),
//     .AREG(1), .BREG(1), .MREG(0), .PREG(1), .ACASCREG(1)
// ) dsp_lh (
//     .CLK    (clk),
//     .A      (a_low_ext),
//     .B      (b_high_ext),
//     .C      (48'b0),
//     .D      (25'b0),
//     .CARRYIN(1'b0),
//     .OPMODE (7'b0100011),
//     .ALUMODE(4'b0000),
//     .CEA1   (1'b1),
//     .CEA2   (1'b0),
//     .CEB1   (1'b1),
//     .CEB2   (1'b0),
//     .CEC    (1'b0),
//     .CEM    (1'b0),
//     .CEP    (1'b1),
//     .RSTA   (~rst_n),
//     .RSTB   (~rst_n),
//     .RSTC   (1'b0),
//     .RSTM   (1'b0),
//     .RSTP   (~rst_n),
//     .P      (mul_lh)
// );

// // DSP4: A低×B�? (16×16)
// DSP48E1 #(
//     .USE_MULT("MULTIPLY"),
//     .AREG(1), .BREG(1), .MREG(0), .PREG(1), .ACASCREG(1)
// ) dsp_ll (
//     .CLK    (clk),
//     .A      (a_low_ext),
//     .B      (b_low_ext),
//     .C      (48'b0),
//     .D      (25'b0),
//     .CARRYIN(1'b0),
//     .OPMODE (7'b0100011),
//     .ALUMODE(4'b0000),
//     .CEA1   (1'b1),
//     .CEA2   (1'b0),
//     .CEB1   (1'b1),
//     .CEB2   (1'b0),
//     .CEC    (1'b0),
//     .CEM    (1'b0),
//     .CEP    (1'b1),
//     .RSTA   (~rst_n),
//     .RSTB   (~rst_n),
//     .RSTC   (1'b0),
//     .RSTM   (1'b0),
//     .RSTP   (~rst_n),
//     .P      (mul_ll)
// );

mult_gen_0 u_mulIP(
    .CLK(clk),
    .A(a),
    .B(b),
    .P(mulIP_result)
);

mult_gen_1 u_mulIP_unsign(
    .CLK(clk),
    .A(a),
    .B(b),
    .P(mulIP_result_unsign)
);

wire [63:0] mulIP_result, mulIP_result_unsign;

//符号扩展
function [63:0]sign_extend_35 (input [34:0]val, input is_signed);
begin 
    if(is_signed )  //�?35位符号扩展扩展到64�?
        sign_extend_35 = {{29{val[34]}},val};
    else 
        sign_extend_35 = {29'b0, val};//�?35位符号扩展到64�?    
end

endfunction
reg [63:0] p_unsign;
// 拼接+锁存合并到第2周期
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        p <= 64'd0;
        p_unsign <= 64'b0;
    end 
    else if (flush) begin   // ��ˢ��������
            p <= 64'd0;
            p_unsign <= 64'd0;
            end
    else begin
        // �?2周期：DSP的PREG输出有效，直接拼接后锁存
        p <= mulIP_result;      //有符�?   
        p_unsign <= mulIP_result_unsign;
        end
end

// 锁存 mul_op，对�? 3 周期乘法延迟
reg [2:0] mul_op_sr0, mul_op_sr1, mul_op_sr2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mul_op_sr0 <= 3'd0;
        mul_op_sr1 <= 3'd0;
        mul_op_sr2 <= 3'd0;
    end 
    else if (flush) begin   // ��ˢ�������ˮ��
            mul_op_sr0 <= 3'd0;
            mul_op_sr1 <= 3'd0;
            mul_op_sr2 <= 3'd0;
        end 
    
    else begin
        // mul_en 有效时锁存新 op；无论是否锁存，每一拍向后移�?
        mul_op_sr0 <= mul_en ? mul_op : mul_op_sr0;
        mul_op_sr1 <= mul_op_sr0;
        mul_op_sr2 <= mul_op_sr1;
    end
end
// //根据mul_op来�?�择�?32位还是低32位输�?
// assign mul_result = mul_op[1] ? p[63:32] :
//                     mul_op[0] ? p[31:0]  : 32'd0 ; //mul_op[1]=1时输出高32位，mul_op[0]=1时输出低32�?

assign mul_result = mul_op_sr2[2] ? (mul_op_sr2[1] ? p[63:32] : p[31:0]):
                                    (mul_op_sr2[1] ? p_unsign[63:32] : p_unsign[31:0]);
//使用移位寄存器来完成ready信号的匹配：mul_en信号只能维持�?个周�?
reg [2:0] ready_shr;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ready_shr <= 3'd0;
        mul_ready <= 1'b1;
    end 
    else if (flush) begin   // ��ˢ������̬
            ready_shr <= 3'd0;
            mul_ready <= 1'b1;
        end 
    else begin
        ready_shr <= {ready_shr[1:0], mul_en};
        // mul_en=0 时空闲；运算启动后拉低，3 拍后拉高，对�? p 有效
        mul_ready <= ~mul_en | ready_shr[2];
    end
end
assign mul_done = ready_shr[2];  // mul_done信号在p得到数据的时候拉�?,复用ready

endmodule
