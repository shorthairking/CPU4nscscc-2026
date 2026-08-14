`include "LoongArch.vh"

module if_stage(
    input  wire        clk,
    input  wire        rstn,

    input  wire        stop, //流水线暂停信号
    input  wire        clear,//流水线清空信号

    input  wire        i_Icache_valid    ,
    input  wire        i_addr_ok         ,
    input  wire        i_data_ok         ,

    //新增分支预测器接口
    input  wire        i_inst_valid      ,//用于判断靠前的inst是否要执行
    input  wire [31:0] i_pc_32           ,
    input  wire [63:0] i_inst_64         ,//双发修改，更改为64位
    input  wire [ 1:0] i_pred_isTaken_2  ,//来自pif，分支预测器预测是否跳转
    input  wire [63:0] i_pred_target_64  ,//来自pif，分支预测器预测的目标地址
    input  wire [ 6:0] i_ex_data_7       ,

    //删除从grf读寄存器的接口
    //中断
    input  wire        i_int             ,
    //送出到pre_if的跳转数据包
    output wire [64:0] o_if_stage_jump_65,
    //stop_controller数据包删除
    //送出到下个流水级数据包
    output wire        o_if_stage_valid   ,
    output wire [169:0] o_if_to_id_data_170//{inst0_valid, is_taken(2), target_pc(64), ex_sign(1), ecode(6), inst1(32), inst0(32), pc(32)}
    );
//..................................................

reg drop_sign;

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        drop_sign <= 1'b0;
    end else begin
        if(i_data_ok) begin
            drop_sign <= 1'b0;
        end else if(clear & i_Icache_valid) begin
            drop_sign <= 1'b1;
        end else if(stop) begin
            drop_sign <= drop_sign;
        end
    end
end

//..................................................pc
reg en_buffer, valid, inst0_valid, inst0_valid_buffer;
reg [ 1:0] pred_taken, pred_taken_buffer;
reg [31:0] pc, pc_buffer;
reg [63:0] inst, inst_buffer, pred_target, pred_target_buffer;
reg [ 6:0] ex_data, ex_data_buffer;

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        pc <= 32'h0;
        pred_taken <= 2'b0;
        pred_target <= 64'h0;
        inst0_valid <= 1'b0;
    end else begin
        if(clear) begin
            pc <= 32'h0;
            pred_taken <= 2'b0;
            pred_target <= 64'h0;
            inst0_valid <= 1'b0;
        end else if(stop) begin
            pc <= pc;
            pred_taken <= pred_taken;
            pred_target <= pred_target;
            inst0_valid <= inst0_valid;
        end else if(i_data_ok & ~drop_sign) begin
            pc <= i_pc_32;
            pred_taken <= i_pred_isTaken_2;
            pred_target <= i_pred_target_64;
            inst0_valid <= i_inst_valid;
        end else if(en_buffer) begin
            pc <= pc_buffer;
            pred_taken <= pred_taken_buffer;
            pred_target <= pred_target_buffer;
            inst0_valid <= inst0_valid_buffer;
        end else begin
            pc <= 32'h0;
            pred_taken <= 2'b0;
            pred_target <= 64'h0;
            inst0_valid <= 1'b0;
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        inst <= {`func_nop, `func_nop};
    end else begin
        if(clear) begin
            inst <= {`func_nop, `func_nop};
        end else if(stop) begin
            inst <= inst;
        end/*
        else if(jump_sign | rstn_sign_1) begin
            inst <= `func_nop;
        end*/
        else if(i_data_ok & ~drop_sign) begin
            inst <= i_inst_64;
        end
        else if(en_buffer) begin
            inst <= inst_buffer;
        end
        else begin
            inst <= `func_nop;
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        ex_data <= 7'h0;
    end else begin
        if(clear) begin
            ex_data <= 7'h0;
        end else if(stop) begin
            ex_data <= ex_data;
        end else if(i_data_ok & ~drop_sign) begin
            ex_data <= i_ex_data_7;
        end else if(en_buffer) begin
            ex_data <= ex_data_buffer;
        end else begin
            ex_data <= 7'h0;
        end
    end
end

wire ex_sign_in;
wire [5:0] ecode_in;
assign {ex_sign_in, ecode_in} = ex_data;

//..................................................buffer
always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        en_buffer <= 1'h0;
    end else begin
        if(clear) begin
            en_buffer <= 1'h0;
        end else if(stop) begin
            if(i_data_ok & ~drop_sign) begin
                en_buffer <= 1'b1;
            end else begin
                en_buffer <= en_buffer;
            end
        end else begin
            en_buffer <= 1'b0;
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        pc_buffer <= 32'h0;
        inst0_valid_buffer <= 1'b0;
        pred_taken_buffer <= 2'b0;
        pred_target_buffer <= 64'h0;
    end else begin
        if(clear) begin
            pc_buffer <= 32'h0;
            inst0_valid_buffer <= 1'b0;
            pred_taken_buffer <= 2'b0;
            pred_target_buffer <= 64'h0;
        end else if(stop) begin
            if(i_data_ok & ~drop_sign) begin
                pc_buffer <= i_pc_32;
                inst0_valid_buffer <= i_inst_valid;
                pred_taken_buffer <= i_pred_isTaken_2;
                pred_target_buffer <= i_pred_target_64;
            end else begin
                pc_buffer <= pc_buffer;
                inst0_valid_buffer <= inst0_valid_buffer;
                pred_taken_buffer <= pred_taken_buffer;
                pred_target_buffer <= pred_target_buffer;
            end
        end else begin
            pc_buffer <= 32'h0;
            inst0_valid_buffer <= 1'b0;
            pred_taken_buffer <= 2'b0;
            pred_target_buffer <= 64'h0;
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        inst_buffer <= 32'h0;
    end else begin
        if(clear) begin
            inst_buffer <= 32'h0;
        end
        else if(stop) begin
            if(i_data_ok & ~drop_sign) begin
                inst_buffer <= i_inst_64;
            end else begin
                inst_buffer <= inst_buffer;
            end
        end else begin
            inst_buffer <= 32'h0;
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        ex_data_buffer <= 7'h0;
    end else begin
        if(clear) begin
            ex_data_buffer <= 7'h0;
        end else if(stop) begin
            if(i_data_ok & ~drop_sign) begin
                ex_data_buffer <= i_ex_data_7;
            end else begin
                ex_data_buffer <= ex_data_buffer;
            end
        end else begin
            ex_data_buffer <= 7'h0;
        end
    end
end

//..................................................valid

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        valid <= 1'b0;
    end else begin
        if(clear) begin
            valid <= 1'b0;
        end else if(stop) begin
            valid <= valid;
        end else if(i_data_ok & ~drop_sign) begin
            valid <= 1'b1;
        end else if(en_buffer) begin
            valid <= 1'b1;
        end else begin
            valid <= 1'b0;
        end
    end
end

//..................................................指令跳转

wire inst_B0, inst_BL0, inst_JIRL0, inst_BEQ0, inst_BNE0, inst_BLT0, inst_BGE0, inst_BLTU0, inst_BGEU0;
wire inst_CALL0, inst_RET0, inst_MAYB0, inst_MUSTB0;
wire [1:0] inst_type0;

wire inst_B1, inst_BL1, inst_JIRL1, inst_BEQ1, inst_BNE1, inst_BLT1, inst_BGE1, inst_BLTU1, inst_BGEU1;
wire inst_CALL1, inst_RET1, inst_MAYB1, inst_MUSTB1;
wire [1:0] inst_type1;

assign inst_B0       = inst[31:26] == `func_b   ;
assign inst_BL0      = inst[31:26] == `func_bl  ;
assign inst_BEQ0     = inst[31:26] == `func_beq ;
assign inst_BNE0     = inst[31:26] == `func_bne ;
assign inst_BLT0     = inst[31:26] == `func_blt ;
assign inst_BGE0     = inst[31:26] == `func_bge ;
assign inst_BLTU0    = inst[31:26] == `func_bltu;
assign inst_BGEU0    = inst[31:26] == `func_bgeu;
assign inst_JIRL0    = inst[31:26] == `func_jirl;

assign inst_B1       = inst[63:58] == `func_b   ;
assign inst_BL1      = inst[63:58] == `func_bl  ;
assign inst_BEQ1     = inst[63:58] == `func_beq ;
assign inst_BNE1     = inst[63:58] == `func_bne ;
assign inst_BLT1     = inst[63:58] == `func_blt ;
assign inst_BGE1     = inst[63:58] == `func_bge ;
assign inst_BLTU1    = inst[63:58] == `func_bltu;
assign inst_BGEU1    = inst[63:58] == `func_bgeu;
assign inst_JIRL1    = inst[63:58] == `func_jirl;

assign inst_CALL0 = inst_JIRL0 & !((inst[9:5] == 5'b00001) & (inst[4:0] == 5'b00000) & (inst[25:10] == 16'b0)) |
                   inst_BL0;

assign inst_CALL1 = inst_JIRL1 & !((inst[41:37] == 5'b00001) & (inst[36:32] == 5'b00000) & (inst[57:42] == 16'b0)) |
                   inst_BL1;

assign inst_RET0 = inst_JIRL0 & (inst[9:5] == 5'b00001) & (inst[4:0] == 5'b00000) & (inst[25:10] == 16'b0);

assign inst_RET1 = inst_JIRL1 & (inst[41:37] == 5'b00001) & (inst[36:32] == 5'b00000) & (inst[57:42] == 16'b0);

assign inst_MAYB0 = inst_BEQ0 | inst_BNE0 | inst_BLT0 | inst_BGE0 | inst_BLTU0 | inst_BGEU0;

assign inst_MAYB1 = inst_BEQ1 | inst_BNE1 | inst_BLT1 | inst_BGE1 | inst_BLTU1 | inst_BGEU1;

assign inst_MUSTB0 = inst_B0;

assign inst_MUSTB1 = inst_B1;

assign inst_type0 = inst_CALL0 ? 2'b11 : (inst_RET0 ? 2'b10 : (inst_MUSTB0 ? 2'b01 : 2'b00));

assign inst_type1 = inst_CALL1 ? 2'b11 : (inst_RET1 ? 2'b10 : (inst_MUSTB1 ? 2'b01 : 2'b00));


wire [15:0] offs0_15_0 ;
wire [ 9:0] offs0_25_16;
wire [15:0] offs1_15_0 ;
wire [ 9:0] offs1_25_16;

assign offs0_15_0  = inst[25:10];
assign offs0_25_16 = inst[ 9: 0];
assign offs1_15_0  = inst[57:42];
assign offs1_25_16 = inst[41:32];


wire [31:0] jump0_addr, offs0_26_32, offs0_16_32;
wire [31:0] jump1_addr, offs1_26_32, offs1_16_32;

assign offs0_26_32 = offs0_25_16[9] ? {4'b1111, offs0_25_16, offs0_15_0, 2'b0} : {4'b0000, offs0_25_16, offs0_15_0, 2'b0};
assign offs0_16_32 = offs0_15_0[15] ? {14'b11111111111111, offs0_15_0, 2'b0}  : {14'b00000000000000, offs0_15_0, 2'b0};
assign offs1_26_32 = offs1_25_16[9] ? {4'b1111, offs1_25_16, offs1_15_0, 2'b0} : {4'b0000, offs1_25_16, offs1_15_0, 2'b0};
assign offs1_16_32 = offs1_15_0[15] ? {14'b11111111111111, offs1_15_0, 2'b0}  : {14'b00000000000000, offs1_15_0, 2'b0};

assign jump0_addr = (inst_B0 || inst_BL0) ?  offs0_26_32 + pc : offs0_16_32 + pc;
assign jump1_addr = (inst_B1 || inst_BL1) ?  offs1_26_32 + pc + 32'h4 : offs1_16_32 + pc + 32'h4;

wire jump0_en, target0_valid;
wire jump1_en, target1_valid;

assign jump0_en  = inst_MAYB0 | inst_MUSTB0 | inst_CALL0 | inst_RET0 | pred_taken[0];
assign jump1_en  = inst_MAYB1 | inst_MUSTB1 | inst_CALL1 | inst_RET1 | pred_taken[1];
assign target0_valid = inst_MUSTB0;
assign target1_valid = inst_MUSTB1;

wire [64:0] if_result;

//新增两条都是分支指令时入队逻辑

reg target_valid_buffer, jump_en_buffer, pred_taken_buffer0;
reg [31:0] jump_addr_buffer, jump_pc_buffer;
reg [1:0] inst_type_buffer;

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        target_valid_buffer <= 1'b0;
        jump_en_buffer <= 1'b0;
        jump_addr_buffer <= 32'h0;
        jump_pc_buffer <= 32'h0;
        inst_type_buffer <= 2'b0;
        pred_taken_buffer0 <= 1'b0;
    end else begin
        if(clear) begin
            target_valid_buffer <= 1'b0;
            jump_en_buffer <= 1'b0;
            jump_addr_buffer <= 32'h0;
            jump_pc_buffer <= 32'h0;
            inst_type_buffer <= 2'b0;
            pred_taken_buffer0 <= 1'b0;
        end else if(stop) begin
            target_valid_buffer <= target_valid_buffer;
            jump_en_buffer <= jump_en_buffer;
            jump_addr_buffer <= jump_addr_buffer;
            jump_pc_buffer <= jump_pc_buffer;
            inst_type_buffer <= inst_type_buffer;
            pred_taken_buffer0 <= pred_taken_buffer0;
        end else if(jump0_en & jump1_en) begin
            target_valid_buffer <= target1_valid;
            jump_en_buffer <= jump1_en;
            jump_addr_buffer <= pred_target[63:34];
            jump_pc_buffer <= pc + 32'h4;
            inst_type_buffer <= inst_type1;
            pred_taken_buffer0 <= pred_taken[1];
        end else begin
            target_valid_buffer <= 1'b0;
            jump_en_buffer <= 1'b0;
            jump_addr_buffer <= 32'h0;
            jump_pc_buffer <= 32'h0;
            inst_type_buffer <= 2'b0;
            pred_taken_buffer0 <= 1'b0;
        end
    end
end


assign if_result =  (jump0_en & inst0_valid) ? {jump0_en, pred_taken[0], target0_valid, inst_type0, pred_target[31:2], pc[31:2]}       :
                    (jump1_en)               ? {jump1_en, pred_taken[1], target1_valid, inst_type1, pred_target[63:34], pc[31:2]+ 30'h1} :
                    (jump_en_buffer)         ? {jump_en_buffer, pred_taken_buffer0, target_valid_buffer, inst_type_buffer, jump_addr_buffer[31:2], jump_pc_buffer[31:2]} :
                    {1'b0, 1'b0, target0_valid, inst_type0, pred_target[31:2], pc[31:2]};

assign o_if_stage_jump_65 = rstn ? if_result : 65'h0;
//..................................................exception

wire ex_sign;
wire [5:0] ecode;
assign ex_sign = ex_sign_in | i_int;
assign ecode = i_int ? 6'b0 : ecode_in;

//stop部分删除：不需要等待grf的数据，rj和rd不需要

//..................................................to id data
assign o_if_stage_valid = (~rstn | clear | stop | ~valid) ? 1'b0 : 1'b1;

// 2 + 64 + 7 + 32 + 32 + 32 = 169 
assign o_if_to_id_data_170 =
            ~rstn                                 ? {1'b0, 2'b0, 64'b0, 7'b0, `func_nop, `func_nop, 32'b0} :
            //(clear | stop | rstn_sign_2 | ~valid) ? {1'b0, 32'b0, 7'b0, `func_nop, 32'b0}        :
            (clear | stop | ~valid)               ? {1'b0, 2'b0, 64'b0, 7'b0, `func_nop, `func_nop, 32'b0} :
            ex_sign && (ecode_in != 6'b0)         ? {1'b1, 2'b0, 64'b0, ex_sign, ecode, `func_nop, `func_nop, pc} :
            //inst_B                              ? {7'b0, `func_nop, 32'b0}        : {ex_sign, ecode, inst, pc};
            //inst_B                              ? {ex_sign, ecode, `func_nop, pc} : 
                                                    {inst0_valid, pred_taken, pred_target, ex_sign, ecode, (inst0_valid ? inst : {inst[63:32], `func_nop}), pc};

//..................................................
endmodule