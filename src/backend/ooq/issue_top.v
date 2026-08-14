`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/20 13:11:19
// Design Name: 
// Module Name: issue_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 发射模块的顶层，发射模块应该包含发射队列（包含发射算法），寄存器映射表（完成寄存器管理，主要是真相关性的解决）
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module issue_top(
    input wire clk,
    input wire rstn,
    input wire flush,       //flush信号应该从rob提交的过程中开始得到
    //从译码模块过来的数据
    //inst0
    input wire          i_alloc_en_idx0,
    input wire [31:0]   i_pc_idx0,
    input wire [82:0]   i_op_idx0,
    input wire [1:0]    i_fu_type_idx0,
    input wire [2:0]    i_rob_idx_idx0,     
    input wire          i_id_rj_ready_idx0, i_id_rk_ready_idx0,
    input wire [2:0]    i_rob_rj_idx0, i_rob_rk_idx0,
    input wire [31:0]   i_rj_value_idx0,i_rk_value_idx0,
    input wire          i_is_branch_idx0,
    input wire [31:0]   i_imm0,
    //新加rd
    input wire [4:0]    i_rj_index_idx0,  i_rk_index_idx0, i_rd_index_idx0 ,

    //inst1
    input wire          i_alloc_en_idx1,
    input wire [31:0]   i_pc_idx1,
    input wire [82:0]   i_op_idx1,
    input wire [1:0]    i_fu_type_idx1,
    input wire [2:0]    i_rob_idx_idx1,
    input wire          i_id_rj_ready_idx1,i_id_rk_ready_idx1,
    input wire [2:0]    i_rob_rj_idx1, i_rob_rk_idx1,
    input wire [31:0]   i_rj_value_idx1,i_rk_value_idx1,
    input wire          i_is_branch_idx1,
    input wire [31:0]   i_imm1,
    input wire [4:0]    i_rj_index_idx1, i_rk_index_idx1, i_rd_index_idx1 ,
    //输出给exe的数据(从iq控制发射，这里只连线) ，执行单元有两个alu，一个乘法，一个除法

    //cdb写回
    input wire          i_cdb_valid_idx0,i_cdb_valid_idx1,
    input wire [2:0]    i_cdb_rob_idx_idx0,i_cdb_rob_idx_idx1,
    input wire [31:0]   i_cdb_value_idx0,i_cdb_value_idx1,

    output wire [465:0] o_2_exe_466,
    
    
    input wire i_exe_alu0_ready,
    input wire i_exe_alu1_ready,
    input wire i_exe_div_ready ,
    input wire i_exe_mul_ready ,
    input wire i_exe_lsu_ready ,

    // output wire [5:0] fu_sel ,   //低三位为idx0的端口，高三位为idx1
    // output reg o_exe_alu0_vld,
    // output reg o_exe_alu1_vld,
    // output reg o_exe_lsu_vld ,
    // output reg o_exe_div_vld ,
    // output reg o_exe_mul_vld ,
    //反压信号
    output wire o_iq_full ,
    output wire o_iq_almost_full

    );
    wire        o_issue_vld0 ,  o_issue_vld1 ;  
    wire [31:0] o_rj0,          o_rj1; //rj和rk的value
    wire [31:0] o_rk0,          o_rk1;
    wire [31:0] o_imm0,         o_imm1;    //译码拓展完成的立即数，都为32位
    wire [82:0] o_op0 ,         o_op1 ;         
    wire [2:0]  o_rob0 ,        o_rob1 ;   //这个索引是指这条指令对应的rob索引，这个索引会一直随着指令知道提交的时候
    wire [31:0] o_pc0,          o_pc1  ;
    wire        o_is_branch0,   o_is_branch1;
    wire [4:0]  o_rd_index_idx0, o_rd_index_idx1;
    wire [4:0]  o_rj_index_idx0, o_rk_index_idx0;
    wire [4:0]  o_rj_index_idx1, o_rk_index_idx1;

    //执行单元的信息
    wire [1:0] o_fu_idx0, o_fu_idx1 ;

    // 输出总线重新拼接，包含新增的索引信号
assign o_2_exe_466 = { //相较于从译码得到的460位数据，多的6位是rob的索引
    // ---- idx1 字段 ----
    o_issue_vld1,        // [465]
    o_rj1,               // [464:433]
    o_rk1,               // [432:401]
    o_imm1,              // [400:369]
    o_op1,               // [368:286]
    o_rob1,              // [285:283]
    o_pc1,               // [282:251]
    o_is_branch1,        // [250]
    o_fu_idx1,           // [249:248]
    o_rj_index_idx1,     // [247:243]
    o_rk_index_idx1,     // [242:238]
    o_rd_index_idx1,     // [237:233]

    // ---- idx0 字段 ----
    o_issue_vld0,        // [232]
    o_rj0,               // [231:200]
    o_rk0,               // [199:168]
    o_imm0,              // [167:136]
    o_op0,               // [135:53]
    o_rob0,              // [52:50]
    o_pc0,               // [49:18]
    o_is_branch0,        // [17]
    o_fu_idx0,           // [16:15]
    o_rj_index_idx0,     // [14:10]
    o_rk_index_idx0,     // [9:5]
    o_rd_index_idx0      // [4:0]
};
    IQ IQ_inst(
        .clk                    (clk),
        .rstn                   (rstn),
        .flush                  (flush),
        //instr0
        .alloc_en_idx0          ( i_alloc_en_idx0        ),
        .alloc_pc_idx0          ( i_pc_idx0              ),   
        .alloc_op_idx0          ( i_op_idx0              ),
        .alloc_fu_type_idx0     ( i_fu_type_idx0         ),
        .alloc_rob_idx_idx0     ( i_rob_idx_idx0         ),
        .alloc_rd_index_idx0    ( i_rd_index_idx0        ), //rd的索引是指这条指令的目的寄存器的索引，分发阶段disp对于信息分配很重要        
        .alloc_rj_index_idx0    ( i_rj_index_idx0           ),
        .alloc_rk_index_idx0    ( i_rk_index_idx0           ),
        .alloc_rj_ready_idx0    ( i_id_rj_ready_idx0     ),
        .alloc_rj_rob_idx0      ( i_rob_rj_idx0          ),
        .alloc_rj_value_idx0    ( i_rj_value_idx0        ),
        .alloc_rk_ready_idx0    ( i_id_rk_ready_idx0     ),
        .alloc_rk_rob_idx0      ( i_rob_rk_idx0          ),
        .alloc_rk_value_idx0    ( i_rk_value_idx0        ),

        .alloc_is_branch_idx0   ( i_is_branch_idx0       ),
        .alloc_imm_idx0         ( i_imm0                 ),
        .cdb_valid_idx0         ( i_cdb_valid_idx0       ),
        .cdb_rob_idx_idx0       ( i_cdb_rob_idx_idx0     ),
        .cdb_value_idx0         ( i_cdb_value_idx0       ),

        .issue_valid_idx0       ( o_issue_vld0           ),
        .issue_op_idx0          ( o_op0                  ),
        .issue_rj_idx0          ( o_rj0                  ),
        .issue_rk_idx0          ( o_rk0                  ),
        .issue_rob_idx_idx0     ( o_rob0                 ),
        .issue_pc_idx0          ( o_pc0                  ),
        .issue_is_branch_idx0   ( o_is_branch0           ),
        .issue_imm_idx0         ( o_imm0                 ),
        .issue_fu_type_idx0     ( o_fu_idx0              ),
        .issue_rd_index_idx0    ( o_rd_index_idx0        ),
        .issue_rj_index_idx0    ( o_rj_index_idx0        ),
        .issue_rk_index_idx0    ( o_rk_index_idx0        ),

        //instr1
        .alloc_en_idx1          ( i_alloc_en_idx1        ),
        .alloc_pc_idx1          ( i_pc_idx1              ),   
        .alloc_op_idx1          ( i_op_idx1              ),
        .alloc_fu_type_idx1     ( i_fu_type_idx1         ),
        .alloc_rob_idx_idx1     ( i_rob_idx_idx1         ),
        .alloc_rd_index_idx1    ( i_rd_index_idx1        ),   
        .alloc_rj_index_idx1    ( i_rj_index_idx1           ),
        .alloc_rk_index_idx1    ( i_rk_index_idx1           ),
        .alloc_rj_ready_idx1    ( i_id_rj_ready_idx1     ),
        .alloc_rj_rob_idx1      ( i_rob_rj_idx1          ),
        .alloc_rj_value_idx1    ( i_rj_value_idx1        ),
        .alloc_rk_ready_idx1    ( i_id_rk_ready_idx1     ),
        .alloc_rk_rob_idx1      ( i_rob_rk_idx1          ),
        .alloc_rk_value_idx1    ( i_rk_value_idx1        ),

        .alloc_is_branch_idx1   ( i_is_branch_idx1       ),
        .alloc_imm_idx1         ( i_imm1                 ),
        .cdb_valid_idx1         ( i_cdb_valid_idx1       ),
        .cdb_rob_idx_idx1       ( i_cdb_rob_idx_idx1     ),
        .cdb_value_idx1         ( i_cdb_value_idx1       ),

        .issue_valid_idx1       ( o_issue_vld1           ),
        .issue_op_idx1          ( o_op1                  ),
        .issue_rj_idx1          ( o_rj1                  ),
        .issue_rk_idx1          ( o_rk1                  ),
        .issue_rob_idx_idx1     ( o_rob1                 ),
        .issue_pc_idx1          ( o_pc1                  ),
        .issue_is_branch_idx1   ( o_is_branch1           ),
        .issue_imm_idx1         ( o_imm1                 ),
        .issue_fu_type_idx1     ( o_fu_idx1              ),
        .issue_rd_index_idx1    ( o_rd_index_idx1        ),
        .issue_rj_index_idx1    ( o_rj_index_idx1        ),
        .issue_rk_index_idx1    ( o_rk_index_idx1        ),

        .fu_alu0_ready          ( i_exe_alu0_ready       ),
        .fu_alu1_ready          ( i_exe_alu1_ready       ),
        .fu_mul_ready           ( i_exe_mul_ready        ),
        .fu_div_ready           ( i_exe_div_ready        ),
        .fu_lsu_ready           ( i_exe_lsu_ready        ),

        //反压信号
        .full                   ( o_iq_full              ),
        .almost_full            ( o_iq_almost_full       )

    );

endmodule