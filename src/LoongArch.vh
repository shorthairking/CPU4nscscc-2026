`define func_add  17'b00000000000100000
`define func_sub  17'b00000000000100010
`define func_sll  17'b00000000000101110
`define func_srl  17'b00000000000101111
`define func_sra  17'b00000000000110000
`define func_and  17'b00000000000101001
`define func_or   17'b00000000000101010
`define func_nor  17'b00000000000101000
`define func_xor  17'b00000000000101011
`define func_slt  17'b00000000000100100
`define func_sltu 17'b00000000000100101
`define func_addi 10'b0000001010
`define func_slli 17'b00000000010000001
`define func_srli 17'b00000000010001001
`define func_srai 17'b00000000010010001

`define func_andi 10'b0000001101
`define func_ori 10'b0000001110
`define func_xori 10'b0000001111
`define func_slti 10'b0000001000
`define func_sltui 10'b0000001001

`define func_mul 17'b00000000000111000
`define func_mulh 17'b00000000000111001
`define func_mulhu 17'b00000000000111010

`define func_div 17'b00000000001000000
`define func_mod 17'b00000000001000001
`define func_divu 17'b00000000001000010
`define func_modu 17'b00000000001000011

`define func_b 6'b010100 
`define func_bl 6'b010101
`define func_beq 6'b010110 
`define func_bne 6'b010111
`define func_blt 6'b011000
`define func_bge 6'b011001
`define func_bltu 6'b011010
`define func_bgeu 6'b011011
`define func_jirl 6'b010011

`define func_ldw 10'b0010100010
`define func_ldh 10'b0010100001
`define func_ldb 10'b0010100000
`define func_ldhu 10'b0010101001
`define func_ldbu 10'b0010101000
`define func_stw 10'b0010100110
`define func_sth 10'b0010100101
`define func_stb 10'b0010100100
`define func_llw 8'b00100000 
`define func_scw 8'b00100001

`define func_lu12i 7'b0001010
`define func_pcaddu12i 7'b0001110

//cache
`define func_cacop 10'b0000011000
`define func_preld 10'b0010101011

//tlb
`define func_tlbsrch 32'b00000110010010000010100000000000
`define func_tlbrd   32'b00000110010010000010110000000000
`define func_tlbwr   32'b00000110010010000011000000000000
`define func_tlbfill 32'b00000110010010000011010000000000
`define func_invtlb  17'b00000110010010011

//counter
`define func_rdcntid 22'b0000000000000000011000
`define func_rdcntvl 22'b0000000000000000011000
`define func_rdcntvh 22'b0000000000000000011001

//csr
`define func_csr 8'b00000100

//exception
`define func_syscall 17'b00000000001010110
`define func_break 17'b00000000001010100
`define func_ertn 22'b0000011001001000001110

//idle
`define func_idle 17'b00000110010010001

//cpucfg
`define func_cpucfg 22'b0000000000000000011011

//nop
`define func_nop 32'b00000010100000000000000000000000

`define func_dbar 17'b00111000011100100
`define func_ibar 17'b00111000011100101