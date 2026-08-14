module pre_if_stage(
    input  wire        clk,
    input  wire        rstn,

    input  wire        stop,     
    //csr
    input  wire [31:0] csr_era_addr      ,
    input  wire [31:0] ex_entry          ,
    input  wire        crmd_da           ,
    input  wire        crmd_pg           ,
    input  wire [ 1:0] crmd_datf         ,
    input  wire [ 1:0] crmd_plv          ,
    input  wire        dmw0_plv0         ,
    input  wire        dmw0_plv3         ,
    input  wire [ 1:0] dmw0_mat          ,
    input  wire [ 2:0] dmw0_pseg         ,
    input  wire [ 2:0] dmw0_vseg         ,
    input  wire        dmw1_plv0         ,
    input  wire        dmw1_plv3         ,
    input  wire [ 1:0] dmw1_mat          ,
    input  wire [ 2:0] dmw1_pseg         ,
    input  wire [ 2:0] dmw1_vseg         ,
    //tlb
    output wire [18:0] tlb_s0_vppn       ,
    output wire        tlb_s0_va_odd     ,
    input  wire        tlb_s0_found      ,
    input  wire [19:0] tlb_s0_ppn        ,
    input  wire [ 5:0] tlb_s0_ps         ,
    input  wire [ 1:0] tlb_s0_plv        ,
    input  wire [ 1:0] tlb_s0_mat        ,
    input  wire        tlb_s0_d          ,
    input  wire        tlb_s0_v          ,
    //exception
    input  wire        i_ex              ,
    input  wire        i_ertn            ,
    input  wire        i_idle            ,//IDLE
    input  wire        i_int             ,
    //cacop
    input  wire        i_cacop_sign      ,
    input  wire [31:0] i_cacop_pc        ,
    input  wire        i_icache_cacop_en ,
    //Icache in
    input  wire        i_addr_ok         ,
    input  wire        i_data_ok         ,
    //predictor
    output wire        o_pred_en         ,//是否开启预测
    output wire [31:0] o_pred_pc_32      ,//需要预测的基准pc
    //修改分支预测接口宽度和对应逻辑
    input  wire [ 1:0] i_pred_taken_2    ,
    input  wire [63:0] i_pred_target_64  ,
    input  wire [ 5:0] i_pred_num_6      ,
    input  wire        i_pred_wrong          ,
    input  wire [31:0] i_pred_correctPC_32       ,
    //out
    output wire        o_idle_sign       ,
    output wire        o_pif_en          ,
    output wire        o_pif_pc_valid    ,//标记输出的两个PC中的第一个是否有效（是否需要被取指），如果无效则只需要取第二个PC
    output wire [ 5:0] o_pif_num_6       ,
    output wire [31:0] o_pc_32           ,//给icache的物理地址，8B对齐
    output wire [31:0] o_pc_to_if_32     ,//给if的逻辑地址，8B对齐
    output wire [ 1:0] o_pif_isTaken_2  ,
    output wire [63:0] o_pif_TakenPC_64  ,
    output wire [ 6:0] o_preif_ex_data_7 ,
    output wire        o_preif_uncache_en
);
    //当前修改目标为将其适应双发射逻辑，且适配后面的分支预测器
    //需要注意输出给下一级的PC需要为8B对齐
    //使用TLB进行地址转换时，因为地址为8B对齐，不会出现页内偏移跨页的情况，因此不需要考虑页内偏移跨页的特殊情况


    //..................................................
    reg         jump_buffer;
    reg  [5:0]  jump_num_buffer;
    reg  [31:0] pc, pc_jump_buffer;
    wire [31:0] pc_next;

    reg req_en;

    //..................................................nextpc to Icache

    wire jump_sign;
    wire [5:0] jump_num;
    wire [31:0] jump_addr, pc_32, p_pc_out_32;

    reg IDLE;

    //..................................................tlb

    wire dmw0_taken, dmw1_taken;

    //..................................................exception

    wire ex_PIF, ex_TLBR, ex_ADEF, ex_sign;
    wire [5:0] ecode;

    //..................................................pif en

    assign o_pif_en = i_idle  ? 1'b0                                        :
                      i_data_ok ? (~stop & rstn & ~IDLE & ~i_icache_cacop_en) :
                      req_en    ? (~stop & rstn & ~IDLE & ~i_icache_cacop_en) : 1'b0;

    //..................................................nextpc to Icache
    assign jump_sign = (i_addr_ok && o_pif_en && (pred_taken_delay != 2'b0) ) ? 1'b1 : 1'b0;
    assign jump_num = i_pred_num_6;
    assign jump_addr = pred_taken_delay[0] ? pred_target_delay[31:0] : pred_target_delay[63:32];

    assign pc_32 = i_ertn       ? csr_era_addr   :
                   i_ex         ? ex_entry       :
                   i_cacop_sign ? i_cacop_pc     : //数据来自wb,优先级高于分支预测
                   i_pred_wrong ? i_pred_correctPC_32:
                   jump_buffer  ? pc_jump_buffer : pc;

    assign o_pif_isTaken_2 = pred_taken_delay;

    assign o_pif_TakenPC_64 = pred_target_delay;

    assign pc_next = (pred_taken_delay == 2'b0) ? (pc_32 + (pc_32[2] ? 32'h4 : 32'h8)) :
                     (pred_taken_delay[0])      ? pred_target_delay[31:0]             :  
                                                  pred_target_delay[63:32]; //双发取指情况下一次取2条指令

    //这里需要解释为什么要用pc_next作为预测器的基准PC
    //分支预测器为一周期预测，如果使用当前PC作为预测基准，下一PC一定会被发射
    //如果使用pc_next作为预测基准，就能少发射一条无用PC，减少流水线耦合损失
    assign o_pred_en = o_pif_en;
    assign o_pred_pc_32 = pc_next;

    assign p_pc_out_32 = crmd_da                         ? pc_32                          :
                         dmw0_taken                      ? {dmw0_pseg,pc_32[28:0]}        :
                         dmw1_taken                      ? {dmw1_pseg,pc_32[28:0]}        :
                         (crmd_pg && tlb_s0_ps == 6'h15) ? {tlb_s0_ppn[19:9],pc_32[20:0]} :
                         (crmd_pg && tlb_s0_ps == 6'h0c) ? {tlb_s0_ppn[19:0],pc_32[11:0]} :
                         32'b0;

    assign o_pc_32       = {p_pc_out_32[31:3], 3'b000}; //输出给icache的地址需要8B对齐，最低3位固定为0
    assign o_pif_pc_valid = ~pc_32[2]; //根据pc_32的第2位判断当前输出的PC是否为第一条指令的地址
    assign o_pif_num_6   = jump_buffer ? jump_num_buffer : i_pred_num_6;
    assign o_pc_to_if_32 = !ex_ADEF ? {pc_32[31:3], 3'b000} : pc_32; //8B对齐

    reg [1:0] pred_taken_delay;
    reg [63:0] pred_target_delay;
    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            pred_taken_delay <= 2'b0;
            pred_target_delay <= 64'h0;
        end
        else begin
            if(i_addr_ok & o_pif_en) begin
                pred_taken_delay <= i_pred_taken_2;
                pred_target_delay <= i_pred_target_64;
            end else if ((i_ex | i_ertn | i_cacop_sign | i_pred_wrong) & ~(i_addr_ok & o_pif_en)) begin
                pred_taken_delay <= 2'b0;
                pred_target_delay <= 64'b0;
            end
            else begin
                pred_taken_delay <= pred_taken_delay;
                pred_target_delay <= pred_target_delay;
            end
        end
    end

    //..................................................IDLE

    assign o_idle_sign = IDLE;

    //..................................................tlb

    assign tlb_s0_vppn   = pc_32[31:13];
    assign tlb_s0_va_odd = pc_32[12];

    assign dmw0_taken = crmd_pg & ((crmd_plv == 2'h3 & dmw0_plv3) | (crmd_plv == 2'h0 & dmw0_plv0)) & (pc_32[31:29] == dmw0_vseg);
    assign dmw1_taken = crmd_pg & ((crmd_plv == 2'h3 & dmw1_plv3) | (crmd_plv == 2'h0 & dmw1_plv0)) & (pc_32[31:29] == dmw1_vseg);

    assign ex_PIF  = tlb_s0_found && crmd_pg && !tlb_s0_v && !(dmw0_taken || dmw1_taken);
    assign ex_TLBR = (!tlb_s0_found && crmd_pg) && !(dmw0_taken || dmw1_taken);
    assign ex_ADEF = (pc_32[1:0] != 2'b00);
    assign ex_sign = ex_PIF | ex_TLBR | ex_ADEF;

    assign ecode = ex_ADEF ? 6'h08 :
                ex_PIF  ? 6'h03 :
                ex_TLBR ? 6'h3f : 6'h0;

    assign o_preif_ex_data_7 = {ex_sign, ecode};

    //..................................................Icache

    assign o_preif_uncache_en = crmd_da      ? crmd_datf  == 2'b00 :
                                dmw0_taken   ? dmw0_mat   == 2'b00 :
                                dmw1_taken   ? dmw1_mat   == 2'b00 :
                                tlb_s0_found ? tlb_s0_mat == 2'b00 :
                                1'b0;

    //..................................................

    always @(posedge clk or negedge rstn) begin
        if (~rstn) begin
            pc <= 32'h1c000000;
        end else begin
            if (i_ertn) begin
                pc <= pc_next;
            end else if (stop | ~i_addr_ok) begin
                pc <= pc;
            end else if (i_addr_ok & o_pif_en) begin
                pc <= pc_next;
            end else begin
                pc <= pc;
            end
        end
    end

    //跳转缓冲逻辑：当发生跳转但地址尚未被接受时，设置跳转缓冲；当地址被接受时，清除跳转缓冲。
    always @(posedge clk or negedge rstn) begin
        if (~rstn) begin
            jump_buffer <= 1'h0;
            jump_num_buffer <= 6'h0;
        end else begin
            if ((i_ex | i_ertn | i_cacop_sign | i_pred_wrong) & ~(i_addr_ok & o_pif_en)) begin
                jump_buffer <= 1'h1;
                jump_num_buffer <= i_pred_num_6;
            end else if (jump_buffer & i_addr_ok & o_pif_en) begin
                jump_buffer <= 1'h0;
                jump_num_buffer <= 6'h0;
            end else begin
                jump_buffer <= jump_buffer;
                jump_num_buffer <= jump_num_buffer;
            end
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (~rstn) begin
            pc_jump_buffer <= 32'h0;
        end else begin
            if ((jump_sign | i_ex | i_ertn | i_cacop_sign | i_pred_wrong) & ~(i_addr_ok & o_pif_en)) begin
                if (i_ex) begin
                    pc_jump_buffer <= ex_entry;
                end else if (i_ertn) begin
                    pc_jump_buffer <= csr_era_addr;
                end else if (i_cacop_sign) begin
                    pc_jump_buffer <= i_cacop_pc;
                end else if (i_pred_wrong) begin
                    pc_jump_buffer <= i_pred_correctPC_32;
                end else if (jump_sign) begin
                    pc_jump_buffer <= i_pred_taken_2[0] ? i_pred_target_64[31:0] : i_pred_target_64[63:32];
                end
            end else if (jump_buffer & i_addr_ok & o_pif_en) begin
                pc_jump_buffer <= 32'h0;
            end else begin
                pc_jump_buffer <= pc_jump_buffer;
            end
        end
    end

    //..................................................pif en

    always @(posedge clk or negedge rstn) begin
        if (~rstn) begin
            req_en <= 1'b1;
        end else begin
            if (i_addr_ok & o_pif_en) begin
                req_en <= 1'b0;
            end else if (i_data_ok) begin
                req_en <= 1'b1;
            end else begin
                req_en <= req_en;
            end
        end
    end

    //..................................................IDLE

    always @(posedge clk or negedge rstn) begin
        if (~rstn) begin
            IDLE <= 1'b0;
        end else begin
            if (i_idle & ~i_int) begin
                IDLE <= 1'b1;
            end else if (i_int) begin
                IDLE <= 1'b0;
            end
        end
    end

    //predictor

endmodule