`timescale 1ns / 1ps

module exe_top(
    input                   clk                     ,
    input                   rstn                    ,
    input                   flush                   , //冲刷信号
    //从iq来的数据�?
    input       [465:0]     i_from_issue_466       ,
    output wire [4:0]       o_fu_free          ,   //fu空闲信号使用独热码，从高到低分别为：alu0,alu1,mul,div,lsu
    input  wire [63:0]      i_cnt_data_64          ,   //计数器数�?
    input  wire [31:0]      i_cnt_id      ,   //计数器id 

    //写回给rob的数�?
    output wire  [153:0]     o_2_rob_wb          ,
    //前�?�给发射队列，解决raw相关性问�?,即cdb总线写回
    output wire        o_cdb_valid0,
    output wire [2:0]  o_cdb_rob0,
    output wire [31:0] o_cdb_value0,
    output wire        o_cdb_valid1,
    output wire [2:0]  o_cdb_rob1,
    output wire [31:0] o_cdb_value1    ,

    //rob的握手信�?
    input wire              i_rob_wb_ack0   ,
    input wire              i_rob_wb_ack1   ,

    //lsu中与csr，tlb等直出端�?
    // ---- CSR 状�?�（地址映射�?----
    input  wire         crmd_da                 ,
    input  wire         crmd_pg                 ,
    input  wire [  1:0] crmd_datm               ,
    input  wire [  1:0] crmd_plv                ,
    input  wire [ 18:0] csr_tlbehi_vppn         ,
    input  wire [  9:0] csr_asid_asid           ,
    input  wire         dmw0_plv0, dmw0_plv3    ,
    input  wire [  1:0] dmw0_mat                ,
    input  wire [  2:0] dmw0_pseg, dmw0_vseg    ,
    input  wire         dmw1_plv0, dmw1_plv3    ,
    input  wire [  1:0] dmw1_mat,
    input  wire [  2:0] dmw1_pseg, dmw1_vseg    ,

    // ---- TLB 接口 ----  // tlb的一些操作就得�?�用dcache的端�?
    output wire         invtlb_valid       ,
    output wire [  4:0] invtlb_op          ,
    output wire [ 18:0] invtlb_vppn        ,
    output wire [  9:0] invtlb_asid        ,
    output wire [ 18:0] tlb_s1_vppn        ,
    output wire         tlb_s1_va_odd      ,
    output wire [  9:0] tlb_s1_asid        ,
    input  wire         tlb_s1_found       ,
    input  wire [  4:0] tlb_s1_index       ,
    input  wire [ 19:0] tlb_s1_ppn         ,
    input  wire [  5:0] tlb_s1_ps          ,
    input  wire [  1:0] tlb_s1_plv         ,
    input  wire [  1:0] tlb_s1_mat         ,
    input  wire         tlb_s1_d           ,
    input  wire         tlb_s1_v           ,

    // ---- LSQ 接口 ----
    output wire         store_valid        ,
    output wire [ 31:0] store_paddr        ,
    output wire [ 31:0] store_data         ,
    output wire [  3:0] store_mask         ,
    output wire [  2:0] store_size         ,
    output wire         store_is_uncache   ,
    output wire         store_is_cacop     ,
    output wire [  1:0] store_cacop_op     ,
    input  wire         store_ready        ,
    output wire         load_valid         ,
    output wire [ 31:0] load_paddr         ,
    output wire [  2:0] load_size          ,
    output wire         load_is_uncache    ,
    input  wire         load_ready         ,
    input  wire [ 31:0] load_result        ,
    input  wire         load_result_valid  ,
    input  wire         ls_stall_i         ,

    // ---- icache cacop 控制 ----
    output wire         icache_cacop_en    ,
    output wire [  1:0] icache_cacop_op    ,
    output wire [ 31:0] icache_cacop_va    ,

    // ---- preld 控制 ---- // 这个控制暂时不用，到时�?�直接给dcache�?0先验证结�?
    output wire         preld_en           ,
    output wire [  4:0] preld_hint         ,

    //raw-exe_result- dispatch
    output wire         exe_2_rj0_ready   ,       
    output wire         exe_2_rk0_ready   ,       
    output wire         exe_2_rj1_ready   ,       
    output wire         exe_2_rk1_ready   ,       
    input  wire [2:0]   disp_rob_idx0_rj       ,
    input  wire [2:0]   disp_rob_idx0_rk       ,
    input  wire [2:0]   disp_rob_idx1_rj       ,
    input  wire [2:0]   disp_rob_idx1_rk       ,
    output wire [31:0]  exe_2_disp_rjdata0     ,
    output wire [31:0]  exe_2_disp_rkdata0     ,
    output wire [31:0]  exe_2_disp_rjdata1     ,
    output wire [31:0]  exe_2_disp_rkdata1      

    );
    /*issue过来的数据包*/
    //执行级的流水寄存�?
    reg         r_inst0_vld,r_inst1_vld ;
    reg [31:0]  r_inst0_rj, r_inst0_rk, r_inst1_rj,r_inst1_rk ;
    reg [31:0]  r_inst0_imm,r_inst1_imm ;
    reg [82:0]  r_inst0_op, r_inst1_op   ;
    reg [2:0]   r_inst0_rob,r_inst1_rob ;    
    reg [31:0]  r_inst0_pc, r_inst1_pc  ;
    reg         r_inst0_branch, r_inst1_branch ;
    reg [1:0]   r_fu_type_idx0 , r_fu_type_idx1 ;   //00-alu,01-mul,10-div,11-lsu
    reg [4:0]   r_inst0_rj_index, r_inst0_rk_index, r_inst0_rd_index, r_inst1_rj_index, r_inst1_rk_index, r_inst1_rd_index ;

    // always@(posedge clk or negedge rstn)begin
    //     if(!rstn)begin
    //          {    r_inst1_vld , r_inst1_rj ,r_inst1_rk , r_inst1_imm , r_inst1_op , r_inst1_rob , r_inst1_pc ,r_inst1_branch , r_fu_type_idx1, r_inst1_rj_index, r_inst1_rk_index, r_inst1_rd_index,
    //             r_inst0_vld , r_inst0_rj ,r_inst0_rk , r_inst0_imm , r_inst0_op , r_inst0_rob , r_inst0_pc ,r_inst0_branch , r_fu_type_idx0, r_inst0_rj_index, r_inst0_rk_index, r_inst0_rd_index }  <= 466'd0;
    //     end
    //     else begin
    //         {    r_inst1_vld , r_inst1_rj ,r_inst1_rk , r_inst1_imm , r_inst1_op , r_inst1_rob , r_inst1_pc ,r_inst1_branch , r_fu_type_idx1, r_inst1_rj_index, r_inst1_rk_index, r_inst1_rd_index,
    //             r_inst0_vld , r_inst0_rj ,r_inst0_rk , r_inst0_imm , r_inst0_op , r_inst0_rob , r_inst0_pc ,r_inst0_branch , r_fu_type_idx0, r_inst0_rj_index, r_inst0_rk_index, r_inst0_rd_index } <=  i_from_issue_466 ;
    //     end
    // end

always@(posedge clk or negedge rstn)begin
    if(!rstn)begin
         {    r_inst1_vld , r_inst1_rj ,r_inst1_rk , r_inst1_imm , r_inst1_op , r_inst1_rob , r_inst1_pc ,r_inst1_branch , r_fu_type_idx1, r_inst1_rj_index, r_inst1_rk_index, r_inst1_rd_index,
            r_inst0_vld , r_inst0_rj ,r_inst0_rk , r_inst0_imm , r_inst0_op , r_inst0_rob , r_inst0_pc ,r_inst0_branch , r_fu_type_idx0, r_inst0_rj_index, r_inst0_rk_index, r_inst0_rd_index }  <= 466'd0;
    end else if (flush) begin
        // 冲刷时清零所有输入寄存器，丢弃当前指�?
        {    r_inst1_vld , r_inst1_rj ,r_inst1_rk , r_inst1_imm , r_inst1_op , r_inst1_rob , r_inst1_pc ,r_inst1_branch , r_fu_type_idx1, r_inst1_rj_index, r_inst1_rk_index, r_inst1_rd_index,
            r_inst0_vld , r_inst0_rj ,r_inst0_rk , r_inst0_imm , r_inst0_op , r_inst0_rob , r_inst0_pc ,r_inst0_branch , r_fu_type_idx0, r_inst0_rj_index, r_inst0_rk_index, r_inst0_rd_index } <= 466'd0;
    end else begin
        // 正常从发射队列接收新指令
        {    r_inst1_vld , r_inst1_rj ,r_inst1_rk , r_inst1_imm , r_inst1_op , r_inst1_rob , r_inst1_pc ,r_inst1_branch , r_fu_type_idx1, r_inst1_rj_index, r_inst1_rk_index, r_inst1_rd_index,
            r_inst0_vld , r_inst0_rj ,r_inst0_rk , r_inst0_imm , r_inst0_op , r_inst0_rob , r_inst0_pc ,r_inst0_branch , r_fu_type_idx0, r_inst0_rj_index, r_inst0_rk_index, r_inst0_rd_index } <=  i_from_issue_466 ;
    end
end

    //根据fu_type分配到对应的执行单元
    wire inst0_alu, inst0_mul, inst0_div, inst0_lsu;
    wire inst1_alu, inst1_mul, inst1_div, inst1_lsu;

    assign {inst0_alu, inst0_mul, inst0_div, inst0_lsu} = 
        r_inst0_vld ? (r_fu_type_idx0 == 2'b00) ? 4'b1000 :
                        (r_fu_type_idx0 == 2'b01) ? 4'b0100 :
                        (r_fu_type_idx0 == 2'b10) ? 4'b0010 :
                        (r_fu_type_idx0 == 2'b11) ? 4'b0001 : 4'b0
                    : 4'b0;

    assign {inst1_alu, inst1_mul, inst1_div, inst1_lsu} = 
        r_inst1_vld ? (r_fu_type_idx1 == 2'b00) ? 4'b1000 :
                        (r_fu_type_idx1 == 2'b01) ? 4'b0100 :
                        (r_fu_type_idx1 == 2'b10) ? 4'b0010 :
                        (r_fu_type_idx1 == 2'b11) ? 4'b0001 : 4'b0
                    : 4'b0;

    //发�?�到ALU单元
    wire [31:0] o_alu_result0 , o_alu_result1 ;
    wire [31:0] o_actual_pc0  , o_actual_pc1 ;
    wire        o_actual_taken0, o_actual_taken1 ;
    reg         alu0_done,alu1_done ;
    //将alu0和inst0绑定                            csr(16)           cnt(8)            exception(7)         idle           ertn               cpucfg_sign                                            //第二个imm相当于offs32
    wire [217:0] alu0_data = inst0_alu ? { r_inst0_op[52:37] , r_inst0_op[60:53] , r_inst0_op[67:61] , r_inst0_op[80] , r_inst0_op[81] , r_inst0_op[78], r_inst0_pc, r_inst0_rj , r_inst0_rk , r_inst0_imm , r_inst0_imm , r_inst0_op[26:16] , r_inst0_op[15:12], r_inst0_op[35:27]}
                                    : 218'd0;
    wire [217:0] alu1_data = inst1_alu ? { r_inst1_op[52:37] , r_inst1_op[60:53] , r_inst1_op[67:61] , r_inst1_op[80] , r_inst1_op[81] , r_inst1_op[78],  r_inst1_pc, r_inst1_rj , r_inst1_rk , r_inst1_imm , r_inst1_imm ,r_inst1_op[26:16] , r_inst1_op[15:12], r_inst1_op[35:27]}
                                    : 218'd0;
    //alu的异常输�?
    wire        o_alu0_exception, o_alu1_exception;
    wire [5:0]  o_alu0_exccode,   o_alu1_exccode;
    wire        o_alu0_ertn,      o_alu1_ertn;
    wire        o_alu0_idle,      o_alu1_idle;  
                
                                    

    //发�?�到mul：按照规定，两条指令中只可能存在�?条mul指令
    wire mul_en, mul_signed;
    wire [31:0]mul_a ,mul_b ;
    wire [31:0]mul_result;
    wire [2:0]  mul_op;
    wire mul_ready ;
    assign mul_en = inst0_mul || inst1_mul ;

    assign mul_op =inst0_mul ? r_inst0_op[2:0] :
                       inst1_mul ? r_inst1_op[2:0] : 3'd0 ;

    assign mul_a = inst0_mul ? r_inst0_rj :
                    inst1_mul ? r_inst1_rj : 32'd0 ;
    assign mul_b = inst0_mul ? r_inst0_rk :
                    inst1_mul ? r_inst1_rk : 32'd0 ;
    
                 
    //发�?�到div：按照发射的规定，两条指令中必然只可能存在一条div的指�?
    wire div_en = inst0_div || inst1_div ;
    wire  div_done ,div_ready;
    wire [2:0]  div_op ;

    wire [31:0] div_z,div_d;
    assign div_z = inst0_div  ?  r_inst0_rj :
                    inst1_div ?  r_inst1_rj : 32'd0;
    assign div_d = inst0_div  ?  r_inst0_rk :
                    inst1_div ?  r_inst1_rk : 32'd0;
    assign div_op = inst0_div  ?  r_inst0_op[5:3]://在译码的时�?�，1-有符号，但是在div�?0才是有符号的运算，故取反
                    inst1_div  ?  r_inst1_op[5:3] : 3'd0 ;  
    wire [31:0] div_result ;

    //lsu�?要复用rj rk imm offs区域来完成操作数的界定，这里还需要对齐！！！！！！！�?
    //发�?�到lsu的信号：
    wire lsu_en = inst0_lsu || inst1_lsu ;
    wire [5:0]  lsu_op;
    wire [31:0] lsu_base ,lsu_offs, lsu_sdata , lsu_pc ;
    wire [4:0]  lsu_rd_index ;
    assign lsu_op = inst0_lsu ? r_inst0_op[11:6] :
                    inst1_lsu ? r_inst1_op[11:6] : 6'd0 ;
    assign lsu_base = inst0_lsu ? r_inst0_rj :
                    inst1_lsu ? r_inst1_rj : 32'd0 ;
    assign lsu_offs = inst0_lsu ? ( lsu_tlb_data[5] ? r_inst0_rk  :  r_inst0_imm) :     //偏移量放在了imm
                    inst1_lsu ? ( lsu_tlb_data[5] ? r_inst1_rk  :  r_inst1_imm) : 32'd0 ;
    assign lsu_sdata = inst0_lsu ? r_inst0_rk : //这里的lsu使用的是rd，但是其实应该只是一个源寄存器，暂时用rk复用
                    inst1_lsu ? r_inst1_rk : 32'd0 ;
    assign lsu_pc = inst0_lsu ? r_inst0_pc :
                    inst1_lsu ? r_inst1_pc : 32'd0 ;
    assign lsu_rd_index =   inst0_lsu ? r_inst0_rd_index :
                            inst1_lsu ? r_inst1_rd_index : 5'd0 ;
    wire lsu_load_stall =  inst0_lsu   ?  r_inst0_op[9]  : 
                            inst1_lsu   ?  r_inst1_op[9]  : 1'b0 ; //连续load指令的stall信号

    wire [9:0]  lsu_tlb_data ;
    wire        lsu_cacop_sign ;
    wire        lsu_preld_sign ;
    wire        lsu_stall ,lsu_ready     ; //lsu_ready信号是为1的时候标识空闲，而这个stall�?0的时候标识空�?
    //lsu的输出端�?
    wire [31:0] lsu_result ;
    wire        lsu_result_valid;
    wire        lsu_exception ;
    wire [5:0]  lsu_exccode  ; 
    wire [31:0] lsu_excaddr ;
    assign lsu_tlb_data = inst0_lsu ? r_inst0_op[77:68] :
                            inst1_lsu ? r_inst1_op[77:68]  : 10'b0 ;

    assign lsu_cacop_sign = inst0_lsu ? r_inst0_op[79] :
                            inst1_lsu ? r_inst1_op[79]  : 1'b0 ;
    
    assign lsu_preld_sign = inst0_lsu ? r_inst0_op[82] :
                            inst1_lsu ? r_inst1_op[82]  : 1'b0 ;
    assign lsu_ready = !lsu_stall ; //1-lsu空闲

    /*========数据写回到rob=========*/
    //alu完成信号
    // always @(posedge clk or negedge rstn) begin
    //     if (!rstn) begin
    //         alu0_done <= 0;
    //         alu1_done <= 0;
    //     end else begin
    //         alu0_done <= inst0_alu;   // 打一�?
    //         alu1_done <= inst1_alu;
    //     end
    // end
    wire mul_done ;
    //======由于可能出现�?个周期有大于两条指令要写回rob，但rob固定了只有两个写回端口，�?以我们需要对每一个执行单元进行暂存，并且添加仲裁�?
    //仲裁的优先级为：div > lsu > mul > alu0 > alu1
    //仲裁器存放的数据格式和rob的存放格式应该一致，这样方便rob写回:使能，rob索引，结果数据，分支实际pc，是否跳�?
    

    //暂存数据，rob握手
    // ================= 新增：FU 结果暂存与仲�? =================
    // 暂存寄存�?
    reg         alu0_valid, alu1_valid;
    reg [31:0]  alu0_result, alu1_result;
    reg [ 2:0]  alu0_rob, alu1_rob;
    reg         alu0_exc, alu1_exc;
    reg         alu0_ertn, alu1_ertn;
    reg         alu0_idle, alu1_idle;
    reg [ 5:0]  alu0_exccode, alu1_exccode;
    reg [31:0]  alu0_btarget, alu1_btarget;
    reg         alu0_btaken, alu1_btaken;

    reg         mul_valid;
    reg [31:0]  mul_result_reg;
    reg [ 2:0]  mul_rob;

    reg         div_valid;
    reg [31:0]  div_result_reg;
    reg [ 2:0]  div_rob;

    reg         lsu_valid;
    reg [31:0]  lsu_result_reg;
    reg [ 2:0]  lsu_rob;
    reg         lsu_exc_reg;
    reg [ 5:0]  lsu_exccode_reg;
    reg [31:0]  lsu_excaddr_reg;

    // ALU 提前锁存 ROB 索引（与 MUL/DIV/LSU �?致）
    // wire [2:0] alu0_rob_idx, alu1_rob_idx;
    // always @(posedge clk or negedge rstn) begin
    //     if (!rstn) begin
    //         alu0_rob_idx <= 0;
    //         alu1_rob_idx <= 0;
    //     end else begin
    //         if (inst0_alu) alu0_rob_idx <= r_inst0_rob;
    //         if (inst1_alu) alu1_rob_idx <= r_inst1_rob;
    //     end
    // end
    // assign alu0_rob_idx = r_inst0_rob;
    // assign alu1_rob_idx = r_inst1_rob;

    // MUL/DIV/LSU �? ROB 索引锁存（启动时记录�?
    wire [2:0] mul_rob_idx, div_rob_idx, lsu_rob_idx;
// always @(posedge clk or negedge rstn) begin
//     if (!rstn) begin
//         mul_rob_idx <= 0;
//         div_rob_idx <= 0;
//         lsu_rob_idx <= 0;
//     end else begin        
//         if (inst0_mul && mul_ready) mul_rob_idx <= r_inst0_rob;
//         if (inst1_mul && mul_ready) mul_rob_idx <= r_inst1_rob;
//         if (inst0_div && div_ready) div_rob_idx <= r_inst0_rob;
//         if (inst1_div && div_ready) div_rob_idx <= r_inst1_rob;
//         if (inst0_lsu && !lsu_stall) lsu_rob_idx <= r_inst0_rob;
//         if (inst1_lsu && !lsu_stall) lsu_rob_idx <= r_inst1_rob;
//     end
// end

    assign mul_rob_idx = inst0_mul ? r_inst0_rob : (inst1_mul ? r_inst1_rob : 3'd0);
    assign div_rob_idx = inst0_div ? r_inst0_rob : (inst1_div ? r_inst1_rob : 3'd0);
    assign lsu_rob_idx = inst0_lsu ? r_inst0_rob : (inst1_lsu ? r_inst1_rob : 3'd0);

    reg  [2:0] sel0  ;
    wire [4:0] mask1 ;
    reg  [2:0] sel1   ;
    // 写回确认清除信号
    wire clr_alu0 = (sel0 == 3'd0) ? i_rob_wb_ack0 : (sel1 == 3'd0) ? i_rob_wb_ack1 : 1'b0;
    wire clr_alu1 = (sel0 == 3'd1) ? i_rob_wb_ack0 : (sel1 == 3'd1) ? i_rob_wb_ack1 : 1'b0;
    wire clr_mul  = (sel0 == 3'd2) ? i_rob_wb_ack0 : (sel1 == 3'd2) ? i_rob_wb_ack1 : 1'b0;
    wire clr_div  = (sel0 == 3'd3) ? i_rob_wb_ack0 : (sel1 == 3'd3) ? i_rob_wb_ack1 : 1'b0;
    wire clr_lsu  = (sel0 == 3'd4) ? i_rob_wb_ack0 : (sel1 == 3'd4) ? i_rob_wb_ack1 : 1'b0;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            alu0_valid <= 0; alu1_valid <= 0; mul_valid <= 0; div_valid <= 0; lsu_valid <= 0;
            alu0_result <= 0; alu1_result <= 0;
            alu0_rob <= 0; alu1_rob <= 0;
            alu0_exc <= 0; alu1_exc <= 0;
            alu0_ertn <= 0; alu1_ertn <= 0;
            alu0_idle <= 0; alu1_idle <= 0;
            alu0_exccode <= 0; alu1_exccode <= 0;
            alu0_btarget <= 0; alu1_btarget <= 0;
            alu0_btaken <= 0; alu1_btaken <= 0;
            mul_valid <= 0;
            mul_rob   <= 0;
            mul_result_reg <= 32'd0;
            div_valid <= 0;
            div_rob   <= 0;
            div_result_reg <= 0;
            lsu_valid <= 0;
            lsu_rob   <= 0;
            lsu_result_reg <= 0;
            lsu_exc_reg    <= 0;
            lsu_exccode_reg <= 0;
            lsu_excaddr_reg <= 0;

        end else if (flush) begin
                // 冲刷：清除所有有效标志及暂存数据
                alu0_valid <= 0; alu1_valid <= 0; mul_valid <= 0; div_valid <= 0; lsu_valid <= 0;
                alu0_result <= 0; alu1_result <= 0; mul_result_reg <= 0; div_result_reg <= 0; lsu_result_reg <= 0;
                alu0_rob <= 0; alu1_rob <= 0; mul_rob <= 0; div_rob <= 0; lsu_rob <= 0;
                alu0_exc <= 0; alu1_exc <= 0; lsu_exc_reg <= 0;
                alu0_exccode <= 0; alu1_exccode <= 0; lsu_exccode_reg <= 0;
                alu0_btarget <= 0; alu1_btarget <= 0; lsu_excaddr_reg <= 0;
                alu0_btaken <= 0; alu1_btaken <= 0;
                alu0_ertn <= 0; alu1_ertn <= 0; alu0_idle <= 0; alu1_idle <= 0; 
        end else begin
            // 清除
            if (clr_alu0) alu0_valid <= 0;
            if (clr_alu1) alu1_valid <= 0;
            if (clr_mul)  mul_valid  <= 0;
            if (clr_div)  div_valid  <= 0;
            if (clr_lsu)  lsu_valid  <= 0;

            // ALU0 锁存（使�? inst0_alu �? alu0_rob_idx�?
            if(inst0_alu && (clr_alu0 || !alu0_valid)) begin
                alu0_valid    <= 1;
                alu0_rob      <= r_inst0_rob;          // 使用提前锁存的索�?
                alu0_exc      <= o_alu0_exception;
                alu0_exccode  <= o_alu0_exccode;
                alu0_ertn     <= o_alu0_ertn;
                alu0_idle     <= o_alu0_idle;
                alu0_btarget  <= o_actual_pc0;
                alu0_btaken   <= o_actual_taken0;
                alu0_result   <= o_alu_result0;
            end

            // ALU1 锁存（使�? inst1_alu �? alu1_rob_idx�?
            if(inst1_alu && (clr_alu1 || !alu1_valid)) begin
                alu1_valid    <= 1;
                alu1_rob      <= r_inst1_rob;
                alu1_exc      <= o_alu1_exception;
                alu1_exccode  <= o_alu1_exccode;
                alu1_ertn     <= o_alu1_ertn;
                alu1_idle     <= o_alu1_idle;
                alu1_btarget  <= o_actual_pc1;
                alu1_btaken   <= o_actual_taken1;
                alu1_result   <= o_alu_result1;
            end

            // MUL 锁存
            if (mul_done && !mul_valid) begin
                mul_valid      <= 1;
                mul_result_reg <= mul_result;
            end

            // DIV 锁存
            if (div_done && !div_valid) begin
                div_valid      <= 1;
                div_result_reg <= div_result;
            end

            // LSU 锁存
            if (lsu_result_valid && (!lsu_valid |clr_lsu)) begin
                lsu_valid       <= 1;
                lsu_result_reg  <= lsu_result;
                lsu_exc_reg     <= lsu_exception;
                lsu_exccode_reg <= lsu_exccode;
                lsu_excaddr_reg <= lsu_excaddr;
            end

            if (inst0_mul || inst1_mul) begin
                mul_rob <= inst0_mul ? r_inst0_rob : r_inst1_rob;
            end else begin
                mul_rob <= mul_rob; // 保持不变
            end

            if(inst0_div || inst1_div) begin
                div_rob <= inst0_div ? r_inst0_rob : r_inst1_rob;
            end else begin
                div_rob <= div_rob; // 保持不变
            end

            if(inst0_lsu || inst1_lsu) begin
                lsu_rob <= inst0_lsu ? r_inst0_rob : r_inst1_rob;
            end else begin
                lsu_rob <= lsu_rob; // 保持不变
            end
        end
    end

    //执行单元结果
    assign exe_2_disp_rjdata0 =( disp_rob_idx0_rj == alu0_rob && alu0_valid )? o_alu_result0 :
                                (disp_rob_idx0_rj == alu1_rob && alu1_valid )? o_alu_result1 :
                                (disp_rob_idx0_rj == mul_rob  && mul_done ) ?mul_result :
                                (disp_rob_idx0_rj == div_rob  && div_done ) ?div_result :
                                (disp_rob_idx0_rj == lsu_rob && lsu_result_valid ) ?lsu_result : 32'b0 ;
    assign exe_2_disp_rkdata0 =( disp_rob_idx0_rk == alu0_rob && alu0_valid )? o_alu_result0 :
                                (disp_rob_idx0_rk == alu1_rob && alu1_valid )?o_alu_result1 :
                                (disp_rob_idx0_rk == mul_rob  && mul_done ) ?mul_result :
                                (disp_rob_idx0_rk == div_rob  && div_done ) ?div_result :
                                (disp_rob_idx0_rk == lsu_rob && lsu_result_valid ) ?lsu_result : 32'b0 ;
    assign exe_2_disp_rjdata1 =( disp_rob_idx1_rj == alu0_rob && alu0_valid )? o_alu_result0 :
                                (disp_rob_idx1_rj == alu1_rob && alu1_valid )?o_alu_result1 :
                                (disp_rob_idx1_rj == mul_rob  && mul_done  ) ?mul_result :
                                (disp_rob_idx1_rj == div_rob  && div_done  ) ?div_result :
                                (disp_rob_idx1_rj == lsu_rob && lsu_result_valid   ) ?lsu_result : 32'b0 ;
    assign exe_2_disp_rkdata1 =( disp_rob_idx1_rk == alu0_rob && alu0_valid )? o_alu_result0 :
                                (disp_rob_idx1_rk == alu1_rob && alu1_valid )?o_alu_result1 :
                                (disp_rob_idx1_rk == mul_rob  && mul_done  ) ?mul_result :
                                (disp_rob_idx1_rk == div_rob  && div_done  ) ?div_result :
                                (disp_rob_idx1_rk == lsu_rob && lsu_result_valid   ) ?lsu_result : 32'b0 ;

    assign exe_2_rj0_ready = ( disp_rob_idx0_rj == alu0_rob && alu0_valid )
                               || (disp_rob_idx0_rj == alu1_rob && alu1_valid )
                                ||(disp_rob_idx0_rj == mul_rob  && mul_done )
                                ||(disp_rob_idx0_rj == div_rob  && div_done )
                                ||(disp_rob_idx0_rj == lsu_rob && lsu_result_valid ) ;
    assign exe_2_rk0_ready =( disp_rob_idx0_rk == alu0_rob && alu0_valid )
                                || (disp_rob_idx0_rk == alu1_rob && alu1_valid )
                                || (disp_rob_idx0_rk == mul_rob  && mul_done )
                                || (disp_rob_idx0_rk == div_rob  && div_done )
                                || (disp_rob_idx0_rk == lsu_rob && lsu_result_valid ) ;
    assign exe_2_rj1_ready = ( disp_rob_idx1_rj == alu0_rob && alu0_valid )
                              || (disp_rob_idx1_rj == alu1_rob && alu1_valid )
                              || (disp_rob_idx1_rj == mul_rob  && mul_done  )
                              || (disp_rob_idx1_rj == div_rob  && div_done  )
                              || (disp_rob_idx1_rj == lsu_rob && lsu_result_valid   ) ;   
    assign exe_2_rk1_ready  =( disp_rob_idx1_rk == alu0_rob && alu0_valid )
                               || (disp_rob_idx1_rk == alu1_rob && alu1_valid )
                               || (disp_rob_idx1_rk == mul_rob  && mul_done  )
                               || (disp_rob_idx1_rk == div_rob  && div_done  )
                               || (disp_rob_idx1_rk == lsu_rob && lsu_result_valid   );
    // 仲裁：优先级 DIV > LSU > MUL > ALU0 > ALU1
    wire [4:0] fu_valid_vec = {lsu_valid, div_valid, mul_valid, alu1_valid, alu0_valid};

    // 优先级编码器 0（always @(*) 替代 function，确保仿真器敏感度正确）
    always @(*) begin
        if (fu_valid_vec[3])      sel0 = 3'd3;    // DIV
        else if (fu_valid_vec[4]) sel0 = 3'd4;    // LSU
        else if (fu_valid_vec[2]) sel0 = 3'd2;    // MUL
        else if (fu_valid_vec[0]) sel0 = 3'd0;    // ALU0
        else if (fu_valid_vec[1]) sel0 = 3'd1;    // ALU1
        else                      sel0 = 3'b111;  // none
    end

    assign mask1 = fu_valid_vec & ~(5'b1 << sel0);  //屏蔽第一条仲裁的结果

    // 优先级编码器 1
    always @(*) begin
        if (mask1[3])      sel1 = 3'd3;    // DIV
        else if (mask1[4]) sel1 = 3'd4;    // LSU
        else if (mask1[2]) sel1 = 3'd2;    // MUL
        else if (mask1[0]) sel1 = 3'd0;    // ALU0
        else if (mask1[1]) sel1 = 3'd1;    // ALU1
        else               sel1 = 3'b111;  // none
    end

    // 生成 77 位写回包（使�? always @(*) 替代 function+wire，确保仿真器�? reg 信号敏感�?
    reg [76:0] wb0_r, wb1_r;
    always @(*) begin
        case (sel0)
            3'd0: wb0_r = {1'b1, alu0_rob, alu0_result, alu0_exc, alu0_exccode, alu0_btaken, alu0_btarget, 1'b0};
            3'd1: wb0_r = {1'b1, alu1_rob, alu1_result, alu1_exc, alu1_exccode, alu1_btaken, alu1_btarget, 1'b0};
            3'd2: wb0_r = {1'b1, mul_rob, mul_result_reg, 1'b0, 6'd0, 1'b0, 32'd0, 1'b0};
            3'd3: wb0_r = {1'b1, div_rob, div_result_reg, 1'b0, 6'd0, 1'b0, 32'd0, 1'b0};
            3'd4: wb0_r = {1'b1, lsu_rob, lsu_result_reg, lsu_exc_reg, lsu_exccode_reg, 1'b0, lsu_excaddr_reg, 1'b0};
            default: wb0_r = 77'b0;
        endcase
    end
    always @(*) begin
        case (sel1)
            3'd0: wb1_r = {1'b1, alu0_rob, alu0_result, alu0_exc, alu0_exccode, alu0_btaken, alu0_btarget, 1'b0};
            3'd1: wb1_r = {1'b1, alu1_rob, alu1_result, alu1_exc, alu1_exccode, alu1_btaken, alu1_btarget, 1'b0};
            3'd2: wb1_r = {1'b1, mul_rob, mul_result_reg, 1'b0, 6'd0, 1'b0, 32'd0, 1'b0};
            3'd3: wb1_r = {1'b1, div_rob, div_result_reg, 1'b0, 6'd0, 1'b0, 32'd0, 1'b0};
            3'd4: wb1_r = {1'b1, lsu_rob, lsu_result_reg, lsu_exc_reg, lsu_exccode_reg, 1'b0, lsu_excaddr_reg, 1'b0};
            default: wb1_r = 77'b0;
        endcase
    end
    wire [76:0] wb0 = (sel0 != 3'b111) ? wb0_r : 77'b0;
    wire [76:0] wb1 = (sel1 != 3'b111) ? wb1_r : 77'b0;

    // 连接到原端口 o_2_rob_wb�?154位）
    assign o_2_rob_wb = {wb1, wb0};

    // CDB 输出（仅无异常时广播�?
    wire exc0 = (sel0 == 3'b111) ? 1'b0 : (sel0 == 0) ? alu0_exc : (sel0 == 1) ? alu1_exc : (sel0 == 4) ? lsu_exc_reg : 1'b0;
    wire [31:0] cdb_val0 = (sel0 == 0) ? alu0_result : (sel0 == 1) ? alu1_result : (sel0 == 2) ? mul_result_reg : (sel0 == 3) ? div_result_reg : (sel0 == 4) ? lsu_result_reg : 32'd0;
    wire [2:0] cdb_rob0 = (sel0 == 0) ? alu0_rob : (sel0 == 1) ? alu1_rob : (sel0 == 2) ? mul_rob : (sel0 == 3) ? div_rob : (sel0 == 4) ? lsu_rob : 3'd0;

    assign o_cdb_valid0 = (sel0 != 3'b111) && !exc0;
    assign o_cdb_rob0   = cdb_rob0;
    assign o_cdb_value0 = cdb_val0;

    wire exc1 = (sel1 == 3'b111) ? 1'b0 : (sel1 == 0) ? alu0_exc : (sel1 == 1) ? alu1_exc : (sel1 == 4) ? lsu_exc_reg : 1'b0;
    wire [31:0] cdb_val1 = (sel1 == 0) ? alu0_result : (sel1 == 1) ? alu1_result : (sel1 == 2) ? mul_result_reg : (sel1 == 3) ? div_result_reg : (sel1 == 4) ? lsu_result_reg : 32'd0;
    wire [2:0] cdb_rob1 = (sel1 == 0) ? alu0_rob : (sel1 == 1) ? alu1_rob : (sel1 == 2) ? mul_rob : (sel1 == 3) ? div_rob : (sel1 == 4) ? lsu_rob : 3'd0;

    assign o_cdb_valid1 = (sel1 != 3'b111) && !exc1;
    assign o_cdb_rob1   = cdb_rob1;
    assign o_cdb_value1 = cdb_val1;

    //输出空闲信号free
    assign  o_fu_free = {   !alu0_valid,        // ALU0 空闲（结果已被取走）
                            !alu1_valid,        // ALU1
                            mul_ready && !mul_valid,
                            div_ready && !div_valid,
                            lsu_ready && !lsu_valid && !lsu_load_stall};

//    reg mul_clear_buffer, div_clear_buffer;
//    reg mul_valid_buffer, div_valid_buffer;

//    always @(posedge clk or negedge rstn) begin
//        if(!rstn) begin
//            mul_clear_buffer <= 0;
//            mul_valid_buffer <= 0;
//            div_clear_buffer <= 0;
//            div_valid_buffer <= 0;
//        end else begin
//            if(mul_en)
//                mul_valid_buffer <= 1;
//            else if(mul_done)
//                mul_valid_buffer <= 0;
//            if(div_en)
//                div_valid_buffer <= 1;
//            else if(div_done)
//                div_valid_buffer <= 0;

//            if((mul_en || mul_valid_buffer) && flush)
//                mul_clear_buffer <= 1;
//            else if(mul_done_wire)
//                mul_clear_buffer <= 0;
//            if((div_en || div_valid_buffer) && flush)
//                div_clear_buffer <= 1;
//            else if(div_done_wire)
//                div_clear_buffer <= 0;
            
//        end
//    end

    alu u_alu0(
        .clk           (clk),
        .rstn          (rstn),
        .i_alu_data    (alu0_data),
        .i_cnt_data_64(i_cnt_data_64),
        .i_cnt_id(i_cnt_id),
        .o_alu_result  (o_alu_result0),
        .o_actual_pc   (o_actual_pc0),
        .o_actual_taken(o_actual_taken0),
        .o_exception   (o_alu0_exception),
        .o_exccode     (o_alu0_exccode),
        .o_ertn        (o_alu0_ertn),
        .o_idle        (o_alu0_idle)
    );

    alu u_alu1(
        .clk           (clk),
        .rstn          (rstn),
        .i_alu_data    (alu1_data),
        .i_cnt_data_64(i_cnt_data_64),
        .i_cnt_id(i_cnt_id),
        .o_alu_result  (o_alu_result1),
        .o_actual_pc   (o_actual_pc1),
        .o_actual_taken(o_actual_taken1),
        .o_exception   (o_alu1_exception),
        .o_exccode     (o_alu1_exccode),
        .o_ertn        (o_alu1_ertn),
        .o_idle        (o_alu1_idle)
    );    

    wire mul_done_wire;
    wire [31:0] mul_result_wire;
    mul u_mul(
        .clk(clk),
        .rst_n(rstn),
        .mul_en(mul_en ),
        .a(mul_a ), //32
        .b(mul_b ), //32
        .mul_ready(mul_ready),
        .mul_done(mul_done),
        .mul_op(mul_op),
        .mul_result(mul_result),
        .flush(flush)
    );

//    assign mul_done = mul_done_wire & ~mul_clear_buffer;
//    assign mul_result = mul_result_wire & ~{32{mul_clear_buffer}};

    wire div_done_wire;
    wire [31:0] div_result_wire;
    div u_div(
        .Z_in(div_z),
        .D_in(div_d),
        .ena(div_en),
        .div_op(div_op),
        .clk(clk),
        .rstn(rstn),
        .div_result(div_result),
        .over(div_done ),
        .ready(div_ready),
        .flush(flush)

    );

//    assign div_done = div_done_wire & ~div_clear_buffer;
//    assign div_result = div_result_wire & {32{~div_clear_buffer}};

    lsu u_lsu(
        .clk(clk),
        .rstn(rstn),
        .stop(1'b0),
        .clear(flush),
        .valid_i (lsu_en),
        .op_lsu_i(lsu_op),
        .base_i(lsu_base),
        .offset_i(lsu_offs),
        .st_data_i(lsu_sdata),
        .rd_index_i(lsu_rd_index),  // 相当于cacop中的code
        .pc_i(lsu_pc),
        .tlb_data_i(lsu_tlb_data),
        .cacop_sign_i(lsu_cacop_sign),
        .preld_sign_i(lsu_preld_sign),
        .lsu_stall_o(lsu_stall),

        .lsu_result(lsu_result),
        .lsu_result_valid(lsu_result_valid),
        .lsu_exception(lsu_exception),
        .lsu_exccode(lsu_exccode),
        .lsu_excaddr(lsu_excaddr),

        //lsu为多端口输入，需要与csr和tlb连接，所以这里将这些端口直出exe顶层
        .crmd_da            (crmd_da          ),             
        .crmd_pg            (crmd_pg          ),                 
        .crmd_datm          (crmd_datm        ),         
        .crmd_plv           (crmd_plv         ),       
        .csr_tlbehi_vppn    (csr_tlbehi_vppn  ),          
        .csr_asid_asid      (csr_asid_asid    ),        
        .dmw0_plv0          (dmw0_plv0        ),
        .dmw0_plv3          (dmw0_plv3        ),    
        .dmw0_mat           (dmw0_mat         ),       
        .dmw0_pseg          (dmw0_pseg        ),    
        .dmw0_vseg          (dmw0_vseg        ),    
        .dmw1_plv0          (dmw1_plv0        ),    
        .dmw1_plv3          (dmw1_plv3        ),        
        .dmw1_mat           (dmw1_mat         ),    
        .dmw1_pseg          (dmw1_pseg        ),    
        .dmw1_vseg          (dmw1_vseg        ),    
        .invtlb_valid       (invtlb_valid     ),    
        .invtlb_op          (invtlb_op        ),    
        .invtlb_vppn        (invtlb_vppn      ),    
        .invtlb_asid        (invtlb_asid      ),    
        .tlb_s1_vppn        (tlb_s1_vppn      ),    
        .tlb_s1_va_odd      (tlb_s1_va_odd    ),    
        .tlb_s1_asid        (tlb_s1_asid      ),    
        .tlb_s1_found       (tlb_s1_found     ),    
        .tlb_s1_index       (tlb_s1_index     ),    
        .tlb_s1_ppn         (tlb_s1_ppn       ),    
        .tlb_s1_ps          (tlb_s1_ps        ),    
        .tlb_s1_plv         (tlb_s1_plv       ),    
        .tlb_s1_mat         (tlb_s1_mat       ),    
        .tlb_s1_d           (tlb_s1_d         ),    
        .tlb_s1_v           (tlb_s1_v         ),         
        .store_valid        (store_valid      ),      
        .store_paddr        (store_paddr      ),      
        .store_data         (store_data       ),      
        .store_mask         (store_mask       ),      
        .store_size         (store_size       ),      
        .store_is_uncache   (store_is_uncache ),      
        .store_is_cacop     (store_is_cacop   ),      
        .store_cacop_op     (store_cacop_op   ),      
        .store_ready        (store_ready      ),      
        .load_valid         (load_valid       ),      
        .load_paddr         (load_paddr       ),      
        .load_size          (load_size        ),                
        .load_is_uncache    (load_is_uncache  ),      
        .load_ready         (load_ready       ),       
        .load_result        (load_result      ),              
        .load_result_valid  (load_result_valid),      
        .ls_stall_i         (ls_stall_i       ),
        .icache_cacop_en    (icache_cacop_en  ),
        .icache_cacop_op    (icache_cacop_op  ),
        .icache_cacop_va    (icache_cacop_va  ),    
        .preld_en           (preld_en         ),
        .preld_hint         (preld_hint       )                                       
    );  

endmodule