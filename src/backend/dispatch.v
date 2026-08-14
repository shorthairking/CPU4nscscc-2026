`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: dispatch_v2
// Description: Two-stage dispatch (D0: GRF read + RMT lookup, D1: IQ write)
//添加了操作数ready信号的逻辑，方便发射队列发射逻辑的生成
//////////////////////////////////////////////////////////////////////////////////
module dispatch (
    input  wire        clk,
    input  wire        rstn,
    input  wire        flush,

    // ---- ID 数据包（460bit） ----
    input  wire [459:0] i_from_id_data_460,

    // ---- 容量状态 ----
    // input  wire [2:0]  i_rob_tail,
    input wire [2:0] i_rob_idx0,  // 来自 ROB 的 disp_index0
    input wire [2:0] i_rob_idx1,  // 来自 ROB 的 disp_index1
    input  wire        i_rob_full,
    input  wire        i_rob_almost_full,
    input  wire        i_iq_full,
    input  wire        i_iq_almost_full,

    // ---- GRF 读数据（异步读，来自顶层 GRF） ----
    input  wire [31:0] i_grf_rj_data0,
    input  wire [31:0] i_grf_rk_data0,
    input  wire [31:0] i_grf_rj_data1,
    input  wire [31:0] i_grf_rk_data1,

    // ---- RMT 查询结果（组合逻辑，来自顶层 RMT） ----
    input  wire        i_rmt_rj_ready0,
    input  wire        i_rmt_rk_ready0,
    input  wire [2:0]  i_rmt_rj_rob0,
    input  wire [2:0]  i_rmt_rk_rob0,
    input  wire        i_rmt_rj_ready1,
    input  wire        i_rmt_rk_ready1,
    input  wire [2:0]  i_rmt_rj_rob1,
    input  wire [2:0]  i_rmt_rk_rob1,

    // ---- 停顿信号给 ID ----
    output reg         o_stall_id,

    // ---- 输出到 ROB ----
    output wire [1:0]  o_2_rob_disp_en,
    output wire [31:0] o_2_rob_pc0,
    output wire [31:0] o_2_rob_pc1,
    output wire [4:0]  o_2_rob_rd0,
    output wire [4:0]  o_2_rob_rd1,
    output wire [1:0]  o_2_rob_is_branch,
    output wire [1:0]  o_2_rob_pred_taken,
    output wire [31:0] o_2_rob_pred_target0,
    output wire [31:0] o_2_rob_pred_target1,
    output wire [5:0]  o_2_rob_op_lsu0,
    output wire [5:0]  o_2_rob_op_lsu1,
    output wire        o_2_rob_tlb_sign0,
    output wire        o_2_rob_tlb_sign1,
    output wire        o_2_rob_grf_we0 ,
    output wire        o_2_rob_grf_we1 ,
    output wire        o_2_rob_cacop0 ,
    output wire        o_2_rob_cacop1 ,

    //与csr相关的信息
    // 新增输出到 ROB 的 CSR 信息
    output wire [1:0]  o_2_rob_disp_is_csr,     // {is_csr1, is_csr0}
    output wire [1:0]  o_2_rob_csr_op0,
    output wire [13:0] o_2_rob_csr_num0,
    // output wire [31:0] o_2_rob_csr_wdata0,      // 即 i_grf_rk_data0（规定将rd的索引放到rk 位置，得到的rd旧值为rk的value）
    // output wire [31:0] o_2_rob_csr_mask0,       // 即 i_grf_rj_data0（掩码本就在 rj 位置）
    output wire [1:0]  o_2_rob_csr_op1,
    output wire [13:0] o_2_rob_csr_num1,
    // output wire [31:0] o_2_rob_csr_wdata1,
    // output wire [31:0] o_2_rob_csr_mask1 ,

    // ---- 输出到 IQ (alloc interface) ----
    output wire        o_2_iq_alloc_en_idx0,
    output wire [31:0] o_2_iq_pc_idx0,
    output wire [82:0] o_2_iq_op_idx0,
    output wire [ 1:0] o_2_iq_fu_type_idx0,
    output wire [ 2:0] o_2_iq_rob_idx_idx0,
    output wire [ 4:0] o_2_iq_rd_index_idx0,
    output wire [ 4:0] o_2_iq_rj_index_idx0,
    output wire [ 4:0] o_2_iq_rk_index_idx0,
    output wire        o_2_iq_rj_ready_idx0,
    output wire [ 2:0] o_2_iq_rj_rob_idx0,
    output wire [31:0] o_2_iq_rj_value_idx0,
    output wire        o_2_iq_rk_ready_idx0,
    output wire [ 2:0] o_2_iq_rk_rob_idx0,
    output wire [31:0] o_2_iq_rk_value_idx0,
    output wire        o_2_iq_is_branch_idx0,
    output wire [31:0] o_2_iq_imm_idx0,

    output wire        o_2_iq_alloc_en_idx1,
    output wire [31:0] o_2_iq_pc_idx1,
    output wire [82:0] o_2_iq_op_idx1,
    output wire [ 1:0] o_2_iq_fu_type_idx1,
    output wire [ 2:0] o_2_iq_rob_idx_idx1,
    output wire [ 4:0] o_2_iq_rd_index_idx1,
    output wire [ 4:0] o_2_iq_rj_index_idx1,
    output wire [ 4:0] o_2_iq_rk_index_idx1,
    output wire        o_2_iq_rj_ready_idx1,
    output wire [ 2:0] o_2_iq_rj_rob_idx1,
    output wire [31:0] o_2_iq_rj_value_idx1,
    output wire        o_2_iq_rk_ready_idx1,
    output wire [ 2:0] o_2_iq_rk_rob_idx1,
    output wire [31:0] o_2_iq_rk_value_idx1,
    output wire        o_2_iq_is_branch_idx1,
    output wire [31:0] o_2_iq_imm_idx1,

    // ---- 输出给 GRF 的读地址 ----
    output wire [4:0]  o_2_grf_rj_addr0,
    output wire [4:0]  o_2_grf_rk_addr0,
    output wire [4:0]  o_2_grf_rj_addr1,
    output wire [4:0]  o_2_grf_rk_addr1,

    // ---- 输出给 RMT 的查询与更新接口 ----
    output wire [4:0]  o_2_rmt_rj0,
    output wire [4:0]  o_2_rmt_rk0,
    output wire [4:0]  o_2_rmt_rj1,
    output wire [4:0]  o_2_rmt_rk1,
    output wire        o_2_rmt_wen0,
    output wire        o_2_rmt_wen1,
    output wire [4:0]  o_2_rmt_rd0,
    output wire [4:0]  o_2_rmt_rd1,
    output wire [2:0]  o_2_rmt_rob_idx0,
    output wire [2:0]  o_2_rmt_rob_idx1 ,

    input  wire        i_from_id_valid , //从译码过来的指令有效信号
    /**D0-n级数据旁路*/
    //为了解决w指令先执行，r指令后进入发射队列的问题，在第一级寄存器得到rj和rk需要从rob中的索引，用这个索引去查询rob的done和data
    input  wire        rj_rob_done0,
    input  wire        rk_rob_done0,
    input  wire        rj_rob_done1,
    input  wire        rk_rob_done1,

    output wire [2:0]  o_rj_rob_index0 ,
    output wire [2:0]  o_rk_rob_index0 ,
    output wire [2:0]  o_rj_rob_index1 ,
    output wire [2:0]  o_rk_rob_index1 ,
   

    input  wire [31:0] i_rj_robdone_data0 ,
    input  wire [31:0] i_rk_robdone_data0 ,
    input  wire [31:0] i_rj_robdone_data1 ,
    input  wire [31:0] i_rk_robdone_data1 ,
    /*D0级数据旁路*/
    //提交与分发同周期的raw解决：此时查rmt表是得到ready为1的，但是不能拿grf的数据，应该拿com_data的数据
    input wire  [31:0] raw_com_data,
    input wire  [4:0]  raw_com_rd  ,
    //exe-dispatch -raw
    output wire [2:0]     disp_2_exe_rob_idx_rj0 ,
    output wire [2:0]     disp_2_exe_rob_idx_rk0 ,
    output wire [2:0]     disp_2_exe_rob_idx_rj1 ,
    output wire [2:0]     disp_2_exe_rob_idx_rk1 ,
    input  wire  [31:0]   exe_rj0_data ,         
    input  wire  [31:0]   exe_rk0_data ,         
    input  wire  [31:0]   exe_rj1_data ,         
    input  wire  [31:0]   exe_rk1_data ,         
    input  wire           exe_rj0_ready,         
    input  wire           exe_rk0_ready,         
    input  wire           exe_rj1_ready,         
    input  wire           exe_rk1_ready  ,

    // ---- D1级CDB旁路（解决exe在D1级出结果的时序窗口） ----
    input wire        i_cdb_valid0,
    input wire [2:0]  i_cdb_rob_idx0,
    input wire [31:0] i_cdb_value0,
    input wire        i_cdb_valid1,
    input wire [2:0]  i_cdb_rob_idx1,
    input wire [31:0] i_cdb_value1
           

);

    // ==================== ID 数据包拆解 ====================
    wire         inst0_preld, inst0_ertn, inst0_idle, inst0_cacop, inst0_cpucfg;
    wire [ 9:0]  inst0_tlb_data;
    wire         inst0_ex_sign;
    wire [ 5:0]  inst0_ecode;
    wire [ 7:0]  inst0_cnt_opcode;
    wire [15:0]  inst0_csr_data;
    wire         inst0_grf_no_wen;
    wire [31:0]  inst0_offs32; //不适用offs32
    wire [31:0]  inst0_imm32;   //统一到imm32
    wire [26:0]  inst0_opcode;
    wire [ 1:0]  inst0_fu_type;
    wire [ 4:0]  inst0_rj_index;
    wire [ 4:0]  inst0_rk_index;
    wire [ 4:0]  inst0_rd_index;
    wire         inst0_is_branch;
    wire         inst0_pred_taken;
    wire [31:0]  inst0_pred_target;
    wire [ 8:0]  inst0_b_insts;
    wire [31:0]  inst0_pc;

    wire         inst1_preld, inst1_ertn, inst1_idle, inst1_cacop, inst1_cpucfg;
    wire [ 9:0]  inst1_tlb_data;
    wire         inst1_ex_sign;
    wire [ 5:0]  inst1_ecode;
    wire [ 7:0]  inst1_cnt_opcode;
    wire [15:0]  inst1_csr_data;
    wire         inst1_grf_no_wen;
    wire [31:0]  inst1_offs32;
    wire [31:0]  inst1_imm32;
    wire [26:0]  inst1_opcode;
    wire [ 1:0]  inst1_fu_type;
    wire [ 4:0]  inst1_rj_index;
    wire [ 4:0]  inst1_rk_index;
    wire [ 4:0]  inst1_rd_index;
    wire         inst1_is_branch;
    wire         inst1_pred_taken;
    wire [31:0]  inst1_pred_target;
    wire [ 8:0]  inst1_b_insts;
    wire [31:0]  inst1_pc;

    // 严格按照 id_stage 输出顺序拆解 460 位
    assign { inst1_preld, inst1_ertn, inst1_idle, inst1_cacop, inst1_cpucfg,
             inst1_tlb_data, inst1_ex_sign, inst1_ecode, inst1_cnt_opcode,
             inst1_csr_data, inst1_grf_no_wen, inst1_offs32, inst1_imm32,
             inst1_opcode, inst1_fu_type, inst1_rj_index, inst1_rk_index, inst1_rd_index,
             inst1_is_branch, inst1_pred_taken, inst1_pred_target, inst1_b_insts, inst1_pc,
             inst0_preld, inst0_ertn, inst0_idle, inst0_cacop, inst0_cpucfg,
             inst0_tlb_data, inst0_ex_sign, inst0_ecode, inst0_cnt_opcode,
             inst0_csr_data, inst0_grf_no_wen, inst0_offs32, inst0_imm32,
             inst0_opcode, inst0_fu_type, inst0_rj_index, inst0_rk_index, inst0_rd_index,
             inst0_is_branch, inst0_pred_taken, inst0_pred_target, inst0_b_insts, inst0_pc
           } = i_from_id_data_460;

    // 拼接 83 位内部操作码
    wire [82:0] inst0_op_83 = { inst0_preld, inst0_ertn, inst0_idle, inst0_cacop, inst0_cpucfg,
                                inst0_tlb_data, inst0_ex_sign, inst0_ecode, inst0_cnt_opcode,
                                inst0_csr_data, inst0_grf_no_wen, inst0_b_insts, inst0_opcode };
    wire [82:0] inst1_op_83 = { inst1_preld, inst1_ertn, inst1_idle, inst1_cacop, inst1_cpucfg,
                                inst1_tlb_data, inst1_ex_sign, inst1_ecode, inst1_cnt_opcode,
                                inst1_csr_data, inst1_grf_no_wen, inst1_b_insts, inst1_opcode };


    // 写寄存器使能（需要写回 rd）
    assign  o_2_rob_grf_we0 = !inst0_grf_no_wen; // grf中已经处理了rd=0的情况
    assign  o_2_rob_grf_we1 = !inst1_grf_no_wen;

    // ==================== 流水线控制 ====================
    // reg [2:0] rob_tail;
    wire      d0_allow;
    reg       d1_valid0, d1_valid1;

    // D1 级数据缓存
    reg [31:0] d1_pc0, d1_pc1;
    reg [82:0] d1_op0, d1_op1;
    reg [ 1:0] d1_fu_type0, d1_fu_type1;
    reg [ 2:0] d1_rob_idx0, d1_rob_idx1;
    reg [ 4:0] d1_rd0, d1_rd1, d1_rj0, d1_rj1, d1_rk0, d1_rk1;
    reg        d1_rj_ready0, d1_rk_ready0, d1_rj_ready1, d1_rk_ready1;
    reg [ 2:0] d1_rj_rob0, d1_rk_rob0, d1_rj_rob1, d1_rk_rob1;
    reg [31:0] d1_rj_val0, d1_rk_val0, d1_rj_val1, d1_rk_val1;
    reg        d1_is_branch0, d1_is_branch1;
    reg [31:0] d1_imm0, d1_imm1;

    wire d1_wr_en0 = d1_valid0 && !i_iq_almost_full;
    wire d1_wr_en1 = d1_valid1 && !i_iq_almost_full;
    wire d1_can_load = (!d1_valid0) || d1_wr_en0;

    // ROB 空间判断
    wire rob_can_accept_two = !i_rob_almost_full;
    wire rob_can_accept_one = !i_rob_full;
    assign d0_allow = d1_can_load && rob_can_accept_two  && !i_iq_almost_full;

    // 停顿输出
    always @(*) begin
        o_stall_id = !d0_allow;
    end

    wire d0_valid0 = d0_allow && i_from_id_valid;
    wire d0_valid1 = d0_allow  && i_from_id_valid;

    assign o_2_rob_disp_en = {d0_valid1, d0_valid0};

    // ROB 分配索引
    wire [2:0] d0_rob_idx0 = i_rob_idx0;
    wire [2:0] d0_rob_idx1 = i_rob_idx1;


    // ==================== 输出到 ROB ====================
    assign o_2_rob_pc0 = d0_valid0 ? inst0_pc : 32'd0;
    assign o_2_rob_pc1 = d0_valid1 ? inst1_pc : 32'd0;
    assign o_2_rob_rd0 = d0_valid0 ? inst0_rd_index : 5'd0;
    assign o_2_rob_rd1 = d0_valid1 ? inst1_rd_index : 5'd0;
    assign o_2_rob_is_branch = { d0_valid1 ? inst1_is_branch : 1'b0,
                                 d0_valid0 ? inst0_is_branch : 1'b0 };
    assign o_2_rob_pred_taken = { d0_valid1 ? inst1_pred_taken : 1'b0,
                                  d0_valid0 ? inst0_pred_taken : 1'b0 };
    assign o_2_rob_pred_target0 = d0_valid0 ? inst0_pred_target : 32'd0;
    assign o_2_rob_pred_target1 = d0_valid1 ? inst1_pred_target : 32'd0;
    //rob中的csr
    wire inst0_is_csr = (inst0_csr_data[15:14] != 2'b00);
    wire inst1_is_csr = (inst1_csr_data[15:14] != 2'b00);

    assign o_2_rob_disp_is_csr = {inst1_is_csr, inst0_is_csr};

    assign o_2_rob_csr_op0    = inst0_csr_data[15:14];
    assign o_2_rob_csr_num0   = inst0_csr_data[13:0];
    // assign o_2_rob_csr_wdata0 = i_grf_rk_data0;   // rd 旧值
    // assign o_2_rob_csr_mask0  = i_grf_rj_data0;   // 掩码

    assign o_2_rob_csr_op1    = inst1_csr_data[15:14];
    assign o_2_rob_csr_num1   = inst1_csr_data[13:0];
    // assign o_2_rob_csr_wdata1 = i_grf_rk_data1;
    // assign o_2_rob_csr_mask1  = i_grf_rj_data1;

    //给rob中的op_lsu 和tlb
    assign o_2_rob_op_lsu0    = inst0_opcode[11:6];
    assign o_2_rob_op_lsu1    = inst1_opcode[11:6];
    assign o_2_rob_tlb_sign0  = (inst0_tlb_data[9:5] != 5'd0);
    assign o_2_rob_tlb_sign1  = (inst1_tlb_data[9:5] != 5'd0);
        //给rob中的cacop标识
    assign o_2_rob_cacop0 = inst0_cacop;
    assign o_2_rob_cacop1 = inst1_cacop;

    // ==================== 输出到 GRF 的读地址 ====================
    assign o_2_grf_rj_addr0 = d0_valid0 ? inst0_rj_index : 5'd0;
    assign o_2_grf_rk_addr0 = d0_valid0 ? inst0_rk_index : 5'd0;
    assign o_2_grf_rj_addr1 = d0_valid1 ? inst1_rj_index : 5'd0;
    assign o_2_grf_rk_addr1 = d0_valid1 ? inst1_rk_index : 5'd0; 

    // ==================== 输出给 RMT 的查询索引 ====================
    assign o_2_rmt_rj0 = d0_valid0 ? inst0_rj_index : 5'd0;
    assign o_2_rmt_rk0 = d0_valid0 ? inst0_rk_index : 5'd0;
    assign o_2_rmt_rj1 = d0_valid1 ? inst1_rj_index : 5'd0;
    assign o_2_rmt_rk1 = d0_valid1 ? inst1_rk_index : 5'd0; 

    // 写映射控制（下个时钟沿生效）
    assign o_2_rmt_wen0 = d0_valid0 && o_2_rob_grf_we0;
    assign o_2_rmt_wen1 = d0_valid1 && o_2_rob_grf_we1;
    assign o_2_rmt_rd0   = d0_valid0 ? inst0_rd_index : 5'd0;
    assign o_2_rmt_rd1   = d0_valid1 ? inst1_rd_index : 5'd0;
    assign o_2_rmt_rob_idx0 = d0_rob_idx0;
    assign o_2_rmt_rob_idx1 = d0_rob_idx1;
    /*D0级数据旁路*/
    assign disp_2_exe_rob_idx_rj0 = i_rmt_rj_rob0 ;
    assign disp_2_exe_rob_idx_rk0 = i_rmt_rk_rob0 ;
    assign disp_2_exe_rob_idx_rj1 = i_rmt_rj_rob1 ;
    assign disp_2_exe_rob_idx_rk1 = i_rmt_rk_rob1 ;
        // ==================== D1级 CDB 旁路（组合逻辑） ====================
    // 当D1的操作数未就绪(ready=0)，且CDB正在写回对应的ROB entry时，
    // 直接旁路CDB数据到IQ输入端口，不经过D1寄存器锁存。
    // 这处理了exe在D1级出结果，而dispatch在D0级的时序窗口。

    // inst0 rj
    wire rj0_cdb_match0 = i_cdb_valid0 && (i_cdb_rob_idx0 == d1_rj_rob0);
    wire rj0_cdb_match1 = i_cdb_valid1 && (i_cdb_rob_idx1 == d1_rj_rob0);
    wire rj0_cdb_bp     = !d1_rj_ready0 && (rj0_cdb_match0 || rj0_cdb_match1);
    wire [31:0] rj0_cdb_data = rj0_cdb_match0 ? i_cdb_value0 : i_cdb_value1;

    // inst0 rk
    wire rk0_cdb_match0 = i_cdb_valid0 && (i_cdb_rob_idx0 == d1_rk_rob0);
    wire rk0_cdb_match1 = i_cdb_valid1 && (i_cdb_rob_idx1 == d1_rk_rob0);
    wire rk0_cdb_bp     = !d1_rk_ready0 && (rk0_cdb_match0 || rk0_cdb_match1);
    wire [31:0] rk0_cdb_data = rk0_cdb_match0 ? i_cdb_value0 : i_cdb_value1;

    // inst1 rj
    wire rj1_cdb_match0 = i_cdb_valid0 && (i_cdb_rob_idx0 == d1_rj_rob1);
    wire rj1_cdb_match1 = i_cdb_valid1 && (i_cdb_rob_idx1 == d1_rj_rob1);
    wire rj1_cdb_bp     = !d1_rj_ready1 && (rj1_cdb_match0 || rj1_cdb_match1);
    wire [31:0] rj1_cdb_data = rj1_cdb_match0 ? i_cdb_value0 : i_cdb_value1;

    // inst1 rk
    wire rk1_cdb_match0 = i_cdb_valid0 && (i_cdb_rob_idx0 == d1_rk_rob1);
    wire rk1_cdb_match1 = i_cdb_valid1 && (i_cdb_rob_idx1 == d1_rk_rob1);
    wire rk1_cdb_bp     = !d1_rk_ready1 && (rk1_cdb_match0 || rk1_cdb_match1);
    wire [31:0] rk1_cdb_data = rk1_cdb_match0 ? i_cdb_value0 : i_cdb_value1;

    // ==================== D0 → D1 流水线寄存器 ====================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            d1_valid0 <= 1'b0;
            d1_valid1 <= 1'b0;
        end else if (flush) begin
            d1_valid0 <= 1'b0;
            d1_valid1 <= 1'b0;
        end else begin
            if (d1_can_load) begin
                d1_valid0 <= d0_valid0;
                d1_valid1 <= d0_valid1;
                if (d0_valid0) begin
                    d1_pc0          <= inst0_pc;
                    d1_op0          <= inst0_op_83;
                    d1_fu_type0     <= inst0_fu_type;
                    d1_rob_idx0     <= d0_rob_idx0;
                    d1_rd0          <= inst0_rd_index;
                    d1_rj0          <= inst0_rj_index;
                    d1_rk0          <= inst0_rk_index;
                    d1_rj_ready0    <= ((inst0_rj_index == 5'd0) ? 1'b1 : i_rmt_rj_ready0) || rj_rob_done0 || exe_rj0_ready;
                    d1_rk_ready0    <= ((inst0_rk_index == 5'd0) ? 1'b1 : i_rmt_rk_ready0) || rk_rob_done0 || exe_rk0_ready;
                    d1_rj_rob0      <= i_rmt_rj_rob0; //只要ready为1了也就无所谓从哪个rob中获得数据了
                    d1_rk_rob0      <= i_rmt_rk_rob0;
                    d1_rj_val0      <= (inst0_rj_index == 5'd0) ? 32'd0 : 
                                            exe_rj0_ready  && (!i_rmt_rj_ready0)     ? exe_rj0_data :
                                            i_rmt_rj_ready0     ? (inst0_rj_index == raw_com_rd ? raw_com_data :i_grf_rj_data0)  :
                                           rj_rob_done0 == 1    ? i_rj_robdone_data0 :32'd0;
                    d1_rk_val0      <= (inst0_rk_index == 5'd0) ? 32'd0 : 
                                            exe_rk0_ready   && (!i_rmt_rk_ready0)    ? exe_rk0_data :
                                            i_rmt_rk_ready0     ? (inst0_rk_index == raw_com_rd ? raw_com_data :i_grf_rk_data0) :
                                            rk_rob_done0 == 1   ? i_rk_robdone_data0 :32'b0;
                    d1_is_branch0   <= inst0_is_branch;
                    d1_imm0         <= inst0_imm32;
                end
                if (d0_valid1) begin
                    d1_pc1          <= inst1_pc;
                    d1_op1          <= inst1_op_83;
                    d1_fu_type1     <= inst1_fu_type;
                    d1_rob_idx1     <= d0_rob_idx1;
                    d1_rd1          <= inst1_rd_index;
                    d1_rj1          <= inst1_rj_index;
                    d1_rk1          <= inst1_rk_index;
                    d1_rj_ready1    <= ((inst1_rj_index == 5'd0) ? 1'b1 : i_rmt_rj_ready1) || rj_rob_done1 || exe_rj1_ready; //如果发现rob中数据此时已经准备好了，相当于ready=1，从rob中获得数据
                    d1_rk_ready1    <= ((inst1_rk_index == 5'd0) ? 1'b1 : i_rmt_rk_ready1) || rk_rob_done1 || exe_rk1_ready;
                    d1_rj_rob1      <= i_rmt_rj_rob1;
                    d1_rk_rob1      <= i_rmt_rk_rob1;
                    d1_rj_val1      <= (inst1_rj_index == 5'd0) ? 32'd0 : 
                                        exe_rj1_ready  &&(!i_rmt_rj_ready1)         ? exe_rj1_data:
                                        i_rmt_rj_ready1         ? (inst1_rj_index == raw_com_rd ? raw_com_data :i_grf_rj_data1) : //查询rmt的优先级更加高，先从grf获取数据（因为后面哪怕ready=1，想rob查询done的索引是0，会出问题的）
                                        rj_rob_done1 ==1        ? i_rj_robdone_data1 : 32'd0;//只有在ready为0的情况下才去从rob获取数据
                    d1_rk_val1      <= (inst1_rk_index == 5'd0) ? 32'd0 : 
                                        exe_rk1_ready  &&(!i_rmt_rk_ready1)         ? exe_rk1_data:
                                        i_rmt_rk_ready1         ? (inst1_rk_index == raw_com_rd ? raw_com_data :i_grf_rk_data1):
                                        rk_rob_done1 ==1        ? i_rk_robdone_data1 : 32'd0;
                    d1_is_branch1   <= inst1_is_branch;
                    d1_imm1         <= inst1_imm32;
                end
            end
        end
    end

    // ==================== D1 输出到 IQ ====================
    assign o_2_iq_alloc_en_idx0 = d1_wr_en0;
    assign o_2_iq_alloc_en_idx1 = d1_wr_en1;

    assign o_2_iq_pc_idx0        = d1_pc0;
    assign o_2_iq_op_idx0        = d1_op0;
    assign o_2_iq_fu_type_idx0   = d1_fu_type0;
    assign o_2_iq_rob_idx_idx0   = d1_rob_idx0;
    assign o_2_iq_rd_index_idx0  = d1_rd0;
    assign o_2_iq_rj_index_idx0  = d1_rj0;
    assign o_2_iq_rk_index_idx0  = d1_rk0;
    // assign o_2_iq_rj_ready_idx0  = d1_rj_ready0;
    // assign o_2_iq_rj_rob_idx0    = d1_rj_rob0;
    // assign o_2_iq_rj_value_idx0  = d1_rj_val0;
    // assign o_2_iq_rk_ready_idx0  = d1_rk_ready0;
    // assign o_2_iq_rk_rob_idx0    = d1_rk_rob0;
    // assign o_2_iq_rk_value_idx0  = d1_rk_val0;
    assign o_2_iq_rj_ready_idx0  = d1_rj_ready0 || rj0_cdb_bp;
    assign o_2_iq_rj_rob_idx0    = d1_rj_rob0;          // 不变
    assign o_2_iq_rj_value_idx0  = rj0_cdb_bp ? rj0_cdb_data : d1_rj_val0;
    assign o_2_iq_rk_ready_idx0  = d1_rk_ready0 || rk0_cdb_bp;
    assign o_2_iq_rk_rob_idx0    = d1_rk_rob0;          // 不变
    assign o_2_iq_rk_value_idx0  = rk0_cdb_bp ? rk0_cdb_data : d1_rk_val0;

    assign o_2_iq_is_branch_idx0 = d1_is_branch0;
    assign o_2_iq_imm_idx0       = d1_imm0;

    assign o_2_iq_pc_idx1        = d1_pc1;
    assign o_2_iq_op_idx1        = d1_op1;
    assign o_2_iq_fu_type_idx1   = d1_fu_type1;
    assign o_2_iq_rob_idx_idx1   = d1_rob_idx1;
    assign o_2_iq_rd_index_idx1  = d1_rd1;
    assign o_2_iq_rj_index_idx1  = d1_rj1;
    assign o_2_iq_rk_index_idx1  = d1_rk1;
    
    assign o_2_iq_rj_ready_idx1  = d1_rj_ready1 || rj1_cdb_bp;
    assign o_2_iq_rj_rob_idx1    = d1_rj_rob1;          // 不变
    assign o_2_iq_rj_value_idx1  = rj1_cdb_bp ? rj1_cdb_data : d1_rj_val1;
    assign o_2_iq_rk_ready_idx1  = d1_rk_ready1 || rk1_cdb_bp;
    assign o_2_iq_rk_rob_idx1    = d1_rk_rob1;          // 不变
    assign o_2_iq_rk_value_idx1  = rk1_cdb_bp ? rk1_cdb_data : d1_rk_val1;
    
    // assign o_2_iq_rj_ready_idx1  = d1_rj_ready1;
    // assign o_2_iq_rj_rob_idx1    = d1_rj_rob1;
    // assign o_2_iq_rj_value_idx1  = d1_rj_val1;
    // assign o_2_iq_rk_ready_idx1  = d1_rk_ready1;
    // assign o_2_iq_rk_rob_idx1    = d1_rk_rob1;
    // assign o_2_iq_rk_value_idx1  = d1_rk_val1;
    assign o_2_iq_is_branch_idx1 = d1_is_branch1;
    assign o_2_iq_imm_idx1       = d1_imm1;

    //raw-iq-exe
    assign o_rj_rob_index0 = (i_rmt_rj_ready0 == 1'b0) ? i_rmt_rj_rob0 : 0 ;
    assign o_rk_rob_index0 = (i_rmt_rk_ready0 == 1'b0) ? i_rmt_rk_rob0 : 0 ;
    assign o_rj_rob_index1 = (i_rmt_rj_ready1 == 1'b0) ? i_rmt_rj_rob1 : 0 ;
    assign o_rk_rob_index1 = (i_rmt_rk_ready1 == 1'b0) ? i_rmt_rk_rob1 : 0 ;


endmodule