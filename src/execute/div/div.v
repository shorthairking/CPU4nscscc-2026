module div(
input wire [31:0] Z_in,
input wire [31:0] D_in,
input wire ena,
// input wire i_u_sign,
input wire [2:0] div_op, //div_op[2] = 1时表示有符号除法，但div内部中，i_u_sign= 0才表示有符号除法
input wire clk,
input wire rstn,

// output reg [31:0] r,
// output reg [31:0] q,
output wire [31:0]  div_result,
output reg          over    ,
input wire flush, 
output wire         ready   
    );
wire i_u_sign = !div_op[2] ;
//将原来的输入i_u_sign改为内部的i_u_sign，输入端口位div_op
//将原来的输出r和q改成内部信号，输出�?�过div_op来�?�择输出商还是余�?
reg [31:0] r;
reg [31:0] q;

reg [31:0] Z_nomal_in;
reg [31:0] D_nomal_in;
reg u_sign;
reg [32:0] Z_csa_s;
reg [32:0] Z_csa_c;
reg [31:0] Z_source;
reg [31:0] D_n;
reg [4:0] diff;
reg fin;
reg q_sign;
reg r_sign;
reg [4:0] counter;
reg [31:0] Qa;
reg [31:0] Qb;

reg [1:0] state;//00~׼����������   01~����    10~�����������?

wire [63:0] Z_nomal_out;
wire [31:0] D_nomal_out;
wire [4:0] diff_nomal_out;
wire fin_nomal_out;
wire r_sign_out;

wire [32:0] m;
wire [32:0] csa_s_out;
wire [32:0] csa_c_out;
wire [7:0] sum_cla;
wire [2:0] q_lut;

wire [31:0] Qa_out;
wire [31:0] Qb_out;

wire [31:0] rel;
wire [31:0] Q;
reg [10:0] test;

reg [2:0] div_op_r;

always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
        u_sign <= 1'b0;
        Z_nomal_in <= 32'b0;
        D_nomal_in <= 32'b0;
        Z_csa_s <= 33'b0;
        Z_csa_c <= 33'b0;
        Z_source <= 32'b0;
        D_n <= 32'b0;
        counter <= 5'b0;
        diff <= 5'b0;
        fin <= 1'b0;
        q_sign <= 1'b0;
        r_sign <= 1'b0;
        Qa <= 32'b0;
        Qb <= 32'b0;
        
        r <= 32'b0;
        q <= 32'b0;
        over <= 1'b0;
        
        state <= 2'b0;
        counter <= 5'b0;
        test<=0;
        div_op_r <= 0 ;
     end else if (flush) begin   // ������ˢ�߼���ͬ�����㣩
            u_sign <= 1'b0;
            Z_nomal_in <= 32'b0;
            D_nomal_in <= 32'b0;
            Z_csa_s <= 33'b0;
            Z_csa_c <= 33'b0;
            Z_source <= 32'b0;
            D_n <= 32'b0;
            counter <= 5'b0;
            diff <= 5'b0;
            fin <= 1'b0;
            q_sign <= 1'b0;
            r_sign <= 1'b0;
            Qa <= 32'b0;
            Qb <= 32'b0;
            r <= 32'b0;
            q <= 32'b0;
            over <= 1'b0;
            state <= 2'b00;
            counter <= 5'b0;
            test <= 0;
            div_op_r <= 0;
        end else begin 
        if(fin) begin//��0�쳣����ֹ
            u_sign <= 1'b0;
            Z_nomal_in <= 32'b0;
            D_nomal_in <= 32'b0;
            Z_csa_s <= 33'b0;
            Z_csa_c <= 33'b0;
            Z_source <= 32'b0;
            D_n <= 32'b0;
            counter <= 5'b0;
            diff <= 5'b0;
            fin <= 1'b0;
            q_sign <= 1'b0;
            r_sign <= 1'b0;
            Qa <= 32'b0;
            Qb <= 32'b0;
            
            r <= 32'hffffffff;
            q <= 32'hffffffff;
            over <= 1'b1;
            state <= 2'b0;
            counter <= 5'b0;
            
        end
        else if(state == 2'b00) begin//�����źźͲ����룬��ʼ��ʼ��
            if(ena) begin
                u_sign <= i_u_sign;
                Z_nomal_in <= Z_in;
                D_nomal_in <= D_in;
                Z_csa_s <= 33'b0;
                Z_csa_c <= 33'b0;
                Z_source <= 32'b0;
                D_n <= 32'b0;
                diff <= 5'b0;
                fin <= 1'b0;
                q_sign <= 1'b0;
                r_sign <= 1'b0;
                Qa <= 32'b0;
                Qb <= 32'b0;
                
                r <= 32'b0;
                q <= 32'b0;
                over <= 1'b0;
                
                state <= 2'b01;
                counter <= 5'b00001;
                div_op_r <= div_op ;

            end
            else begin
                u_sign <= 1'b0;
                Z_nomal_in <= 32'b0;
                D_nomal_in <= 32'b0;
                over <= 1'b0;
                state <= 2'b00;
                counter <= 5'b00000;
            end
        end
        else if(state == 2'b01) begin//���ճ�ʼ�����ݣ���ʼ����
            Z_csa_s <= {1'b0, Z_nomal_out[63:32]};
            Z_csa_c <= 33'b0;
            Z_source <= Z_nomal_out[31:0];
            D_n <= D_nomal_out;
            diff <= diff_nomal_out;
            fin <= fin_nomal_out;
            q_sign <= q_sign_out;
            r_sign <= r_sign_out;
            
            state <= 2'b10;
            counter <= counter + 1;

        end
        else if(state == 2'b10) begin//����
            Z_csa_s <= csa_s_out;
            Z_csa_c <= csa_c_out;
            Z_source <= {Z_source[29:0], 2'b0};
            Qa <= Qa_out;
            Qb <= Qb_out;
            counter <= counter + 1;
            if(counter == 5'b10001) begin
                state <= 2'b11;
            end
            else begin
                state <= state;
            end

        end
        else if(state == 2'b11) begin//����
            fin <= 1'b0;
            if(counter == 5'b10100) begin
                over <= 1'b0;
                r <= r;
                q <= q;
                state <= 2'b0;
                counter <= 5'b0;
            end
            else begin
                over <= 1'b1;
                r <= rel;
                q <= Q;
                state <= state;
                counter <= counter + 1;
            end
        end
    end
end

assign ready = (state == 2'b00) ;
assign div_result = div_op_r[0] ? q : //
                    div_op_r[1] ? r : 32'b0;
normalizer nomal(
.Z_in(Z_nomal_in),
.D_in(D_nomal_in),
.op_1(u_sign),
.rstn(rstn),

.Z_out(Z_nomal_out),
.D_out(D_nomal_out),
.diff(diff_nomal_out),
.final1(fin_nomal_out),
.q_sign(q_sign_out),
.r_sign(r_sign_out)
);

csa ca1(
.s_in({Z_csa_s[30:0], Z_source[31:30]}),
.c_in({Z_csa_c[30:0], 2'b0}),
.m(m),

.s_out(csa_s_out),
.c_out(csa_c_out)
);

cla cla1(
.add1(Z_csa_s[32:25]),
.add2(Z_csa_c[32:25]),

.sum(sum_cla)
);

lut lut1(
.P(sum_cla),
.D(D_n[31:28]),
.rstn(rstn),

.Q(q_lut)
);

div_sel s(
.D(D_n),
.Q(q_lut),

.M(m)
);

q_convert q_con(
.Qa_in(Qa),
.Qb_in(Qb),
.Q(q_lut),

.Qa_out(Qa_out),
.Qb_out(Qb_out)
);

qcoor qcoor1(
.Q(Qa),
.D(D_n),
.s(Z_csa_s),
.c(Z_csa_c),
.diff(diff),
.state(state),
.rstn(rstn),
.q_sign(q_sign),
.r_sign(r_sign),

.rel(rel),
.Q_out(Q)
);

endmodule
