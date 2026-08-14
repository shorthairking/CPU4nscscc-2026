`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Description: 
// 对比原来的那一版本，修改如下
//1.删除了fu_sel的判断逻辑，因为实际上我们的alu总在一个周期出数据，所以每个时钟周期的上升沿，alu都是空闲的，我们绑定了
//alu0-inst0,alu1-inst1 , 对于mul，div，lsu，都只有一个，所以只需要fu_type就可以知道去往哪个执行单元了，然后根据这个ready信号（到这里其实是输出的fu_avail）完成发射
//2.删除了访存宽度的端口，该信息已经被包含到了op中
//3.扩展op位宽，最高位上加上：preld  +  ertn +  idle +  cacop + cpucfg + tlb(10bit) +  exception(sign + excode6bits) + cnt_op(8bits) + csr(16bits) + grf_no_wen +  [原来的opcode （36bit）] = 47+36 = 83bit
//4.需要添加rj,rk,rd的5bit索引，cacop，sys,ertn等都需要这个rd的索引-其实就是code，只不过放在了rj, rk,rd的位置

//////////////////////////////////////////////////////////////////////////////////

module IQ(
    input wire clk,
    input wire rstn,
    input wire flush,          // 冲刷信号（分支预测错误、例外）

    // ----- 来自译码 / RMT / ROB 的分配端口（每周期最多 2 条指令）-----
    input  wire        alloc_en_idx0,           // 各指令分配有效
    input  wire [31:0] alloc_pc_idx0,           // PC
    input  wire [ 82:0]alloc_op_idx0,           // 内部操作码（ALU/MUL/DIV/LSU 需要）
    input  wire [ 1:0] alloc_fu_type_idx0,      // 功能单元类型：00=ALU, 01=MUL, 10=DIV, 11=LSU
    input  wire [ 2:0] alloc_rob_idx_idx0,      // ROB 条目索引（目的）
    input  wire [ 4:0] alloc_rd_index_idx0,     // 目的寄存器索引（5-bit）
    input  wire [ 4:0] alloc_rj_index_idx0,     // 源操作数 rj 的寄存器索引
    input  wire [ 4:0] alloc_rk_index_idx0,     // 源操作数 rk 的寄存器索引
    // 源操作数信息（来自 RMT）
    input  wire        alloc_rj_ready_idx0,   // 源1 是否已就绪（可直接从 ARF 取值）
    input  wire [ 2:0] alloc_rj_rob_idx0,     // 若未就绪，等待的 ROB 索引
    input  wire [31:0] alloc_rj_value_idx0,   // 若已就绪，ARF 读出的值
    input  wire        alloc_rk_ready_idx0,
    input  wire [ 2:0] alloc_rk_rob_idx0,
    input  wire [31:0] alloc_rk_value_idx0,
    // 访存/分支附加信息（根据需要）
    input  wire        alloc_is_branch_idx0,    // 是否为分支指令
    input  wire [31:0] alloc_imm_idx0,          // 立即数（已扩展）

    // ----- 来自 CDB 的唤醒端口（每周期最多 2 个结果）-----
    input  wire        cdb_valid_idx0,
    input  wire [ 2:0] cdb_rob_idx_idx0,
    input  wire [31:0] cdb_value_idx0,

    // ----- 发射到执行单元的接口（每周期最多 2 条指令）-----
    output reg        issue_valid_idx0,
    output reg [82:0] issue_op_idx0,
    output reg [31:0] issue_rj_idx0,
    output reg [31:0] issue_rk_idx0,
    output reg [ 2:0] issue_rob_idx_idx0,
    output reg [31:0] issue_pc_idx0,
    output reg        issue_is_branch_idx0,
    output reg [31:0] issue_imm_idx0,
    output reg [1:0]  issue_fu_type_idx0,
    output reg [4:0]  issue_rd_index_idx0,     // 发射的rd索引
    output reg [4:0]  issue_rj_index_idx0,     // 发射的 rj 索引
    output reg [4:0]  issue_rk_index_idx0,     // 发射的 rk 索引
    //inst1
    // ----- 来自译码 / RMT / ROB 的分配端口（每周期最多 2 条指令）-----
    input  wire        alloc_en_idx1,           // 各指令分配有效
    input  wire [31:0] alloc_pc_idx1,           // PC
    input  wire [ 82:0] alloc_op_idx1,           // 内部操作码（ALU/MUL/DIV/LSU 需要）
    input  wire [ 1:0] alloc_fu_type_idx1,      // 功能单元类型：00=ALU, 01=MUL, 10=DIV, 11=LSU
    input  wire [ 2:0] alloc_rob_idx_idx1,      // ROB 条目索引（目的）
    input  wire [ 4:0] alloc_rd_index_idx1,     // 目的寄存器索引（5-bit）
    input  wire [ 4:0] alloc_rj_index_idx1,     // 源操作数 rj 的寄存器索引
    input  wire [ 4:0] alloc_rk_index_idx1,     // 源操作数 rk 的寄存器索引
    // 源操作数信息（来自 RMT）
    input  wire        alloc_rj_ready_idx1,   // 源1 是否已就绪（可直接从 ARF 取值）
    input  wire [ 2:0] alloc_rj_rob_idx1,     // 若未就绪，等待的 ROB 索引
    input  wire [31:0] alloc_rj_value_idx1,   // 若已就绪，ARF 读出的值
    input  wire        alloc_rk_ready_idx1,
    input  wire [ 2:0] alloc_rk_rob_idx1,
    input  wire [31:0] alloc_rk_value_idx1,
    // 访存/分支附加信息（根据需要）
    input  wire        alloc_is_branch_idx1,    // 是否为分支指令
    input  wire [31:0] alloc_imm_idx1,          // 立即数（已扩展）

    // ----- 来自 CDB 的唤醒端口（每周期最多 2 个结果）-----
    input  wire        cdb_valid_idx1,
    input  wire [ 2:0] cdb_rob_idx_idx1,
    input  wire [31:0] cdb_value_idx1,

    // ----- 发射到执行单元的接口（每周期最多 2 条指令）-----
    output reg        issue_valid_idx1,
    output reg [82:0] issue_op_idx1,
    output reg [31:0] issue_rj_idx1,
    output reg [31:0] issue_rk_idx1,
    output reg [ 2:0] issue_rob_idx_idx1,
    output reg [31:0] issue_pc_idx1,
    output reg        issue_is_branch_idx1,
    output reg [31:0] issue_imm_idx1,
    output reg [1:0]  issue_fu_type_idx1,
    output reg [4:0]  issue_rd_index_idx1,     // 发射的rd索引
    output reg [4:0]  issue_rj_index_idx1,     // 发射的 rj 索引
    output reg [4:0]  issue_rk_index_idx1,     // 发射的 rk 索引

   // ----- 来自功能单元的状态（空闲/忙）-----
    input  wire        fu_alu0_ready,
    input  wire        fu_alu1_ready,
    input  wire        fu_mul_ready,
    input  wire        fu_div_ready,
    input  wire        fu_lsu_ready,
    
    // ----- 反压前端 -----
    output wire        full,                   // 队列满（无法再接新指令）
    output wire        almost_full             // 可选，只剩 1 个空闲
    );

//发射队列内部的寄存器阵列
reg        valid[0:7];           // 该条目有效
reg [31:0] pc[0:7];
reg [82:0] op[0:7];             //这个op已经包含了：b_opcode,aluopcode，alu_selcode，div,mul,lsu所有的操作信息
reg [ 1:0] fu_type[0:7];         // 00-alu,01-mul,10-div ,11-lsu
reg [ 2:0] rob_idx[0:7];         // 目的 ROB 索引,该条指令所在的rob索引
reg [ 4:0] rd_index[0:7];       // 目的寄存器索引（5-bit）
reg [ 4:0] rj_index[0:7];       // 源操作数 rj 的寄存器索引
reg [ 4:0] rk_index[0:7];       // 源操作数 rk 的寄存器索引
// 源操作数 1
reg        rj_ready[0:7];   
reg [ 2:0] rj_rob[0:7];         //rj源操作数需要从哪个rob索引中获得数据
reg [31:0] rj_value[0:7];
// 源操作数 2
reg        rk_ready[0:7];
reg [ 2:0] rk_rob[0:7];         //rk源操作数应该从哪个rob索引中获得数据
reg [31:0] rk_value[0:7];
// 附加
reg        is_branch[0:7];
reg [31:0] imm[0:7];            //发射队列中的imm是包含了imm32和offs32的，alu指令发射出去的是imm32，分支指令发射出去的是offs32
//用来控制读写的指针，由于是压缩队列，所以写指针永远在队尾
reg [3:0] tail; //控制反压信号，写入的指针变成了idx_next

integer  i ;
//cdb唤醒逻辑
reg          rj_ready_comb [0:7];
reg [31:0]   rj_value_comb [0:7];
reg          rk_ready_comb [0:7];
reg [31:0]   rk_value_comb [0:7];
//组合逻辑
always@(*)begin
    for (i = 0 ; i < 'd8 ; i = i +'d1 )begin
        rj_ready_comb[i] = rj_ready[i]; //对组合逻辑进行赋初始值，将队列中的ready和value信号赋值给comb，之后再进行cdb匹配，覆盖对应额ready和value
        rj_value_comb[i] = rj_value[i];
        rk_ready_comb[i] = rk_ready[i];
        rk_value_comb[i] = rk_value[i];

        //rj匹配
        if( !rj_ready[i] ) begin//只有在rj_ready被置为0的情况下才需要去从rob获取数据
            if(cdb_valid_idx0 && cdb_rob_idx_idx0 == rj_rob[i] )begin
                rj_ready_comb[i] = 1'b1;
                rj_value_comb[i] = cdb_value_idx0;
            end
            else if (cdb_valid_idx1 && cdb_rob_idx_idx1 == rj_rob[i])begin
                rj_ready_comb[i] = 1'b1;
                rj_value_comb[i] = cdb_value_idx1;
            end
        end
        //rk匹配
        if( !rk_ready[i] ) begin 
            if(cdb_valid_idx0 && cdb_rob_idx_idx0 == rk_rob[i] )begin
                rk_ready_comb[i] = 1'b1;
                rk_value_comb[i] = cdb_value_idx0;
            end
            else if (cdb_valid_idx1 && cdb_rob_idx_idx1 == rk_rob[i])begin
                rk_ready_comb[i] = 1'b1;
                rk_value_comb[i] = cdb_value_idx1;
            end
        end
        
    end

end

//选择逻辑
wire [3:0] head0;
wire [3:0] head1;
wire [7:0] ready_masked0;

//生成发射就绪标记，组合逻辑
wire [7:0] ready_comb;
genvar g;
generate 
    for(g = 0 ; g < 8 ; g = g + 'd1 )begin: gen_ready
        assign ready_comb[g] = valid[g] && rj_ready_comb[g] && rk_ready_comb[g]; 
    end
endgenerate

//lsu顺序发射，阻塞逻辑
reg lsu_block [0:7];
integer j ,k;
always@(*)begin
    for(j = 0 ; j <8 ; j = j+'d1)begin
        lsu_block[j] = 0;
        for (k = 0 ; k <j ; k = k+ 'd1)begin
            if(valid[k] && fu_type[k] == 2'b11  &&  (head0 != k && head1 != k ) )  //当前面存在lsu指令，并且不是本周期要发射的指令的时候，阻塞当前的lsu指令
            //当0~j-1的指令中有有效的，lsu指令，该周期不发射的，置位为1表示阻塞该条lsu指令发射。
            lsu_block[j] = 1'b1;
            // else lsu_block[j] = 1'b0;
        end
    end
end

assign ready_masked0 = ready_comb;
assign head0 = ready_masked0[0] ? 4'd0 :
                ready_masked0[1] ? 4'd1 :
                ready_masked0[2] ? 4'd2 :
                ready_masked0[3] ? 4'd3 :
                ready_masked0[4] ? 4'd4 :
                ready_masked0[5] ? 4'd5 :
                ready_masked0[6] ? 4'd6 :
                ready_masked0[7] ? 4'd7 : 4'd8;

wire [7:0] ready_masked2;
assign ready_masked2 = ready_comb & ~(8'b1 << head0);    //将head0选中的那条指令进行屏蔽
assign head1 = (head0 == 4'd8) ? 4'd8 :
                ready_masked2[0] ? 4'd0 :
                ready_masked2[1] ? 4'd1 :
                ready_masked2[2] ? 4'd2 :
                ready_masked2[3] ? 4'd3 :
                ready_masked2[4] ? 4'd4 :
                ready_masked2[5] ? 4'd5 :
                ready_masked2[6] ? 4'd6 :
                ready_masked2[7] ? 4'd7 : 4'd8;

//fu单元的分配和发射使能
wire fu_avail0,fu_avail1;

assign fu_avail0 = (head0 == 4'd8 )  ? 1'b0 :
        (fu_type[head0] == 2'b00)   ? (fu_alu0_ready ) :
        (fu_type[head0] == 2'b01)   ? fu_mul_ready :
        (fu_type[head0] == 2'b10)   ? fu_div_ready :
        (fu_type[head0] == 2'b11)   ? (fu_lsu_ready && !lsu_block[head0]) : 1'b0;

wire same_fu_type = (head0 != 4'd8) && head1 != 4'd8 && fu_type[head1] == fu_type[head0];
assign fu_avail1 =  (head1 == 'd8 ) ?  1'b0  :
                        (fu_type[head1] == 2'b00 ) ? (     fu_alu1_ready    )                          //在第二条指令为alu类型的指令            
                                            :                             
                        (fu_type[head1] == 2'b01 ) ? (fu_mul_ready && !(same_fu_type && fu_avail0)):
                        (fu_type[head1] == 2'b10 ) ? (fu_div_ready && !(same_fu_type && fu_avail0)):
                        (fu_type[head1] == 2'b11 ) ? (fu_lsu_ready && !(same_fu_type && fu_avail0) && !lsu_block[head1]): 1'b0;

                    
wire issue0_valid = (head0 != 4'd8) && fu_avail0 ;
wire issue1_valid = (head1 != 4'd8) && fu_avail1 ;

//发射逻辑输出：
always@(*)begin

        issue_valid_idx0         = 1'b0;
        issue_op_idx0            = 83'b0;
        issue_rj_idx0            = 32'd0;
        issue_rk_idx0            = 32'd0;
        issue_rob_idx_idx0       = 3'b0;
        issue_pc_idx0            = 32'b0;
        issue_is_branch_idx0     = 1'b0;
        issue_imm_idx0           = 32'd0;

        issue_fu_type_idx0      = 2'b0; //默认alu
        issue_rd_index_idx0     = 5'b0;
        issue_rj_index_idx0     = 5'b0;
        issue_rk_index_idx0     = 5'b0;

    if( issue0_valid  )begin
        issue_valid_idx0         = valid[head0];
        issue_op_idx0            = op[head0];
        issue_rj_idx0            = rj_value_comb[head0];
        issue_rk_idx0            = rk_value_comb[head0];
        issue_rob_idx_idx0       = rob_idx[head0];
        issue_pc_idx0            = pc[head0];
        issue_is_branch_idx0     = is_branch[head0];
        issue_imm_idx0           = imm[head0];

        issue_fu_type_idx0      = fu_type[head0];
        issue_rd_index_idx0     = rd_index[head0];
        issue_rj_index_idx0     = rj_index[head0];
        issue_rk_index_idx0     = rk_index[head0];
    end

    
end

always@(*)begin

    issue_valid_idx1         = 1'b0;
    issue_op_idx1            = 83'b0;
    issue_rj_idx1            = 32'd0;
    issue_rk_idx1            = 32'd0;
    issue_rob_idx_idx1       = 3'b0;
    issue_pc_idx1            = 32'b0;
    issue_is_branch_idx1     = 1'b0;
    issue_imm_idx1           = 32'd0;
    issue_fu_type_idx1      = 2'b0; //默认alu
    issue_rd_index_idx1     = 5'b0;
    issue_rj_index_idx1     = 5'b0;
    issue_rk_index_idx1     = 5'b0;
    if( issue1_valid )begin
        issue_valid_idx1         = valid[head1];
        issue_op_idx1            = op[head1];
        issue_rj_idx1            = rj_value_comb[head1];
        issue_rk_idx1            = rk_value_comb[head1];
        issue_rob_idx_idx1       = rob_idx[head1];
        issue_pc_idx1            = pc[head1];
        issue_is_branch_idx1     = is_branch[head1];
        issue_imm_idx1           = imm[head1];
        issue_fu_type_idx1      = fu_type[head1]; 
        issue_rd_index_idx1     = rd_index[head1];
        issue_rj_index_idx1     = rj_index[head1];
        issue_rk_index_idx1     = rk_index[head1];
    end
end

assign full = tail >= 3'd7;
assign almost_full = tail == 3'd6;

//压缩逻辑
integer c;
reg [7:0] keep_mask ;   //1-保留，0-发射
//通过临时队列来完成压缩
    reg         t_valid     [0:7];
    reg [31:0]  t_pc        [0:7];
    reg [82:0]  t_op        [0:7];
    reg [ 1:0]  t_fu_type   [0:7];
    reg [ 2:0]  t_rob_idx   [0:7];
    reg [ 4:0]  t_rd_index  [0:7];
    reg [ 4:0]  t_rj_index  [0:7];
    reg [ 4:0]  t_rk_index  [0:7];
    reg         t_rj_ready  [0:7];
    reg [ 2:0]  t_rj_rob    [0:7];
    reg [31:0]  t_rj_value  [0:7];
    reg         t_rk_ready  [0:7];
    reg [ 2:0]  t_rk_rob    [0:7];
    reg [31:0]  t_rk_value  [0:7];
    reg         t_is_branch [0:7];
    reg [31:0]  t_imm       [0:7];
    reg [3:0] idx_next;

//将t_xx 组合逻辑和 时序逻辑分离
integer x;
always@(*)begin
    for( x = 0 ; x < 8; x = x + 'd1)begin
        t_valid    [x] = 1'b0;
        t_pc       [x]  = 32'b0;
        t_op       [x]  = 83'b0;
        t_fu_type  [x]  = 2'b0;
        t_rob_idx  [x]  = 3'b0;
        t_rd_index [x]  = 5'b0;
        t_rj_index [x]  = 5'b0;
        t_rk_index [x]  = 5'b0;
        t_rj_ready [x]  = 1'b0;
        t_rj_rob   [x]  = 3'b0;
        t_rj_value [x]  = 32'b0;
        t_rk_ready [x]  = 1'b0;
        t_rk_rob   [x]  = 3'b0;
        t_rk_value [x]  = 32'b0;
        t_is_branch[x]  = 1'b0;
        t_imm      [x]  = 32'b0;

    end
    keep_mask = 8'b0;
    for( x = 0 ; x <'d8 ;  x = x + 'd1)begin
        if ( valid[x] )begin
            if(issue0_valid == 1 && x == head0 ) keep_mask[x] = 1'b0;   //将掩码设置好
            else if (issue1_valid && x == head1) keep_mask[x] = 1'b0;
            else keep_mask[x] = 1'b1;
        end 
    end
    idx_next = 'd0 ;
    //根据掩码填入要保留的指令进入到临时队列
    for(x = 0 ; x < 'd8 ; x = x+ 'd1)begin
        if(keep_mask[x]) begin
                t_valid[idx_next]     = 1'b1;
                t_pc[idx_next]        = pc[x];
                t_op[idx_next]        = op[x];
                t_fu_type[idx_next]   = fu_type[x];
                t_rob_idx[idx_next]   = rob_idx[x];
                t_rd_index[idx_next]  = rd_index[x];
                t_rj_index[idx_next]  = rj_index[x];
                t_rk_index[idx_next]  = rk_index[x];
                t_rj_ready[idx_next]  = rj_ready_comb[x];   // 使用最新的就绪状态
                t_rj_rob[idx_next]    = rj_rob[x];
                t_rj_value[idx_next]  = rj_value_comb[x];
                t_rk_ready[idx_next]  = rk_ready_comb[x];
                t_rk_rob[idx_next]    = rk_rob[x];
                t_rk_value[idx_next]  = rk_value_comb[x];
                t_is_branch[idx_next] = is_branch[x];
                t_imm[idx_next]       = imm[x];
                idx_next = idx_next + 1;    //原来的idx_next是三位的,当写满的时候,idx_next = 7 ,此时在将压缩队列写回去的时候,idx_next溢出为0了,不会写进队列里面
        end
    end
    //追加新的两条指令
        if ( alloc_en_idx0 && idx_next < 'd8 ) begin
               t_valid[idx_next]         = 1;
               t_pc[idx_next]            = alloc_pc_idx0;
               t_op[idx_next]            = alloc_op_idx0;
               t_fu_type[idx_next]       = alloc_fu_type_idx0;
               t_rob_idx[idx_next]       = alloc_rob_idx_idx0;
               t_rd_index[idx_next]      = alloc_rd_index_idx0;
               t_rj_index[idx_next]      = alloc_rj_index_idx0;
               t_rk_index[idx_next]      = alloc_rk_index_idx0;

               t_rj_ready[idx_next]        = alloc_rj_ready_idx0;
               t_rj_rob[idx_next]          = alloc_rj_rob_idx0;   
               t_rj_value[idx_next]        = alloc_rj_value_idx0;
               t_rk_ready[idx_next]        = alloc_rk_ready_idx0;
               t_rk_rob[idx_next]          = alloc_rk_rob_idx0;   
               t_rk_value[idx_next]        = alloc_rk_value_idx0;

               t_is_branch[idx_next]       = alloc_is_branch_idx0;
               t_imm[idx_next]             = alloc_imm_idx0;
               idx_next                 = idx_next + 'd1;

        end
        if ( alloc_en_idx1 && idx_next < 'd8 )begin //只有当队列还有空间，使能的时候才可以再继续写入第二条指令
            t_valid[idx_next]           = 1;
            t_pc[idx_next]              = alloc_pc_idx1;
            t_op[idx_next]              = alloc_op_idx1;
            t_fu_type[idx_next]         = alloc_fu_type_idx1;
            t_rob_idx[idx_next]         = alloc_rob_idx_idx1;
            t_rd_index[idx_next]        = alloc_rd_index_idx1;
            t_rj_index[idx_next]        = alloc_rj_index_idx1;
            t_rk_index[idx_next]        = alloc_rk_index_idx1;

            t_rj_ready[idx_next]        = alloc_rj_ready_idx1;
            t_rj_rob[idx_next]          = alloc_rj_rob_idx1;   
            t_rj_value[idx_next]        = alloc_rj_value_idx1;
            t_rk_ready[idx_next]        = alloc_rk_ready_idx1;
            t_rk_rob[idx_next]          = alloc_rk_rob_idx1;   
            t_rk_value[idx_next]        = alloc_rk_value_idx1;

            t_is_branch[idx_next]       = alloc_is_branch_idx1;
            t_imm[idx_next]             = alloc_imm_idx1;
            idx_next                 = idx_next + 'd1;
        end

end

always@(posedge clk or negedge rstn) begin
    if (!rstn) begin
        // 重置所有条目
        for (c = 0; c < 8; c = c + 1) begin
            valid[c]         <= 0;
            pc[c]            <= 0;
            op[c]            <= 0;
            fu_type[c]       <= 0;
            rob_idx[c]       <= 0;
            rd_index[c]      <= 0;
            rj_index[c]      <= 0;
            rk_index[c]      <= 0;
            rj_ready[c]      <= 0;
            rj_rob[c]        <= 0;
            rj_value[c]      <= 0;
            rk_ready[c]      <= 0;
            rk_rob[c]        <= 0;
            rk_value[c]      <= 0;
            is_branch[c]     <= 0;
            imm[c]           <= 0;
        end
        tail <= 3'd0;

    end 
    else if (flush) begin
        // 冲刷：清空所有条目
        for (c = 0; c < 'd8; c = c + 1) begin
            valid[c] <= 0;
        end
        tail <= 3'd0;
    end 
    else begin
        // 所存cdb唤醒结果，将组合逻辑数据写入寄存器
        for (c = 0 ; c <8 ; c = c + 'd1)begin
            //将临时压缩好的队列写回进发射队列
            if( c < idx_next )begin
                valid[c]        <=  t_valid[c];
                pc[c]           <= t_pc[c];
                op[c]           <= t_op[c];
                fu_type[c]      <= t_fu_type[c];
                rob_idx[c]      <= t_rob_idx[c];
                rd_index[c]     <= t_rd_index[c];
                rj_index[c]     <= t_rj_index[c];
                rk_index[c]     <= t_rk_index[c];
                rj_ready[c]     <= t_rj_ready[c];
                rj_rob[c]       <= t_rj_rob[c];
                rj_value[c]     <= t_rj_value[c];
                rk_ready[c]     <= t_rk_ready[c];
                rk_rob[c]       <= t_rk_rob[c];
                rk_value[c]     <= t_rk_value[c];
                is_branch[c]    <= t_is_branch[c];
                imm[c]          <= t_imm[c];
            end
            else begin
                valid [c] <= 1'b0;
            end

        end
        tail <= idx_next ;
    end
end

    
endmodule