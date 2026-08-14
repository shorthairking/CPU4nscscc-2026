module decoder (
    // //llbit
    // input  wire        i_llbit,
    

    output wire [ 4:0] o_rj_index_5,        // 这些只是不再需要传到寄存器堆，需要打包发给发射队列
    output wire [ 4:0] o_rk_index_5,
    output wire [ 4:0] o_rd_index_5,

    output wire [23:0] o_id_stop_sign_24,
    output wire        o_id_tlbsrch_sign,
    //送出到stop_controller数据包

    // id_stage内部输入输出---------------------------------
    input  wire [31:0] inst,
    input  wire        ex_sign_in,
    input  wire [ 5:0] ecode_in,

    output wire         inst_PRELD, 
    output wire         inst_ERTN, 
    output wire         inst_IDLE, 
    output wire         inst_CACOP, 
    output wire         inst_CPUCFG, 
    output wire [  9:0] tlb_data, 
    output wire         ex_sign, 
    output wire [  5:0] ecode, 
    output wire [ 15:0] csr_data,               // 禁用寄存器后csr只有这个输出不再有rk_data(与csr有关)
    output wire         grf_no_wen, 
    output wire [ 31:0] offs32, 
    output wire [ 31:0] imm32, 
    output wire [ 10:0] alu_opcode, 
    output wire [  3:0] selcode, 
    output wire [  5:0] op_lsu,
    output wire [  2:0] div_opcode,
    output wire [  2:0] mul_opcode,
    output wire [  7:0] cnt_opcode,  // {inst_RDCNTID, inst_RDCNTVL, inst_RDCNTVH, cnt_index}
    output wire [  8:0] b_insts,
    output wire         is_branch,
    output wire [  1:0] fu_type      // 发给发射队列，便于判断发送到哪个执行单元：00=ALU, 01=MUL, 10=DIV, 11=LSU
);
//..................................................
wire [16:0] func_code_31_15;//R or exception enter
wire [ 9:0] func_code_31_22;//I
wire [ 5:0] func_code_31_26;//B 
wire [ 6:0] func_code_31_25;//U
wire [21:0] func_code_31_10;//exception back
wire [ 7:0] func_code_31_24;//CSR

assign func_code_31_15 = inst[31:15];
assign func_code_31_22 = inst[31:22];
assign func_code_31_26 = inst[31:26];
assign func_code_31_25 = inst[31:25];
assign func_code_31_10 = inst[31:10];
assign func_code_31_24 = inst[31:24];

wire inst_ADD,inst_SUB,inst_SLL,inst_SRL,inst_SRA,inst_AND,inst_OR,inst_NOR,
inst_XOR,inst_SLT,inst_SLTU,inst_ADDI,inst_SLLI,inst_SRLI,inst_SRAI,
inst_ANDI,inst_ORI,inst_XORI,inst_SLTI,inst_SLTUI,

inst_MUL,inst_MULH,inst_MULHU,
inst_DIV,inst_MOD,inst_DIVU,inst_MODU,

inst_B,inst_BL,inst_BEQ,inst_BNE,inst_BLT,inst_BGE,inst_BLTU,inst_BGEU,inst_JIRL,

inst_LDW,inst_LDH,inst_LDB,inst_LDHU,inst_LDBU,inst_STW,inst_STH,inst_STB,
inst_LLW,inst_SCW,

inst_LU12I,inst_PCADDU12I,

// inst_CACOP,inst_PRELD,

inst_TLBSRCH,inst_TLBRD,inst_TLBWR,inst_TLBFILL,inst_INVTLB,

inst_RDCNTID,inst_RDCNTVL,inst_RDCNTVH,

inst_CSRRD,inst_CSRWR,inst_CSRXCHG,

inst_SYSCALL,inst_BREAK,
// inst_ERTN,

// inst_IDLE,inst_CPUCFG,
inst_NOP;

wire inst_DBAR, inst_IBAR;

assign inst_DBAR = (func_code_31_15 == `func_dbar);
assign inst_IBAR = (func_code_31_15 == `func_ibar);

assign inst_ADD     = (func_code_31_15 == `func_add  );
assign inst_SUB     = (func_code_31_15 == `func_sub  );
assign inst_SLL     = (func_code_31_15 == `func_sll  );
assign inst_SRL     = (func_code_31_15 == `func_srl  );
assign inst_SRA     = (func_code_31_15 == `func_sra  );
assign inst_AND     = (func_code_31_15 == `func_and  );
assign inst_OR      = (func_code_31_15 == `func_or   );
assign inst_NOR     = (func_code_31_15 == `func_nor  );
assign inst_XOR     = (func_code_31_15 == `func_xor  );
assign inst_SLT     = (func_code_31_15 == `func_slt  );
assign inst_SLTU    = (func_code_31_15 == `func_sltu );
assign inst_SLLI    = (func_code_31_15 == `func_slli );
assign inst_SRLI    = (func_code_31_15 == `func_srli );
assign inst_SRAI    = (func_code_31_15 == `func_srai );

assign inst_MUL     = (func_code_31_15 == `func_mul  );
assign inst_MULH    = (func_code_31_15 == `func_mulh );
assign inst_MULHU   = (func_code_31_15 == `func_mulhu);
assign inst_DIV     = (func_code_31_15 == `func_div  );
assign inst_MOD     = (func_code_31_15 == `func_mod  );
assign inst_DIVU    = (func_code_31_15 == `func_divu );
assign inst_MODU    = (func_code_31_15 == `func_modu );

assign inst_ADDI    = (func_code_31_22 == `func_addi );
assign inst_ANDI    = (func_code_31_22 == `func_andi );
assign inst_ORI     = (func_code_31_22 == `func_ori  );
assign inst_XORI    = (func_code_31_22 == `func_xori );
assign inst_SLTI    = (func_code_31_22 == `func_slti );
assign inst_SLTUI   = (func_code_31_22 == `func_sltui);

assign inst_LDW     = (func_code_31_22 == `func_ldw  );
assign inst_LDH     = (func_code_31_22 == `func_ldh  );
assign inst_LDB     = (func_code_31_22 == `func_ldb  );
assign inst_LDHU    = (func_code_31_22 == `func_ldhu );
assign inst_LDBU    = (func_code_31_22 == `func_ldbu );
assign inst_STW     = (func_code_31_22 == `func_stw  );
assign inst_STH     = (func_code_31_22 == `func_sth  );
assign inst_STB     = (func_code_31_22 == `func_stb  );
assign inst_LLW     = (func_code_31_24 == `func_llw  );
assign inst_SCW     = (func_code_31_24 == `func_scw  );

assign inst_B       = (func_code_31_26 == `func_b    );
assign inst_BL      = (func_code_31_26 == `func_bl   );
assign inst_BEQ     = (func_code_31_26 == `func_beq  );
assign inst_BNE     = (func_code_31_26 == `func_bne  );
assign inst_BLT     = (func_code_31_26 == `func_blt  );
assign inst_BGE     = (func_code_31_26 == `func_bge  );
assign inst_BLTU    = (func_code_31_26 == `func_bltu );
assign inst_BGEU    = (func_code_31_26 == `func_bgeu );
assign inst_JIRL    = (func_code_31_26 == `func_jirl );

assign inst_LU12I     = (func_code_31_25 == `func_lu12i    );
assign inst_PCADDU12I = (func_code_31_25 == `func_pcaddu12i);

//cache
assign inst_CACOP = (func_code_31_22 == `func_cacop);
assign inst_PRELD = (func_code_31_22 == `func_preld);

//tlb
assign inst_TLBSRCH = (inst == `func_tlbsrch);
assign inst_TLBRD   = (inst == `func_tlbrd  );
assign inst_TLBWR   = (inst == `func_tlbwr  );
assign inst_TLBFILL = (inst == `func_tlbfill);
assign inst_INVTLB  = (func_code_31_15 == `func_invtlb);

//counter
assign inst_RDCNTID = (func_code_31_10 == `func_rdcntid) & (inst[4:0] == 5'h0);
assign inst_RDCNTVL = (func_code_31_10 == `func_rdcntvl) & (inst[9:5] == 5'h0);
assign inst_RDCNTVH = (func_code_31_10 == `func_rdcntvh) & (inst[9:5] == 5'h0);

//csr
assign inst_CSRRD   = (func_code_31_24 == `func_csr) & (inst[9:5] == 5'b00000) ;
assign inst_CSRWR   = (func_code_31_24 == `func_csr) & (inst[9:5] == 5'b00001) ;
assign inst_CSRXCHG = (func_code_31_24 == `func_csr) & ~(inst_CSRRD | inst_CSRWR) ;

//exception
assign inst_SYSCALL = (func_code_31_15 == `func_syscall);
assign inst_BREAK   = (func_code_31_15 == `func_break);

//ertn
assign inst_ERTN    = (func_code_31_10 == `func_ertn);

//idle
assign inst_IDLE    = (func_code_31_15 == `func_idle);

//cpucfg
assign inst_CPUCFG  = (func_code_31_10 == `func_cpucfg);

//nop
assign inst_NOP     = (inst[31:0] == `func_nop) | inst_DBAR | inst_IBAR;// | inst[31:0] == 32'b0

//..................................................inst sign
wire [4:0] invtlb_op;
wire sign_R, sign_I, sign_B, sign_U, sign_M, sign_D, sign_CSR, sign_CNT, sign_TLB;

assign sign_R   = inst_ADD | inst_SUB | inst_SLL | inst_SRL | inst_SRA | inst_AND | inst_OR | inst_NOR | inst_XOR | inst_SLT | inst_SLTU | inst_SLLI | inst_SRLI | inst_SRAI | inst_SYSCALL | inst_BREAK;
assign sign_I   = inst_SLTUI | inst_SLTI | inst_XORI | inst_ORI | inst_ANDI | inst_ADDI | inst_STW | inst_STH | inst_STB | inst_LDW | inst_LDH | inst_LDB | inst_LDHU | inst_LDBU | inst_LLW | inst_SCW;
assign sign_B   = inst_JIRL | inst_BGEU |  inst_BLTU | inst_BGE | inst_BLT | inst_BNE | inst_BEQ |  inst_BL |inst_B;
assign sign_U   = inst_LU12I | inst_PCADDU12I;
assign sign_M   = inst_MUL | inst_MULH | inst_MULHU;
assign sign_D   = inst_DIV | inst_MOD | inst_DIVU | inst_MODU;
assign sign_CSR = inst_CSRRD | inst_CSRWR | inst_CSRXCHG;
assign sign_CNT = inst_RDCNTID | inst_RDCNTVL | inst_RDCNTVH;
assign sign_TLB = inst_TLBSRCH | inst_TLBRD | inst_TLBWR | inst_TLBFILL | (inst_INVTLB & (invtlb_op < 5'h7));

assign is_branch = sign_B | inst_B;

//..................................................exception

wire ex_SYS, ex_BRK, ex_INE;
wire inst_valid;
assign inst_valid = sign_R | sign_I | sign_B | sign_U | sign_M | sign_D | sign_CSR | sign_CNT | sign_TLB | inst_CACOP | inst_PRELD | 
                    inst_ERTN | inst_IDLE | inst_CPUCFG | inst_NOP | inst_SYSCALL | inst_BREAK;
assign ex_INE = ~inst_valid;
assign ex_SYS = inst_SYSCALL;
assign ex_BRK = inst_BREAK;

assign ex_sign = ex_sign_in | ex_SYS | ex_BRK | ex_INE;
assign ecode = ex_sign_in ? ecode_in :
               ex_SYS     ? 6'h0b    :
               ex_BRK     ? 6'h0c    :
               ex_INE     ? 6'h0d    : 6'b0;

//..................................................imm and offset

wire [11:0] extend_si12;
wire [4:0] extend_ui5;
wire [19:0] extend_si20;
wire [15:0] extend_offs_15_0;
wire [9:0] extend_offs_25_16;
wire [13:0] extend_si14;

//对于rj的索引，无rj的指令，rj为5’b0
assign o_rj_index_5 = (inst_RDCNTVH | inst_RDCNTVL | inst_BREAK | inst_SYSCALL |inst_CSRRD | inst_CSRWR |
                       inst_IDLE    | inst_LU12I   | inst_PCADDU12I | inst_DBAR | inst_IBAR |
                       inst_B       | inst_BL      ) ? 5'b0 :inst[9:5];

//对于rk的索引，指令中没有rk的位置，则这个rk为5‘b
assign o_rk_index_5 =( inst_RDCNTID | inst_RDCNTVH | inst_RDCNTVL | inst_BREAK | inst_SYSCALL | inst_SLLI| inst_SRLI | inst_SRAI |
                      inst_SLTI    | inst_SLTUI   | inst_ADDI    | inst_ANDI  | inst_ORI     | inst_XORI| inst_CSRRD| 
                      inst_CACOP   | inst_TLBSRCH | inst_TLBRD   | inst_TLBWR | inst_TLBFILL | inst_ERTN| inst_IDLE | op_lsu[3] | inst_PRELD |
                      inst_LU12I   | inst_PCADDU12I| inst_DBAR   | inst_IBAR  | inst_CPUCFG | b_insts[8:6] )?  5'b0 : 
                                                                        (op_lsu[4] && !op_lsu[3]) || b_insts[5:0]  || inst_CSRWR| inst_CSRXCHG   ?  inst[4:0] : inst[14:10];
                                                                        
assign o_rd_index_5 = (inst_BL ? 5'b00001 : 
                    inst_RDCNTID ? inst[9:5] : inst[4:0]);

assign extend_si12       = inst[21:10];
assign extend_ui5        = inst[14:10];
assign extend_si20       = inst[24: 5];
assign extend_offs_15_0  = inst[25:10];
assign extend_offs_25_16 = inst[ 9: 0];
assign extend_si14       = inst[23:10];

//..................................................grf_no_wen

// wire grf_no_wen;
assign grf_no_wen = inst_STW | inst_STH | inst_STB | inst_BEQ | inst_BGE | inst_BGEU | inst_BNE | inst_BLT | inst_BLTU | inst_B |
                    inst_SYSCALL | inst_BREAK | inst_ERTN | inst_IDLE | inst_CACOP | inst_PRELD | inst_TLBSRCH | inst_TLBRD | inst_TLBWR | inst_TLBFILL | inst_INVTLB;//不需要写寄存器的指令

//..................................................op_lsu

// wire [5:0] op_lsu;
assign op_lsu[5]   = inst_LLW | inst_SCW;                                                                                           //是否为原子访存
assign op_lsu[4]   = inst_STW | inst_STH | inst_STB | inst_LDW | inst_LDH | inst_LDB | inst_LDHU | inst_LDBU | inst_LLW | inst_SCW; //当前是否为访存指令
assign op_lsu[3]   = inst_LDW | inst_LDH | inst_LDB | inst_LDHU | inst_LDBU | inst_LLW;                                             //是否为Load
assign op_lsu[2]   = inst_LDH | inst_LDB;                                                                                           //有符号
assign op_lsu[1:0] = (inst_STW | inst_LDW | inst_LLW | inst_SCW)             ? 2'b11 :
                     (inst_STH | inst_LDH | inst_LDHU)                       ? 2'b10 : 2'b01;                                       //访存类型

//..................................................extend_sign

wire ui5, si12, ui12,si20, offs16, offs26, si14;
assign ui5    = inst_SLLI | inst_SRLI | inst_SRAI;
assign si12   = inst_ADDI | inst_SLTI | inst_SLTUI | inst_STW | inst_STH | inst_STB | inst_LDW | inst_LDH | inst_LDB | inst_LDHU | inst_LDBU | inst_CACOP | inst_PRELD;
assign ui12   = inst_ANDI | inst_ORI | inst_XORI;
assign si20   = inst_LU12I | inst_PCADDU12I;
assign offs16 = inst_BEQ | inst_BNE | inst_BLT | inst_BGE | inst_BLTU | inst_BGEU | inst_JIRL;
assign offs26 = inst_BL | inst_B;
assign si14   = inst_LLW | inst_SCW;

wire [6:0] extend_sign;
assign extend_sign = {ui5, si12, ui12, si20, offs16, offs26, si14};

//..................................................selcode

wire rj_rk = inst_ADD | inst_SUB | inst_SLL | inst_SRL | inst_SRA | inst_AND | inst_OR | inst_NOR | inst_XOR | inst_SLT | inst_SLTU | inst_MUL | inst_MULH | inst_MULHU | inst_DIV | inst_MOD | inst_DIVU | inst_MODU;
wire rj_imm = inst_ADDI | inst_SLLI | inst_SRLI | inst_SRAI | inst_ANDI | inst_ORI | inst_XORI | inst_SLTI | inst_SLTUI;
wire pc_imm = inst_PCADDU12I;
wire zero_imm = inst_LU12I;

// wire [3:0] selcode;
assign selcode = {zero_imm, pc_imm, rj_imm, rj_rk};

//..................................................alu_opcode

wire op_signed, op_mod, op_div, op_mulh, op_mul, op_sltu, op_slt, op_sra, op_srl, op_sll, op_sub, op_add, op_xor, op_nor, op_or, op_and;
assign op_and  = inst_AND  | inst_ANDI ;
assign op_or   = inst_OR   | inst_ORI  ;
assign op_nor  = inst_NOR              ;
assign op_xor  = inst_XOR  | inst_XORI ;
assign op_add  = inst_ADD  | inst_ADDI | inst_LU12I | inst_PCADDU12I;
assign op_sub  = inst_SUB               ;
assign op_sll  = inst_SLL  | inst_SLLI  ;
assign op_srl  = inst_SRL  | inst_SRLI  ;
assign op_sra  = inst_SRA  | inst_SRAI  ;
assign op_slt  = inst_SLT  | inst_SLTI  ;
assign op_sltu = inst_SLTU | inst_SLTUI ;

assign op_mul    = inst_MUL                                   ;
assign op_mulh   = inst_MULH | inst_MULHU                     ;
assign op_div    = inst_DIV  | inst_DIVU                      ;
assign op_mod    = inst_MOD  | inst_MODU                      ;
assign op_signed = inst_MUL  | inst_MULH | inst_DIV | inst_MOD;

assign b_insts = {inst_B, inst_BL, inst_JIRL, inst_BEQ, inst_BNE, inst_BLT, inst_BLTU, inst_BGE, inst_BGEU};

// wire [10:0] alu_opcode;
assign alu_opcode = {
                // op_signed, op_mod, op_div, op_mulh, op_mul, 
                op_sltu, op_slt, op_sra, op_srl, op_sll, op_sub, op_add, op_xor, op_nor, op_or, op_and};
assign div_opcode = {op_signed, op_mod, op_div};
assign mul_opcode = {op_signed, op_mulh, op_mul};

//..................................................cpucfg

//..................................................csr

wire [1:0] csr_sign;
assign csr_sign = inst_CSRRD   ? 2'b01 :
                  inst_CSRWR   ? 2'b10 :
                  inst_CSRXCHG ? 2'b11 : 2'b00;

wire [13:0] csr_index;
assign csr_index = inst[23:10];

assign csr_data = {csr_sign, csr_index};

//..................................................extend and grf_data

// wire [31:0] imm32, offs32;

extend ext(
    .i_si12     ( extend_si12       ),
    .i_ui5      ( extend_ui5        ),
    .i_si20     ( extend_si20       ),
    .i_offs16   ( extend_offs_15_0  ),
    .i_offs26   ( extend_offs_25_16 ),
    .i_si14     ( extend_si14       ),
    .i_sign     ( extend_sign       ),
  
    .o_imm32    ( imm32             ),
    .o_offs32   ( offs32            )
);

// //..................................................counter

wire [4:0] cnt_index;
assign cnt_index = inst_RDCNTID ? o_rj_index_5 : o_rd_index_5;

assign cnt_opcode = {inst_RDCNTID, inst_RDCNTVL, inst_RDCNTVH, cnt_index};

//..................................................tlb

wire tlb_we, tlb_fill, tlb_rd, tlb_srch, invtlb_en;
// wire [9:0] tlb_data;
assign tlb_we    = (inst_TLBWR | inst_TLBFILL);
assign tlb_fill  = inst_TLBFILL;
assign tlb_rd    = inst_TLBRD;
assign tlb_srch  = inst_TLBSRCH;
assign invtlb_en = inst_INVTLB ;
assign invtlb_op = inst[4:0];

assign tlb_data = {tlb_we, tlb_fill, tlb_rd, tlb_srch, invtlb_en, invtlb_op};

//..................................................stop sign

wire [5:0] rj_stop_sign, rk_stop_sign, rd_stop_sign, rd_stop_sign_w;
assign rj_stop_sign[5] = (rj_rk | rj_imm | inst_JIRL) & (o_rj_index_5 != 5'b0);
assign rk_stop_sign[5] = rj_rk & (o_rk_index_5 != 5'b0);
assign rd_stop_sign[5] = ((op_lsu[4] & ~op_lsu[3]) | inst_CSRXCHG | inst_CSRWR) & (o_rd_index_5 != 5'b0);//store  csrxchg csrwr情况
assign rd_stop_sign_w[5] = ~grf_no_wen;
assign rj_stop_sign[4:0] = o_rj_index_5;
assign rk_stop_sign[4:0] = o_rk_index_5;
assign rd_stop_sign[4:0] = o_rd_index_5;
assign rd_stop_sign_w[4:0] = inst_RDCNTID ? o_rj_index_5 : o_rd_index_5;

assign o_id_stop_sign_24 = {rj_stop_sign, rk_stop_sign, rd_stop_sign, rd_stop_sign_w};
assign o_id_tlbsrch_sign = inst_TLBSRCH;

// //..................................................to exe data

// wire B_sign;
// assign B_sign = inst_BEQ | inst_BNE | inst_BLT | inst_BGE | inst_BLTU | inst_BGEU;

assign fu_type = (op_lsu[4] | inst_CACOP | inst_PRELD | sign_TLB)   ? 2'b11 :   // 访存指令 + TLB指令 → LSU
            (op_mul | op_mulh)                                      ? 2'b01 :   // 乘法类 → 乘法器
            (op_div | op_mod)                                       ? 2'b10 :   // 除法/取模 → 除法器
                                                                      2'b00 ;   // 其余（含 NOP/CSR 等）→ ALU
    
endmodule