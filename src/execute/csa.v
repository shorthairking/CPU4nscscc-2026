module csa(
input wire [32:0] s_in,
input wire [32:0] c_in,
input wire [32:0] m,

output wire [32:0] s_out,
output wire [32:0] c_out
    );

    
    full_adder f0(.a(s_in[0]),.b(1'b0),.x(m[0]),.s(s_out[0]),.c(c_out[1]));
    full_adder f1(.a(s_in[1]),.b(c_in[1]),.x(m[1]),.s(s_out[1]),.c(c_out[2]));
    full_adder f2(.a(s_in[2]),.b(c_in[2]),.x(m[2]),.s(s_out[2]),.c(c_out[3]));
    full_adder f3(.a(s_in[3]),.b(c_in[3]),.x(m[3]),.s(s_out[3]),.c(c_out[4]));
    full_adder f4(.a(s_in[4]),.b(c_in[4]),.x(m[4]),.s(s_out[4]),.c(c_out[5]));
    full_adder f5(.a(s_in[5]),.b(c_in[5]),.x(m[5]),.s(s_out[5]),.c(c_out[6]));
    full_adder f6(.a(s_in[6]),.b(c_in[6]),.x(m[6]),.s(s_out[6]),.c(c_out[7]));
    full_adder f7(.a(s_in[7]),.b(c_in[7]),.x(m[7]),.s(s_out[7]),.c(c_out[8]));
    
    full_adder f8(.a(s_in[8]),.b(c_in[8]),.x(m[8]),.s(s_out[8]),.c(c_out[9]));
    full_adder f9(.a(s_in[9]),.b(c_in[9]),.x(m[9]),.s(s_out[9]),.c(c_out[10]));
    full_adder f10(.a(s_in[10]),.b(c_in[10]),.x(m[10]),.s(s_out[10]),.c(c_out[11]));
    full_adder f11(.a(s_in[11]),.b(c_in[11]),.x(m[11]),.s(s_out[11]),.c(c_out[12]));
    full_adder f12(.a(s_in[12]),.b(c_in[12]),.x(m[12]),.s(s_out[12]),.c(c_out[13]));
    full_adder f13(.a(s_in[13]),.b(c_in[13]),.x(m[13]),.s(s_out[13]),.c(c_out[14]));
    full_adder f14(.a(s_in[14]),.b(c_in[14]),.x(m[14]),.s(s_out[14]),.c(c_out[15]));
    full_adder f15(.a(s_in[15]),.b(c_in[15]),.x(m[15]),.s(s_out[15]),.c(c_out[16]));
    
    full_adder f16(.a(s_in[16]),.b(c_in[16]),.x(m[16]),.s(s_out[16]),.c(c_out[17]));
    full_adder f17(.a(s_in[17]),.b(c_in[17]),.x(m[17]),.s(s_out[17]),.c(c_out[18]));
    full_adder f18(.a(s_in[18]),.b(c_in[18]),.x(m[18]),.s(s_out[18]),.c(c_out[19]));
    full_adder f19(.a(s_in[19]),.b(c_in[19]),.x(m[19]),.s(s_out[19]),.c(c_out[20]));
    full_adder f20(.a(s_in[20]),.b(c_in[20]),.x(m[20]),.s(s_out[20]),.c(c_out[21]));
    full_adder f21(.a(s_in[21]),.b(c_in[21]),.x(m[21]),.s(s_out[21]),.c(c_out[22]));
    full_adder f22(.a(s_in[22]),.b(c_in[22]),.x(m[22]),.s(s_out[22]),.c(c_out[23]));
    full_adder f23(.a(s_in[23]),.b(c_in[23]),.x(m[23]),.s(s_out[23]),.c(c_out[24]));
    
    full_adder f24(.a(s_in[24]),.b(c_in[24]),.x(m[24]),.s(s_out[24]),.c(c_out[25]));
    full_adder f25(.a(s_in[25]),.b(c_in[25]),.x(m[25]),.s(s_out[25]),.c(c_out[26]));
    full_adder f26(.a(s_in[26]),.b(c_in[26]),.x(m[26]),.s(s_out[26]),.c(c_out[27]));
    full_adder f27(.a(s_in[27]),.b(c_in[27]),.x(m[27]),.s(s_out[27]),.c(c_out[28]));
    full_adder f28(.a(s_in[28]),.b(c_in[28]),.x(m[28]),.s(s_out[28]),.c(c_out[29]));
    full_adder f29(.a(s_in[29]),.b(c_in[29]),.x(m[29]),.s(s_out[29]),.c(c_out[30]));
    full_adder f30(.a(s_in[30]),.b(c_in[30]),.x(m[30]),.s(s_out[30]),.c(c_out[31]));
    full_adder f31(.a(s_in[31]),.b(c_in[31]),.x(m[31]),.s(s_out[31]),.c(c_out[32]));
    
    full_adder f32(.a(s_in[32]),.b(c_in[32]),.x(m[32]),.s(s_out[32]),.c(c_out[0]));

    
endmodule