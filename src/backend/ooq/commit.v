module commit(
    input  wire        clk              ,
    input  wire        rstn             ,       // 提交阶段不需要再冲刷或者停止

    // 来自 ROB 的提交信息
    input  wire        i_valid          ,       // 提交有效，当异常发生时，此信号为0
    input  wire [31:0] i_pc             ,       // 提交指令的pc
    // GRF写回
    input  wire [4:0]  i_rd             ,       // 目标grf索引
    input  wire        i_grf_we         ,       // grf写使能
    input  wire [31:0] i_grf_wdata      ,       // grf写回数据
    // CSR写回
    input  wire [1:0]  i_csr_sign       ,       // csr信号
    input  wire [13:0] i_csr_waddr      ,       // csr写回地址
    input  wire [31:0] i_csr_wdata      ,       // csr写回数据
    input  wire [31:0] i_csr_wmask      ,       // csr写掩码（有些指令只写部分）

    // 异常
    input  wire        i_ex_sign        ,       // 异常信号
    input  wire [31:0] i_ex_pc          ,       // 异常地址
    input  wire [31:0] i_ex_addr        ,       // 
    input  wire [5:0]  i_ex_code        ,       // 异常码
    input  wire [10:0] i_tlb_data       ,       // TLB数据 {invtlb_en,we,fill,rd,search,found,index[4:0]}
    // 其他控制信号
    input  wire        i_ertn_sign      , 
    input  wire        i_idle_sign      ,
    // 新加
    input  wire        i_llbit          ,
    input  wire        i_cacop_inst     ,

    input  wire [5:0]  i_op_lsu         ,
    input  wire        i_is_branch      ,
    input  wire        i_pred_taken     ,
    input  wire        i_actual_taken   ,
    input  wire [31:0] i_pred_target    ,
    input  wire [31:0] i_actual_target  ,
    

    // 写回 GRF（组合输出）
    output wire        o_grf_we         ,
    output wire [4:0]  o_grf_waddr      ,
    output wire [31:0] o_grf_wdata      ,
    // 写回 CSR
    output wire        o_csr_we         ,
    output wire [13:0] o_csr_waddr      ,
    output wire [31:0] o_csr_wdata      ,
    output wire [31:0] o_csr_wmask      ,
    // LLbit
    output wire        o_llbit          ,
    output wire        o_llbit_set      ,
    // 异常
    output wire        o_ex_sign        ,
    output wire [31:0] o_ex_pc          ,
    output wire [31:0] o_ex_addr        ,
    output wire [5:0]  o_ex_code        ,
    output wire [9:0]  o_subecode_9     ,
    // TLB 操作
    output wire        o_tlb_we         ,
    output wire        o_tlb_rd         ,
    output wire        o_tlbfill_en     ,
    output wire        o_tlb_search     ,
    output wire        o_tlb_s_found    ,
    output wire [4:0]  o_tlb_s_index    ,
    // 其他控制信号
    output wire        o_ertn_sign      ,
    output wire        o_idle_sign      ,
    output wire        o_cacop_sign     ,
    output wire [31:0] o_cacop_pc       ,   // 用于cacop时让前端重新取指
    // 新加
    output wire        o_lsq_retire     ,
    output wire        o_lsq_can_send   ,

    output wire        o_feedback_en    ,
    output wire        o_actual_taken   ,
    output wire [31:0] o_actual_target  ,
    output wire         o_flush //组合逻辑输出
);

    wire valid = i_valid && (!i_ex_sign || i_ex_code == 6'h0);

    // ----- 异常传递（无需检测i_valid） -----
    wire   choose_addr  = (i_ex_code == 6'h9 | i_ex_code == 6'h3f | i_ex_code == 6'h01 | i_ex_code == 6'h02 | i_ex_code == 6'h03 | i_ex_code == 6'h04 | i_ex_code == 6'h07);
    assign o_ex_sign    = i_ex_sign; // 中断也是有效指令，但是也要冲刷
    assign o_ex_pc      = i_ex_sign ? i_ex_pc : 32'd0;
    assign o_ex_addr    = i_ex_sign ? (choose_addr ? i_ex_addr : i_ex_pc) : 32'd0;
    assign o_ex_code    = i_ex_sign ? i_ex_code : 6'd0;
    assign o_subecode_9 = 9'b0;

// 以下皆为正常提交时输出**************************************************
    // ----- GRF 写回（x0 不写）-----
    wire [31:0] grf_wdata = (i_op_lsu[5:3] == 3'b110) ? {31'b0,i_llbit} : i_grf_wdata;   // SC指令写回llbit，其他指令写回grf数据
    assign o_grf_we    = valid ? (i_grf_we & (i_rd != 5'd0)) : 1'b0;
    assign o_grf_waddr = valid ? i_rd : 5'd0;      // 当 we=0 时可为任意值，此处给0
    assign o_grf_wdata = valid ? grf_wdata : 32'd0;

    // ----- CSR 写回 -----
    wire [1:0] csr_sign = valid ? i_csr_sign : 2'b0;
    assign o_csr_we    = valid ? i_csr_sign[1]  : 1'b0;
    assign o_csr_waddr = valid ? i_csr_waddr : 14'd0;
    assign o_csr_wdata = valid ? i_csr_wdata : 32'd0;
    assign o_csr_wmask = valid ? i_csr_wmask : 32'd0;

    // ----- LLbit -----
    assign o_llbit_set = valid ? i_op_lsu[5]                 : 1'b0;    // 原子访存都会改
    assign o_llbit     = valid ? (i_op_lsu[5] & i_op_lsu[3]) : 1'b0;    // LL指令置为1，SC指令置为0（sc失败即llbit=0也没关系）

    // ----- TLB 操作 -----
    wire   inst_tlb      = valid ? (|i_tlb_data[10:6])  : 1'b0;
    wire   invtlb_en     = valid ? i_tlb_data[10]       : 1'b0;
    assign o_tlb_we      = valid ? i_tlb_data[9]        : 1'b0;
    assign o_tlb_rd      = valid ? i_tlb_data[8]        : 1'b0;
    assign o_tlbfill_en  = valid ? i_tlb_data[7]        : 1'b0;
    assign o_tlb_search  = valid ? i_tlb_data[6]        : 1'b0;
    assign o_tlb_s_found = valid ? i_tlb_data[5]        : 1'b0;
    assign o_tlb_s_index = valid ? i_tlb_data[4:0]      : 5'd0;

    // ----- 特殊控制信号 -----
    assign o_ertn_sign  = valid ? (i_ertn_sign  & ~i_ex_sign) : 1'b0;
    assign o_idle_sign  = valid ? (i_idle_sign  & ~i_ex_sign) : 1'b0;
    // assign o_cacop_sign = valid ? (o_llbit_set | o_csr_we | o_idle_sign | o_tlb_we | invtlb_en) : 1'b0;
    assign o_cacop_sign = valid ? (o_llbit_set | (csr_sign != 2'b0) | o_idle_sign | inst_tlb | invtlb_en) : 1'b0;     // 只要是tlb指令就会改csr，直接冲刷不再暂停
    assign o_cacop_pc   = i_pc + 32'h4;

    // ----- 新加 -----
    // 分支判断：
    //      如果是分支指令，无论是否跳转都需要发送 是否跳转 及 跳转地址
    //      如果不是分支指令，只有预测跳转才要发送 是否跳转 及 跳转地址
    wire   need_feedback   = valid ? (i_is_branch | (~i_is_branch & i_pred_taken)) : 1'b0;
    assign o_feedback_en   = need_feedback;
    assign o_actual_taken  = need_feedback ? i_actual_taken  : 1'b0;
    assign o_actual_target = need_feedback ? (i_csr_sign[1] ? (i_pc + 32'h4) : i_actual_target) : 32'd0;
    // 只有两种情况正确————预测不跳转，实际不跳转（不需要比较target）；预测跳转，实际跳转，且target相同
    wire branch_no_error = (i_pred_taken == 1'b0 && i_actual_taken == 1'b0) || 
                             (i_pred_taken == 1'b1 && i_actual_taken == 1'b1 && i_pred_target == i_actual_target);
    wire brach_error     = valid ? ~branch_no_error : 1'b0;   // 提交有效且分支错误时拉高

    // lsq retire和can_send信号
    wire   dcache_cacop   = i_cacop_inst && i_rd[2:0] == 3'b001;
    assign o_lsq_retire   = valid ? ((i_op_lsu[4:3] == 2'b10) || dcache_cacop) : 1'b0;      // 只有store和dcache_cacop才要retire
    assign o_lsq_can_send = valid ? ~((i_op_lsu[5:3] == 3'b110) & ~i_llbit)    : 1'b0;      // 只有SC指令且llbit为0时才会发送0

    wire cacop_inst = valid && i_cacop_inst;    // 无论dcache_cacop还是icache_cacop都冲刷

    assign o_flush = o_ex_sign || brach_error || o_cacop_sign || o_ertn_sign || cacop_inst;
    
    // always @(posedge clk or negedge rstn) begin
    //     if (!rstn) begin
    //         o_flush <= 1'b0;
    //     end else begin
    //         o_flush <= flush;
    //     end
    // end

endmodule