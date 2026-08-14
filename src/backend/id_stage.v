module id_stage (
    input  wire        clk,  
    input  wire        rstn,
    
    input  wire        stop, //流水线暂停信号
    input  wire        clear,//流水线清空信号
 
    // 总线中有两条指令
    input  wire         i_if_to_id_valid, //if_stage送来的指令有效信号
    input  wire [169:0] i_if_to_id_data_170,  //{inst0_valid, pred_taken, pred_target, ex_sign, ecode, inst1, inst0, pc}
 
    
    // //llbit     【注意】唯一状态位，直接共享就行
    // input  wire        i_llbit,

    output wire [23:0] o_inst1_id_stop_sign_24, // inst1
    output wire        o_inst1_id_tlbsrch_sign,
    output wire [23:0] o_inst0_id_stop_sign_24, // inst0
    output wire        o_inst0_id_tlbsrch_sign,
    //送出到stop_controller数据包
// --------------------------------------------------
    output wire        o_id_to_issue_valid, //送出到下一流水级数据包有效信号
    output wire [461:0] o_id_to_issue_data_460
    //送出到下一流水级数据包
    );   
//..................................................
// wire [ 49:0] inst1_diff_data;
wire         inst1_PRELD; 
wire         inst1_ERTN; 
wire         inst1_IDLE; 
wire         inst1_CACOP; 
wire         inst1_CPUCFG; 
wire [  9:0] inst1_tlb_data; 
wire         inst1_ex_sign; 
wire [  5:0] inst1_ecode; 
wire [ 15:0] inst1_csr_data; 
wire         inst1_grf_no_wen; 
wire [ 31:0] inst1_offs32; 
wire [ 31:0] inst1_imm32; 
wire [ 10:0] inst1_alu_opcode; 
wire [  3:0] inst1_selcode; 
wire [  5:0] inst1_op_lsu;
wire [  2:0] inst1_op_div;
wire [  2:0] inst1_op_mul;
wire [  8:0] inst1_b_insts;
wire [  1:0] inst1_fu_type;
wire [  4:0] inst1_rj_index_5;    
wire [  4:0] inst1_rk_index_5;
wire [  4:0] inst1_rd_index_5;
wire [ 31:0] inst1_pred_target;
wire         inst1_pred_taken;
wire         inst1_is_branch;
wire [  7:0] inst1_cnt_opcode;

wire         inst0_PRELD; 
wire         inst0_ERTN; 
wire         inst0_IDLE; 
wire         inst0_CACOP; 
wire         inst0_CPUCFG; 
wire [  9:0] inst0_tlb_data; 
wire         inst0_ex_sign; 
wire [  5:0] inst0_ecode; 
wire [ 15:0] inst0_csr_data; 
wire         inst0_grf_no_wen; 
wire [ 31:0] inst0_offs32; 
wire [ 31:0] inst0_imm32; 
wire [ 10:0] inst0_alu_opcode; 
wire [  3:0] inst0_selcode; 
wire [  5:0] inst0_op_lsu;
wire [  2:0] inst0_op_div;
wire [  2:0] inst0_op_mul;
wire [  8:0] inst0_b_insts;
wire [  1:0] inst0_fu_type;
wire [  4:0] inst0_rj_index_5;    
wire [  4:0] inst0_rk_index_5;
wire [  4:0] inst0_rd_index_5;
wire [ 31:0] inst0_pred_target;
wire         inst0_pred_taken;
wire         inst0_is_branch;
wire [  7:0] inst0_cnt_opcode;

reg [169:0] i_data_170;
reg         if_to_id_valid ;
always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        i_data_170 <= {1'b0, 2'b0, 64'b0, 7'b0, `func_nop, `func_nop, 32'b0};
        if_to_id_valid <= 1'b0 ;
    end
    else begin
        if(clear) begin
            i_data_170 <= {1'b0, 2'b0, 64'b0, 7'b0, `func_nop, `func_nop, 32'b0};
            if_to_id_valid <= 1'b0 ;
        end
        else if(stop) begin
            i_data_170 <= i_data_170;
            if_to_id_valid <= if_to_id_valid;

        end
        else begin
            i_data_170 <= i_if_to_id_data_170;
            if_to_id_valid <= i_if_to_id_valid ;
        end
    end
end

wire inst0_valid;
wire [1:0] pred_taken;
wire [63:0] pred_target;
wire ex_sign_in;
wire [ 5:0] ecode_in;
wire [31:0] pc, inst1, inst0;
wire [31:0] real_inst1, real_inst0;
assign {inst0_valid, pred_taken, pred_target, ex_sign_in, ecode_in, inst1, inst0, pc} = i_data_170;

reg need_match;
reg [31:0] need_match_target; // 之前预测跳转时将pc设置为的跳转地址
wire match0 = (need_match_target == pc       );
wire match1 = (need_match_target == pc+32'h4 );

always @(posedge clk or negedge rstn) begin // 这里都是锁存值，都是针对上一组指令的
    if(~rstn) begin
        need_match <= 1'b0;
        need_match_target <= 32'b0;
    end
    else begin
        if(clear) begin
            need_match <= 1'b0;
            need_match_target <= 32'b0;
        end
        else if(stop) begin
            need_match <= need_match;
            need_match_target <= need_match_target;
        end
        else begin   
            if(match0 | match1) begin   // 上一轮匹配成功（因为此时的pc还是上一轮的）
                need_match <= 1'b0;
            end
            
            // 上一轮存在 有效 且 预测跳转 的指令，需要匹配（若因取指pc无效则is_branch = 0）
            if((inst0_is_branch & pred_taken[0]) | (inst1_is_branch & pred_taken[1])) begin   
                need_match <= 1'b1;
                if(pred_taken[0]) begin
                    need_match_target <= pred_target[31:0];
                end
                else begin
                    need_match_target <= pred_target[63:32];
                end
            end
        end
    end
end

// 这两个信号在时序逻辑中代表的是上一轮，但是除了那些判断其他都是组合逻辑，实际上依然代表当前指令

// 如果需要匹配且没有匹配上才会改变指令（inst0匹配上了则inst1也可以保留）
assign real_inst0 = (need_match & ~match0) ? `func_nop : inst0;
assign real_inst1 = (need_match & ~match0) ? 
                    ((need_match & ~match1)                 ? `func_nop : inst1) :  // inst0没匹配上需要尝试匹配inst1
                    ((pred_taken[0] & (inst0 != `func_nop)) ? `func_nop : inst1) ;  // inst0匹配上了 或 不需要匹配 都要检查inst0有效跳转对于inst1的屏蔽

decoder u_inst1_decoder(

    //llbit
    // .i_llbit                (i_llbit),

    // //csr前递

    .o_rj_index_5           (inst1_rj_index_5),
    .o_rk_index_5           (inst1_rk_index_5),
    .o_rd_index_5           (inst1_rd_index_5),

    .o_id_stop_sign_24      (o_inst1_id_stop_sign_24),
    .o_id_tlbsrch_sign      (o_inst1_id_tlbsrch_sign),
    //送出到stop_controller数据包

    // id_stage内部输入输出---------------------------------
    .inst                   (real_inst1),
    .ex_sign_in             (ex_sign_in & ~inst0_valid),
    .ecode_in               (ecode_in & {6{~inst0_valid}}),

    .inst_PRELD             (inst1_PRELD), 
    .inst_ERTN              (inst1_ERTN), 
    .inst_IDLE              (inst1_IDLE), 
    .inst_CACOP             (inst1_CACOP), 
    .inst_CPUCFG            (inst1_CPUCFG), 
    // .cpucfg_data            (inst1_cpucfg_data), 
    .tlb_data               (inst1_tlb_data), 
    .ex_sign                (inst1_ex_sign), 
    .ecode                  (inst1_ecode), 
    .csr_data               (inst1_csr_data), 
    .grf_no_wen             (inst1_grf_no_wen), 
    .offs32                 (inst1_offs32), 
    .imm32                  (inst1_imm32), 
    .alu_opcode             (inst1_alu_opcode), 
    .selcode                (inst1_selcode), 
    .op_lsu                 (inst1_op_lsu),
    .div_opcode             (inst1_op_div),
    .mul_opcode             (inst1_op_mul),
    .cnt_opcode             (inst1_cnt_opcode),
    .b_insts                (inst1_b_insts),
    .is_branch              (inst1_is_branch),
    .fu_type                (inst1_fu_type)
);

decoder u_inst0_decoder(
    // .i_llbit                (i_llbit),

    .o_rj_index_5           (inst0_rj_index_5),
    .o_rk_index_5           (inst0_rk_index_5),
    .o_rd_index_5           (inst0_rd_index_5),

    .o_id_stop_sign_24      (o_inst0_id_stop_sign_24),
    .o_id_tlbsrch_sign      (o_inst0_id_tlbsrch_sign),
    //送出到stop_controller数据包

    // id_stage内部输入输出---------------------------------
    .inst                   (real_inst0),
    .ex_sign_in             (ex_sign_in & inst0_valid),
    .ecode_in               (ecode_in & {6{inst0_valid}}),

    .inst_PRELD             (inst0_PRELD), 
    .inst_ERTN              (inst0_ERTN), 
    .inst_IDLE              (inst0_IDLE), 
    .inst_CACOP             (inst0_CACOP), 
    .inst_CPUCFG            (inst0_CPUCFG), 
    .tlb_data               (inst0_tlb_data), 
    .ex_sign                (inst0_ex_sign), 
    .ecode                  (inst0_ecode), 
    .csr_data               (inst0_csr_data), 
    .grf_no_wen             (inst0_grf_no_wen), 
    .offs32                 (inst0_offs32), 
    .imm32                  (inst0_imm32), 
    .alu_opcode             (inst0_alu_opcode), 
    .selcode                (inst0_selcode), 
    .op_lsu                 (inst0_op_lsu),
    .div_opcode             (inst0_op_div),
    .mul_opcode             (inst0_op_mul),
    .cnt_opcode             (inst0_cnt_opcode),
    .b_insts                (inst0_b_insts),
    .is_branch              (inst0_is_branch),
    .fu_type                (inst0_fu_type)
);

assign inst0_pred_target = pred_target[31:0];
assign inst0_pred_taken = pred_taken[0];
wire [26:0] inst0_opcode = {inst0_alu_opcode, inst0_selcode, inst0_op_lsu, inst0_op_div, inst0_op_mul};

assign inst1_pred_target = pred_target[63:32];
assign inst1_pred_taken = pred_taken[1];
wire [26:0] inst1_opcode = {inst1_alu_opcode, inst1_selcode, inst1_op_lsu, inst1_op_div, inst1_op_mul};

assign o_id_to_issue_valid = (~rstn | clear | stop | ~if_to_id_valid) ? 1'b0 : 1'b1;
assign o_id_to_issue_data_460 = (inst0_ex_sign) ? {230'b0, inst0_PRELD, inst0_ERTN, inst0_IDLE, inst0_CACOP, inst0_CPUCFG, inst0_tlb_data, inst0_ex_sign, inst0_ecode, inst0_cnt_opcode, inst0_csr_data, inst0_grf_no_wen, inst0_offs32, inst0_imm32,  inst0_opcode, inst0_fu_type, inst0_rj_index_5, inst0_rk_index_5, inst0_rd_index_5, inst0_is_branch, inst0_pred_taken, inst0_pred_target, inst0_b_insts, pc}:

                                (!stop) ? {inst1_PRELD, inst1_ERTN, inst1_IDLE, inst1_CACOP, inst1_CPUCFG, inst1_tlb_data, inst1_ex_sign, inst1_ecode, inst1_cnt_opcode, inst1_csr_data, inst1_grf_no_wen, inst1_offs32, inst1_imm32,  inst1_opcode, inst1_fu_type, inst1_rj_index_5, inst1_rk_index_5, inst1_rd_index_5, inst1_is_branch, inst1_pred_taken, inst1_pred_target, inst1_b_insts, pc+ 32'h4,
//                                             1    +      1    +      1    +      1     +       1     +         10   +          1   +         6  +          8      +          16   +         1      +          32  +         32  +     +      27     +        2    +           5       +       5       +          5    +           1        +         1        +       32      +        9      + 32 = 230
                                           inst0_PRELD, inst0_ERTN, inst0_IDLE, inst0_CACOP, inst0_CPUCFG, inst0_tlb_data, inst0_ex_sign, inst0_ecode, inst0_cnt_opcode, inst0_csr_data, inst0_grf_no_wen, inst0_offs32, inst0_imm32,  inst0_opcode, inst0_fu_type, inst0_rj_index_5, inst0_rk_index_5, inst0_rd_index_5, inst0_is_branch, inst0_pred_taken, inst0_pred_target, inst0_b_insts, pc}:
                                
                                                                        460'b0;
//..................................................
endmodule