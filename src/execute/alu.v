`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Description: 
// alu要完成的计算如下：
// 1.加减，逻辑，移位，比较，
// 2.分支指令
// 3.lu12i 和 pcaddu12i -- zero_imm型数据，√
// 4.csrwr csrrd csrxchg    
// 5.idle ,cpucfg ,nop , dbar ,ibar  
// 6.syscall , break , ertn  
//////////////////////////////////////////////////////////////////////////////////

module alu(
    input           clk             ,
    input           rstn            ,
    input  [217:0]      i_alu_data      ,   //分发过来的alu数据包，寄存器操作数，立即数，selcode，opcode，csr相关 + 分支指令的信息
    //csr + cnt + exception + idle + ertn + cpucfg_sign + pc + rj + rk + imm32 + offs32 + aluopcode + aluselcode +  b_opcode
    // 16 + 8   +    7      +   1   +1     +  1        + 32  + 32 + 32 + 32   + 32     + 11       + 4           + 9   =  218
    //添加计数器相关的数据
    input [63:0]       i_cnt_data_64      ,   //计数器数据
    input [31:0]       i_cnt_id      ,   //计数器id
    //alu计算结果，根据opcode来选择指令的计算结果，输出到rob中
    output     [31:0]   o_alu_result    ,
    // output reg [31:0]   gr_data     ,   //bl和jilr指令需要写寄存器，目的寄存器的编号rob中已经记录
    output reg [31:0]   o_actual_pc    ,    //分支指令的跳转pc
    output reg          o_actual_taken , //分支指令实际是否跳转
    output reg [5:0]    o_exccode ,
    output reg          o_exception ,
    output reg          o_idle,
    output reg          o_ertn 
    // //与csr相关的端口
    // output [31:0] o_csr_wr_data,  // CSR 写入数据（rd 旧值）
    // output [31:0] o_csr_mask,     // CSRXCHG 掩码（rj 值）
    // output [15:0] o_csr_info      // {csr_num[13:0], csr_op[1:0]}，原样来自 csr_data
    );
    //将数据包拆解
    wire [31:0] pc ,rj_data, rk_data , imm32, offs32 ;  //在发射队列，imm32和offs32都当作是一个32位的数据，不用区分开来这是进行普通指令的计算还是分支指令的偏移量，但alu中区分开来（只是命名不同，但数据一样）
    wire [10:0] alu_opcode ;
    wire [3:0]  alu_selcode ;
    wire [8:0]  b_opcode  ;
    //特殊指令
    wire [15:0] csr_data;
    wire [ 7:0] cnt_opcode;
    wire [ 6:0] exception_field;   // {ex_sign, ecode[5:0]}
    wire        idle_flag;
    wire        ertn_flag;
    wire        cpucfg_sign ;

    wire ex_sign = exception_field[6];
    wire [5:0] ecode = exception_field[5:0];

    assign {csr_data, cnt_opcode, exception_field, idle_flag, ertn_flag,cpucfg_sign, pc, rj_data , rk_data, imm32 ,offs32, alu_opcode , alu_selcode, b_opcode  } = i_alu_data ;
    
    
    /*普通的整型指令*/
    /*一般指令*/
    wire    [31:0]      data_1,data_2;    //两个操作数
    assign data_1 = alu_selcode[0] ? rj_data :
                    alu_selcode[1] ? rj_data :
                    alu_selcode[2] ? pc      :
                    alu_selcode[3] ? 32'b0   : 32'b0;

    assign data_2 = alu_selcode[0] ? rk_data :
                    alu_selcode[1] ? imm32   :
                    alu_selcode[2] ? imm32   :
                    alu_selcode[3] ? imm32   : 32'b0;
    
wire [31:0] and_data, or_data, nor_data, xor_data, add_data, sub_data, sll_data, srl_data, sra_data, slt_data, sltu_data;
assign and_data  = data_1 & data_2;                                          //AND
assign or_data   = data_1 | data_2;                                          //OR
assign nor_data   = ~or_data;                                                 //NOR
assign xor_data  = data_1 ^ data_2;                                          //XOR
assign add_data  = data_1 + data_2;                                          //ADD
assign sub_data  = data_1 - data_2;                                          //SUB
assign sll_data  = data_1 << data_2[4:0];                                    //SLL
assign srl_data  = data_1 >> data_2[4:0];                                    //SRL
assign sra_data  = $signed(data_1) >>> $signed(data_2[4:0]);                //SRA`
assign slt_data  = (($signed(data_1) < $signed(data_2)) ? 32'b1 : 32'b0);    //SLT
assign sltu_data = (($unsigned(data_1) < $unsigned(data_2)) ? 32'b1 : 32'b0);//SLTU

    /*分支指令的处理*/
wire [31:0]b_data1, b_data2 ; 
assign b_data1 = b_opcode [5:0] != 6'b0 ? rj_data : // beq, ben, blt,bltu,bge,bgeu 
                 b_opcode [6]   == 1'b1 ? rj_data : // jirl
                 b_opcode [7]   == 1'b1 ? offs32  : // bl
                 b_opcode [8]   == 1'b1 ? offs32  : 32'b0; //b 

assign b_data2 = b_opcode [5:0] != 6'b0 ? rk_data :     //指令集中是使用rd，但其实也只是一个源寄存器，我们统一使用rk命名
                 b_opcode [6]   == 1'b1 ? rj_data :     //
                 b_opcode [7]   == 1'b1 ? offs32  :
                 b_opcode [8]   == 1'b1 ? offs32  : 32'b0; 
            
wire  eq_sign , less_signed_sign , less_unsigned_sign ;
assign eq_sign = b_data1 == b_data2 ;   //1-beq, 0-ben
assign less_signed_sign = $signed(b_data1) < $signed(b_data2 ) ; //1-blt , 0-bge
assign less_unsigned_sign = $unsigned(b_data1 ) < $unsigned(b_data2) ; // 1-bltu ,0-bge

wire [31:0] cpucfg_r_value;
wire special_or_exc = ex_sign | ertn_flag | idle_flag; //异常屏蔽
reg [31:0] gr_data ; //当指令为bl和jilr的时候，需要更改通用寄存器，使用gr_data来暂存，最后还是通过o_alu_result来完成输出

    /*最后输出的结果*/
    //o_alu_result保存的：运算指令和分支指令都保存的要更改到grf中的数据，对应rob中的data
    //
assign o_alu_result = special_or_exc ? 32'd0 : 
                      alu_opcode[0]  ? and_data         :
                      alu_opcode[1]  ? or_data          :
                      alu_opcode[2]  ? nor_data         :
                      alu_opcode[3]  ? xor_data         :
                      alu_opcode[4]  ? add_data         :
                      alu_opcode[5]  ? sub_data         :
                      alu_opcode[6]  ? sll_data         :
                      alu_opcode[7]  ? srl_data         :
                      alu_opcode[8]  ? sra_data         :
                      alu_opcode[9]  ? slt_data         :
                      alu_opcode[10] ? sltu_data        :
           (b_opcode[7] || b_opcode[6]) ? gr_data         :
                      cnt_opcode[7] ? i_cnt_id          :
                      cnt_opcode[6] ? i_cnt_data_64[31:0]:
                      cnt_opcode[5] ? i_cnt_data_64[63:32] :
                      cpucfg_sign    ? cpucfg_r_value   :   //cpucfg指令的输出，cpucfg_sign信号在发射队列中已经被设置好
                      csr_data[15]   ? rk_data        :
                      32'b0;

always@(*)begin

    // 默认值
    o_exception   = 1'b0;
    o_exccode     = 6'd0;
    o_ertn        = 1'b0;
    o_idle        = 1'b0;
    o_actual_pc   = pc + 32'h4;
    o_actual_taken = 1'b0;
    gr_data       = 32'h0;

    // 1. 译码阶段前传的异常（优先级最高）
    if (ex_sign) begin
        o_exception = 1'b1;
        o_exccode   = ecode;
    end
    // 2. ERTN
    else if (ertn_flag) begin
        o_exception = 1'b1;
        o_exccode   = 6'h3D;   // 自定义：ERTN 特殊码
        o_ertn      = 1'b1;
    end
    // 3. IDLE
    else if (idle_flag) begin
        o_exception = 1'b1;
        o_exccode   = 6'h3E;   // 自定义：IDLE 特殊码
        o_idle      = 1'b1;
    end
    // 4. 正常指令（包括分支）
    else begin
        case(b_opcode)
        9'b0_0000_0000: begin if(csr_data [15])         begin o_actual_pc = rj_data    ;  o_actual_taken = 0 ;end  else begin o_actual_pc = pc + 32'h4 ; o_actual_taken = 0 ;end  end
        9'b0_0000_0001: begin if( ~less_unsigned_sign ) begin o_actual_pc = pc + offs32 ; o_actual_taken = 1 ;end  else begin o_actual_pc = pc + 32'h4 ; o_actual_taken = 0 ;end  end
        9'b0_0000_0010: begin if( ~less_signed_sign   ) begin o_actual_pc = pc + offs32 ; o_actual_taken = 1 ;end  else begin o_actual_pc = pc + 32'h4 ; o_actual_taken = 0 ;end  end
        9'b0_0000_0100: begin if(  less_unsigned_sign ) begin o_actual_pc = pc + offs32 ; o_actual_taken = 1 ;end  else begin o_actual_pc = pc + 32'h4 ; o_actual_taken = 0 ;end  end
        9'b0_0000_1000: begin if(  less_signed_sign   ) begin o_actual_pc = pc + offs32 ; o_actual_taken = 1 ;end  else begin o_actual_pc = pc + 32'h4 ; o_actual_taken = 0 ;end  end
        9'b0_0001_0000: begin if( ~eq_sign            ) begin o_actual_pc = pc + offs32 ; o_actual_taken = 1 ;end  else begin o_actual_pc = pc + 32'h4 ; o_actual_taken = 0 ;end  end
        9'b0_0010_0000: begin if(  eq_sign            ) begin o_actual_pc = pc + offs32 ; o_actual_taken = 1 ;end  else begin o_actual_pc = pc + 32'h4 ; o_actual_taken = 0 ;end  end
        9'b0_0100_0000: begin gr_data = pc + 32'h4 ; o_actual_pc = offs32 + b_data1 ; o_actual_taken = 1 ;end //jilr
        9'b0_1000_0000: begin gr_data = pc + 32'h4 ; o_actual_pc = pc + offs32 ;   o_actual_taken = 1 ; end//bl
        9'b1_0000_0000: begin o_actual_pc = pc + offs32 ;  o_actual_taken = 1 ;end//b
        default : begin  o_actual_pc = pc + 32'h4 ;o_actual_taken = 0 ; end
        endcase
    end
end

// /*================csr相关指令==================*/
// // 判断是否为 CSR 指令（csr_data 非 0 即为 CSR 指令）
// wire is_csr = (csr_data[15] == 1'b1);//最高位为csr_sign

// // 根据指令类型选择源操作数
// // 假设译码阶段已将 CSRWR/CSRXCHG 的 rd 旧值放在 rj_data，CSRXCHG 的掩码放在 rk_data
// // CSRRD 无源操作数
// assign o_csr_wr_data = is_csr ? rj_data : 32'd0;   // CSRWR/CSRXCHG 的写入数据
// assign o_csr_mask    = is_csr ? rk_data : 32'd0;   // CSRXCHG 的掩码
// assign o_csr_info    = is_csr ? csr_data : 16'd0;

/*================CPUCFG================*/
//cpucfg的处理，放到alu中，当这条指令到来的时候，获得对应的数据，最后数据放到o_alu_result输出
wire cpucfg_0_prid_31_0;
assign cpucfg_0_prid_31_0 = 32'h11121314;

wire cpucfg_1_arch_1_0, cpucfg_1_pgmmu_2, cpucfg_1_iocsr_3, cpucfg_1_palen_11_4, cpucfg_1_valen_19_12, cpucfg_1_ual_20,
     cpucfg_1_ri_21, cpucfg_1_ep_22, cpucfg_1_rplv_23, cpucfg_1_hp_24, cpucfg_1_crc_25, cpucfg_1_msg_int_26;
assign cpucfg_1_arch_1_0    = 2'b00;
assign cpucfg_1_pgmmu_2     = 1'b0;
assign cpucfg_1_iocsr_3     = 1'b0;
assign cpucfg_1_palen_11_4  = 8'h1f;
assign cpucfg_1_valen_19_12 = 8'h1f;
assign cpucfg_1_ual_20      = 1'b0;
assign cpucfg_1_ri_21       = 1'b0;
assign cpucfg_1_ep_22       = 1'b0;
assign cpucfg_1_rplv_23     = 1'b0;
assign cpucfg_1_hp_24       = 1'b0;
assign cpucfg_1_crc_25      = 1'b0;
assign cpucfg_1_msg_int_26  = 1'b0;

wire cpucfg_2_fp_0, cpucfg_2_fp_sp_1, cpucfg_2_fp_dp_2, cpucfg_2_fp_ver_5_3, cpucfg_2_lsx_6, cpucfg_2_lasx_7,
     cpucfg_2_complex_8, cpucfg_2_crypto_9, cpucfg_2_lvz_10, cpucfg_2_lvz_ver_13_11, cpucfg_2_llftp_14, cpucfg_2_llftp_ver_17_15,
     cpucfg_2_lbt_x86_18, cpucfg_2_lbt_arm_19, cpucfg_2_lbt_mips_20, cpucfg_2_lspw_21, cpucfg_2_lam_22, cpucfg_2_hptw_24,
     cpucfg_2_frecipe_25, cpucfg_2_div32_26, cpucfg_2_lam_bh_27, cpucfg_2_lamcas_28, cpucfg_2_llacq_screl_29, cpucfg_2_scq_30;
assign cpucfg_2_fp_0            = 1'b0;
assign cpucfg_2_fp_sp_1         = 1'b0;
assign cpucfg_2_fp_dp_2         = 1'b0;
assign cpucfg_2_fp_ver_5_3      = 3'b0;
assign cpucfg_2_lsx_6           = 1'b0;
assign cpucfg_2_lasx_7          = 1'b0;
assign cpucfg_2_complex_8       = 1'b0;
assign cpucfg_2_crypto_9        = 1'b0;
assign cpucfg_2_lvz_10          = 1'b0;
assign cpucfg_2_lvz_ver_13_11   = 3'b0;
assign cpucfg_2_llftp_14        = 1'b0;
assign cpucfg_2_llftp_ver_17_15 = 3'b0;
assign cpucfg_2_lbt_x86_18      = 1'b0;
assign cpucfg_2_lbt_arm_19      = 1'b0;
assign cpucfg_2_lbt_mips_20     = 1'b0;
assign cpucfg_2_lspw_21         = 1'b0;
assign cpucfg_2_lam_22          = 1'b0;
assign cpucfg_2_hptw_24         = 1'b0;
assign cpucfg_2_frecipe_25      = 1'b0;
assign cpucfg_2_div32_26        = 1'b0;
assign cpucfg_2_lam_bh_27       = 1'b0;
assign cpucfg_2_lamcas_28       = 1'b0;
assign cpucfg_2_llacq_screl_29  = 1'b0;
assign cpucfg_2_scq_30          = 1'b0;

wire cpucfg_3_ccdma_0, cpucfg_3_sfb_1, cpucfg_3_ucacc_2, cpucfg_3_llexc_3, cpucfg_3_scdly_4, cpucfg_3_lldbar_5, cpucfg_3_ltlbhmc_6,
     cpucfg_3_ichmc_7, cpucfg_3_spw_lvl_10_8, cpucfg_3_spw_hp_hf_11, cpucfg_3_rva_12, cpucfg_3_rvamax_1_16_13, cpucfg_3_dbar_hints_17,
     cpucfg_3_ld_seq_sa_23;
assign cpucfg_3_ccdma_0        = 1'b0;
assign cpucfg_3_sfb_1          = 1'b0;
assign cpucfg_3_ucacc_2        = 1'b0;
assign cpucfg_3_llexc_3        = 1'b0;
assign cpucfg_3_scdly_4        = 1'b0;
assign cpucfg_3_lldbar_5       = 1'b0;
assign cpucfg_3_ltlbhmc_6      = 1'b0;
assign cpucfg_3_ichmc_7        = 1'b0;
assign cpucfg_3_spw_lvl_10_8   = 3'b0;
assign cpucfg_3_spw_hp_hf_11   = 1'b0;
assign cpucfg_3_rva_12         = 1'b0;
assign cpucfg_3_rvamax_1_16_13 = 4'b0;
assign cpucfg_3_dbar_hints_17  = 1'b0;
assign cpucfg_3_ld_seq_sa_23   = 1'b0;

wire cpucfg_4_cc_freq_31_0;
assign cpucfg_4_cc_freq_31_0 = 32'b0;

wire cpucfg_5_cc_mul_15_0, cpucfg_5_cc_div_31_16;
assign cpucfg_5_cc_mul_15_0  = 16'b0;
assign cpucfg_5_cc_div_31_16 = 16'b0;

wire cpucfg_6_pmp_0, cpucfg_6_pmver_3_1, cpucfg_6_pmnum_7_4, cpucfg_6_pmbits_13_8, cpucfg_6_upm_14;
assign cpucfg_6_pmp_0       = 1'b0;
assign cpucfg_6_pmver_3_1   = 3'b0;
assign cpucfg_6_pmnum_7_4   = 4'b0;
assign cpucfg_6_pmbits_13_8 = 6'b0;
assign cpucfg_6_upm_14      = 1'b0;

wire cpucfg_10_l1_iu_present_0, cpucfg_10_l1_iu_unify_1, cpucfg_10_l1_d_present_2, cpucfg_10_l2_iu_present_3, cpucfg_10_l2_iu_unify_4,
     cpucfg_10_l2_iu_private_5, cpucfg_10_l2_iu_inclusive_6, cpucfg_10_l2_d_present_7, cpucfg_10_l2_d_private_8, cpucfg_10_l2_d_inclusive_9,
     cpucfg_10_l3_iu_present_10, cpucfg_10_l3_iu_unify_11, cpucfg_10_l3_iu_private_12, cpucfg_10_l3_iu_inclusive_13, cpucfg_10_l3_d_present_14,
     cpucfg_10_l3_d_private_15, cpucfg_10_l3_d_inclusive_16;
assign cpucfg_10_l1_iu_present_0    = 1'b1;
assign cpucfg_10_l1_iu_unify_1      = 1'b0;
assign cpucfg_10_l1_d_present_2     = 1'b1;
assign cpucfg_10_l2_iu_present_3    = 1'b0;
assign cpucfg_10_l2_iu_unify_4      = 1'b0;
assign cpucfg_10_l2_iu_private_5    = 1'b0;
assign cpucfg_10_l2_iu_inclusive_6  = 1'b0;
assign cpucfg_10_l2_d_present_7     = 1'b0;
assign cpucfg_10_l2_d_private_8     = 1'b0;
assign cpucfg_10_l2_d_inclusive_9   = 1'b0;
assign cpucfg_10_l3_iu_present_10   = 1'b0;
assign cpucfg_10_l3_iu_unify_11     = 1'b0;
assign cpucfg_10_l3_iu_private_12   = 1'b0;
assign cpucfg_10_l3_iu_inclusive_13 = 1'b0;
assign cpucfg_10_l3_d_present_14    = 1'b0;
assign cpucfg_10_l3_d_private_15    = 1'b0;
assign cpucfg_10_l3_d_inclusive_16  = 1'b0;

wire cpucfg_11_way_1_15_0, cpucfg_11_index_log2_23_16, cpucfg_11_linesize_log2_30_24;
assign cpucfg_11_way_1_15_0          = 16'h1;
assign cpucfg_11_index_log2_23_16    = 8'h4;
assign cpucfg_11_linesize_log2_30_24 = 7'h8;

wire cpucfg_12_way_1_15_0, cpucfg_12_index_log2_23_16, cpucfg_12_linesize_log2_30_24;
assign cpucfg_12_way_1_15_0          = 16'h1;
assign cpucfg_12_index_log2_23_16    = 8'h4;
assign cpucfg_12_linesize_log2_30_24 = 7'h8;

wire cpucfg_13_way_1_15_0, cpucfg_13_index_log2_23_16, cpucfg_13_linesize_log2_30_24;
assign cpucfg_13_way_1_15_0          = 16'h0;
assign cpucfg_13_index_log2_23_16    = 8'h0;
assign cpucfg_13_linesize_log2_30_24 = 7'h0;

wire cpucfg_14_way_1_15_0, cpucfg_14_index_log2_23_16, cpucfg_14_linesize_log2_30_24;
assign cpucfg_14_way_1_15_0          = 16'h0;
assign cpucfg_14_index_log2_23_16    = 8'h0;
assign cpucfg_14_linesize_log2_30_24 = 7'h0;

wire [31:0] cpucfg_0_value, cpucfg_1_value, cpucfg_2_value, cpucfg_3_value, cpucfg_4_value, cpucfg_5_value, cpucfg_6_value, cpucfg_10_value,
            cpucfg_11_value, cpucfg_12_value, cpucfg_13_value, cpucfg_14_value;

assign cpucfg_0_value  = cpucfg_0_prid_31_0;
assign cpucfg_1_value  = {5'b0,cpucfg_1_msg_int_26,cpucfg_1_crc_25,cpucfg_1_hp_24,cpucfg_1_rplv_23,cpucfg_1_ep_22,cpucfg_1_ri_21,cpucfg_1_ual_20,cpucfg_1_valen_19_12,cpucfg_1_palen_11_4,cpucfg_1_iocsr_3,cpucfg_1_pgmmu_2,cpucfg_1_arch_1_0};
assign cpucfg_2_value  = {1'b0,cpucfg_2_scq_30,cpucfg_2_llacq_screl_29,cpucfg_2_lamcas_28,cpucfg_2_lam_bh_27,cpucfg_2_div32_26,cpucfg_2_frecipe_25,cpucfg_2_hptw_24,1'b0,cpucfg_2_lam_22,cpucfg_2_lspw_21,cpucfg_2_lbt_mips_20,cpucfg_2_lbt_arm_19,cpucfg_2_lbt_x86_18,
                          cpucfg_2_llftp_ver_17_15,cpucfg_2_llftp_14,cpucfg_2_lvz_ver_13_11,cpucfg_2_lvz_10,cpucfg_2_crypto_9,cpucfg_2_complex_8,cpucfg_2_lasx_7,cpucfg_2_lsx_6,cpucfg_2_fp_ver_5_3,cpucfg_2_fp_dp_2,cpucfg_2_fp_sp_1,cpucfg_2_fp_0};
assign cpucfg_3_value  = {8'b0,cpucfg_3_ld_seq_sa_23,5'b0,cpucfg_3_dbar_hints_17,cpucfg_3_rvamax_1_16_13,cpucfg_3_rva_12,cpucfg_3_spw_hp_hf_11,cpucfg_3_spw_lvl_10_8,cpucfg_3_ichmc_7,cpucfg_3_ltlbhmc_6,cpucfg_3_lldbar_5,cpucfg_3_scdly_4,cpucfg_3_llexc_3,cpucfg_3_ucacc_2,cpucfg_3_sfb_1,cpucfg_3_ccdma_0};
assign cpucfg_4_value  = cpucfg_4_cc_freq_31_0;
assign cpucfg_5_value  = {cpucfg_5_cc_div_31_16,cpucfg_5_cc_mul_15_0};
assign cpucfg_6_value  = {17'b0,cpucfg_6_upm_14,cpucfg_6_pmbits_13_8,cpucfg_6_pmnum_7_4,cpucfg_6_pmver_3_1,cpucfg_6_pmp_0};
assign cpucfg_10_value = {15'b0,cpucfg_10_l3_d_inclusive_16,cpucfg_10_l3_d_private_15,cpucfg_10_l3_d_present_14,cpucfg_10_l3_iu_inclusive_13,cpucfg_10_l3_iu_private_12,cpucfg_10_l3_iu_unify_11,cpucfg_10_l3_iu_present_10,cpucfg_10_l2_d_inclusive_9,cpucfg_10_l2_d_private_8,
                          cpucfg_10_l2_d_present_7,cpucfg_10_l2_iu_inclusive_6,cpucfg_10_l2_iu_private_5,cpucfg_10_l2_iu_unify_4,cpucfg_10_l2_iu_present_3,cpucfg_10_l1_d_present_2,cpucfg_10_l1_iu_unify_1,cpucfg_10_l1_iu_present_0};
assign cpucfg_11_value = {1'b0,cpucfg_11_linesize_log2_30_24,cpucfg_11_index_log2_23_16,cpucfg_11_way_1_15_0};
assign cpucfg_12_value = {1'b0,cpucfg_12_linesize_log2_30_24,cpucfg_12_index_log2_23_16,cpucfg_12_way_1_15_0};
assign cpucfg_13_value = {1'b0,cpucfg_13_linesize_log2_30_24,cpucfg_13_index_log2_23_16,cpucfg_13_way_1_15_0};
assign cpucfg_14_value = {1'b0,cpucfg_14_linesize_log2_30_24,cpucfg_14_index_log2_23_16,cpucfg_14_way_1_15_0};

wire cpucfg_index = rj_data[4:0] ;
assign cpucfg_r_value = (cpucfg_index == 5'h0 ) ? cpucfg_0_value  :
                        (cpucfg_index == 5'h1 ) ? cpucfg_1_value  :
                        (cpucfg_index == 5'h2 ) ? cpucfg_2_value  :
                        (cpucfg_index == 5'h3 ) ? cpucfg_3_value  :
                        (cpucfg_index == 5'h4 ) ? cpucfg_4_value  :
                        (cpucfg_index == 5'h5 ) ? cpucfg_5_value  :
                        (cpucfg_index == 5'h6 ) ? cpucfg_6_value  :
                        (cpucfg_index == 5'h10) ? cpucfg_10_value :
                        (cpucfg_index == 5'h11) ? 32'h04080001 :
                        (cpucfg_index == 5'h12) ? 32'h04080001 :
                        (cpucfg_index == 5'h13) ? cpucfg_13_value :
                        (cpucfg_index == 5'h14) ? cpucfg_14_value :
                        32'b0;

endmodule
