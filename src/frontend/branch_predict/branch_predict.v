//负责人：张晟
//目前分支指令的分类一共有这几种：may b /must b(不包含bl) /call(bl和jirl) / ret(jirl)/ 普通jirl

`include "LoongArch.vh"

module branch_predict(
    input wire          clk,
    input wire          rstn,
    input wire          clear,//流水线清空信号，来自提交阶段的异常/例外/ertn/cacop 
    //pif
    input wire          i_pc_valid, //标记低位PC对应的inst是否有效
    input wire          i_predict_en,//是否需要预测
    input wire [31:0]   i_nextPC_32,//8B对齐
    output wire         o_wrong_predict,//预测错误，需要pif返回指定pc
    output wire [31:0]  o_correct_pc_32,//预测错误需要跳转的pc
    //if
    input wire          i_if_en,
    input wire          i_if_isTaken,
    input wire [2:0]    i_if_inst_type_3,//{target_valid, inst_type(2)}
    input wire [59:0]   i_if_pc_60, //{target_30, pc_30}
    //retire(wb?)
    input wire          i_retire_en,
    input wire          i_retire_isTaken,
    input wire [31:0]   i_retire_target_32,
    //predictor out
    //输出接口拓宽，后续需要两条指令的预测结果
    output wire [1:0]   o_predict_taken_2,
    output wire [5:0]   o_predict_num_6,
    output wire [63:0]  o_predict_target_64
);
    integer i;
    wire [29:0] pc0, pc1;
    assign pc0 = i_nextPC_32[31:2];
    assign pc1 = i_nextPC_32[31:2] + 30'd1;

    //对pc做hash，获得bht/pht/btb的索引和tag
    wire [8:0] index0, index1;
    assign index0 = pc0[8:0] ^ pc0[17:9];
    assign index1 = pc1[8:0] ^ pc1[17:9];

    wire [19:0] tag0, tag1;
    assign tag0 = pc0[29:10];
    assign tag1 = pc1[29:10];

    //预测taken，由bht和pht组合共同完成
    wire [19:0] bht_history;
    branch_history_table bht(
        .clk(clk),
        .rstn(rstn),
        .i_index_18({index1, index0}),
        .o_history_20(bht_history),
        .i_update_en(pht_update_en),
        .i_update_index_9(pht_update_index),
        .i_update_history_10(pht_update_history)
    );

    wire [3:0] pht_taken;
    wire [19:0] pht_history;
    wire [17:0] pht_index;
    pattern_history_table pht(
        .clk(clk),
        .rstn(rstn),
        .i_index_18({index1, index0}),
        .i_history_20(bht_history),
        .o_taken_4(pht_taken),
        .o_history_20(pht_history),
        .o_index_18(pht_index),
        .i_update_en(pht_update_en),
        .i_update_index_9(pht_update_index),
        .i_update_history_10(pht_update_history),
        .i_update_way(pht_update_way),
        .i_update_pattern_2(pht_update_pattern)
    );

    //预测target，获得pc对应的inst种类
    wire [1:0] btb_hit;
    wire [3:0] btb_type;
    wire [59:0] btb_target;

    branch_target_buffer btb(
        .clk(clk),
        .rstn(rstn),
        .i_index_18({index1, index0}),
        .i_tag_40({tag1, tag0}),
        .o_hit_2(btb_hit),
        .o_type_4(btb_type),
        .o_target_60(btb_target),
        .i_update_en(btb_update_en),
        .i_update_index_9(btb_update_index),
        .i_update_tag_20(btb_update_tag),
        .i_update_target_30(btb_update_target),
        .i_update_inst_type_2(btb_update_inst_type)
    );

    //ras
    wire [29:0] ras_target, ras_push_pc;
    wire ras_recover_en, ras_target_ready;
    wire [3:0] ras_top_ptr;
    wire ras_push, ras_pop;

    assign ras_push = i_if_en && (i_if_inst_type_3[1:0] == 2'b10);
    assign ras_pop = i_if_en && (i_if_inst_type_3[1:0] == 2'b11);
    assign ras_push_pc = i_if_pc_60[29:0] + 30'd1;

    return_address_stack ras(
        .clk(clk),
        .rstn(rstn),
        .i_push_en(ras_push),
        .i_push_pc_30(ras_push_pc),
        .i_pop_en(ras_pop),
        .o_target_ready(ras_target_ready),
        .o_pop_target_30(ras_target),
        .o_stack_ptr_4(ras_top_ptr),
        .i_recover_en(ras_recover_en),
        .i_recover_ptr_4(ras_recover_ptr_4)
    );

    reg pc_valid;//用于寄存来自pif的信号，和输出对齐
    reg predict_en;
    reg [29:0] current_pc;
    reg [5:0] predict_num;//用于统计预测的指令数量，用于给指令编号

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            pc_valid <= 1'b0;
            predict_en <= 1'b0;
            current_pc <= 30'b0;
            predict_num <= 6'b0;
        end else begin
            pc_valid <= i_pc_valid;
            predict_en <= i_predict_en;
            current_pc <= i_nextPC_32[31:2];
            if(o_predict_taken_2 || correct_en) begin
                predict_num <= predict_num + 6'b1;
            end else begin
                predict_num <= predict_num;
            end
        end
    end

    //首先根据inst type选择模式
    //00: may b 01: must b / jirl(非call或ret) 10: call（包括bl和特定的jirl） 11: ret
    wire [1:0] is_taken;

    //如果是may b，根据pht预测，否则直接看btb是否命中
    assign is_taken[0] = (btb_type[1:0] == 2'b00) ? pht_taken[1] : btb_hit[0];
    assign is_taken[1] = (btb_type[3:2] == 2'b00) ? pht_taken[3] : btb_hit[1];

    //是否以低位PC为准进行跳转
    wire choose_way;
    wire [3:0] inst_type;

    //choose_way优先挑选靠前的taken，若无taken则选靠前的hit
    assign choose_way = pc_valid ? 1'b1 : ~(is_taken[0] || btb_hit[0]);
    //由于输出宽度修改的缘故，因此将inst_type拓宽
    assign inst_type = btb_type;

    //根据指令类型进行操作
    //may b：使用is_taken作为跳转方向，使用btb作为目标地址
    //must b/jirl：无论如何都跳转，使用btb作为目标地址
    //call：无论如何都跳转，使用btb作为目标地址，同时ras压栈
    //ret：无论如何都跳转，使用ras作为目标地址，同时ras弹栈

    //更新：将分支预测的结果输出到模块外，拓宽数据宽度
    wire [1:0] predict_taken;

    assign predict_taken[1] = (inst_type[3:2] == 2'b11) ? ras_target_ready : is_taken[1];
    assign predict_taken[0] = (inst_type[1:0] == 2'b11) ? ras_target_ready : is_taken[0];

    wire [59:0] predict_target;

    assign predict_target[59:30] = (inst_type[3:2] == 2'b11) ? ras_target : btb_target[59:30];
    assign predict_target[29:0] = (inst_type[1:0] == 2'b11) ? ras_target : btb_target[29:0];

    //checkpoint需要知道从btb查到的inst type(may b)是否有效
    wire taken_valid;
    assign taken_valid = btb_hit[choose_way] && predict_en;

    //输出
    assign o_predict_taken_2[0] = predict_taken[0] & predict_en & pc_valid;
    assign o_predict_taken_2[1] = predict_taken[1] & predict_en;
    assign o_predict_target_64 = {predict_target[59:30], 2'b00, predict_target[29:0], 2'b00} & {64{predict_en}};
    //当预测跳转时，指令编号需要+1
    assign o_predict_num_6 = predict_num + (((predict_taken && predict_en) || correct_en) ? 6'b1 : 6'b0);

    //修改为两级流水线进行信息比较并更新

    //删除way寄存逻辑，在实际操作中way来自pc
    
    //第一级流水用于比较指令类型和源PC，且对于b型指令比较目标地址
    //意识到一个问题，只要方向和地址没错，其他的可以在retire更新，对跳转无影响
    wire lv0_empty, lv0_full;
    reg [30:0] lv0_target [0:3];
    reg [30:0] lv0_pc [0:3];
    reg [1:0] lv0_inst_type [0:3];
    reg lv0_taken [0:3];
    reg [1:0] lv0_pattern [0:3];
    reg [9:0] lv0_history [0:3];
    reg [1:0] lv0_head, lv0_tail;

    assign lv0_empty = (lv0_head == lv0_tail);
    assign lv0_full = (lv0_head + 2'b1 == lv0_tail);

    always @(posedge clk or negedge rstn) begin
        if(!rstn || clear) begin
            lv0_head <= 2'b0;
            lv0_tail <= 2'b0;
            for(i = 0; i < 4; i = i + 1) begin
                lv0_pc[i] <= 30'b0;
                lv0_target[i] <= 30'b0;
                lv0_inst_type[i] <= 2'b0;
                lv0_taken[i] <= 1'b0;
                lv0_pattern[i] <= 2'b0;
                lv0_history[i] <= 10'b0;
            end
        end else begin
            //入队逻辑
            if(taken_valid && !lv0_full) begin
                lv0_taken[lv0_head] <= (o_predict_taken_2 != 2'b00) ? 1'b1 : 1'b0;
                lv0_inst_type[lv0_head] <= choose_way ? inst_type[3:2] : inst_type[1:0];
                lv0_target[lv0_head] <= choose_way ? predict_target[59:30] : predict_target[29:0];
                lv0_pattern[lv0_head] <= choose_way ? pht_taken[3:2] : pht_taken[1:0];
                lv0_history[lv0_head] <= choose_way ? pht_history[19:10] : pht_history[9:0];
                lv0_pc[lv0_head] <= current_pc;
                lv0_head <= lv0_head + 2'b1;
            end
            //出队逻辑
            //第二级的流水判断也需要考虑，当主流水线清空时若该级不清空会导致错位
            //第一级在判断方向一定错误且目标已知或者基准PC错误或者跳转目标一定错时才清空
            if(i_if_en || (i_retire_en && !lv1_empty)) begin
                if( //来自if的清空条件
                    (i_if_inst_type_3 == 3'b101 && !lv0_taken[lv0_tail]) || 
                    (lv0_pc[lv0_tail] != i_if_pc_60[29:0]) ||
                    (i_if_inst_type_3[2] && (lv0_target[lv0_tail] != i_if_pc_60[59:30]))
                ) begin
                    lv0_tail <= lv0_head;
                end else if(i_if_en) begin
                    //正常出队
                    lv0_tail <= lv0_tail + 2'b1;
                end
            end
        end
    end

    //第二级流水
    wire lv1_empty, lv1_full;
    reg [30:0] lv1_pc [0:15];
    reg [30:0] lv1_target [0:15];
    reg [1:0] lv1_inst_type [0:15];
    reg lv1_taken [0:15];
    reg [3:0] lv1_head, lv1_tail;

    assign lv1_empty = (lv1_head == lv1_tail);
    assign lv1_full = (lv1_head + 2'b1 == lv1_tail);

    always @(posedge clk or negedge rstn) begin
        if( !rstn || clear) begin
            lv1_head <= 4'b0;
            lv1_tail <= 4'b0;
            for(i = 0; i < 16; i = i + 1) begin
                lv1_pc[i] <= 30'b0;
                lv1_target[i] <= 30'b0;
                lv1_inst_type[i] <= 2'b0;
                lv1_taken[i] <= 1'b0;
            end
        end else begin
            //入队逻辑
            //根据第一级流水输出和if输出选择入队数据
            if(i_if_en && !lv1_full) begin
                lv1_inst_type[lv1_head] <= i_if_inst_type_3[1:0];
                lv1_pc[lv1_head] <= i_if_pc_60[29:0];
                lv1_target[lv1_head] <= i_if_pc_60[59:30];
                lv1_taken[lv1_head] <= i_if_isTaken;
                lv1_head <= lv1_head + 2'b1;
            end
            //出队逻辑
            //根据retire的输出进行比较获得出队的数据，填充到btb/pht/bht中
            if(i_retire_en && !lv1_empty) begin
                if(i_retire_isTaken == lv1_taken[lv1_tail] && ((i_retire_target_32[31:2] == lv1_target[lv1_tail]) || !i_retire_isTaken)) begin
                    lv1_tail <= lv1_tail + 2'b1;
                end else begin
                    lv1_tail <= lv1_head;
                end
            end
        end
    end

    //恢复逻辑
    //如果两个模块同时发送需要恢复跳转，retire的优先级高于if
    reg correct_en;
    reg [31:0] correct_pc;

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            correct_en <= 1'b0;
            correct_pc <= 32'b0;
        end else if(i_retire_en && ((i_retire_isTaken != lv1_taken[lv1_tail]) || (i_retire_isTaken & (i_retire_target_32[31:2] != lv1_target[lv1_tail])))) begin
            correct_en <= 1'b1;
            correct_pc <= i_retire_isTaken != lv1_taken[lv1_tail] ? (i_retire_isTaken ? i_retire_target_32 : {lv1_pc[lv1_tail], 2'b00} + 32'h4)
                        : i_retire_target_32;
        end else begin
            correct_en <= 1'b0;
            correct_pc <= 32'b0; 
        end
    end

    assign o_wrong_predict = correct_en;
    assign o_correct_pc_32 = correct_pc;

    //更新逻辑

    //btb：指令类型和目标地址都在里面，b型指令在if阶段更新，j型在retire更新
    //pht/bht：根据自己的推测结果更新，建立checkpoint，推测错了恢复
    //ras：根据call/ret分别进行压栈和弹栈，checkpoint恢复

    //btb更新逻辑
    //btb目前只有一路更新来源，来自比较的流水线输出，单个周期最多来一组数据
    reg btb_update_en;
    reg [8:0] btb_update_index;
    reg [19:0] btb_update_tag;
    reg [29:0] btb_update_target;
    reg [1:0] btb_update_inst_type;
    reg [62:0] update_btb_buffer [0:3];//{index, tag, target, inst_type}
    reg [1:0] update_btb_head, update_btb_tail;
    reg update_btb_empty;

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            btb_update_en <= 1'b0;
            btb_update_index <= 9'b0;
            btb_update_tag <= 20'b0;
            btb_update_target <= 30'b0;
            btb_update_inst_type <= 2'b0;
            update_btb_head <= 2'b0;
            update_btb_tail <= 2'b0;
            update_btb_empty <= 1'b1;
            for(i = 0; i < 4; i = i + 1) begin
                update_btb_buffer[i] <= 64'b0;
            end
        end else begin
            if(i_retire_en && !lv1_empty) begin
                btb_update_en <= 1'b1;
                btb_update_index <= lv1_pc[lv1_tail][8:0] ^ lv1_pc[lv1_tail][17:9];
                btb_update_tag <= lv1_pc[lv1_tail][29:10];
                btb_update_target <= i_retire_target_32[31:2];
                btb_update_inst_type <= lv1_inst_type[lv1_tail];
            end else begin
                btb_update_en <= 1'b0;
            end
        end
    end

    //pht/bht更新逻辑
    //和checkpoint一起进行管理，启动时机位于if得到指令类型后
    //checkpoint
    reg cp_empty;
    reg [25:0] cp_entry [0:7];//{index, history, way, pattern, top_ptr}
    reg [2:0] cp_head, cp_tail;

    //ras控制
    reg ras_recover;
    reg [3:0] ras_recover_ptr_4;

    assign ras_recover_en = ras_recover;

    //bht/pht更新控制，pht接口较全，bht共用
    reg pht_update_en, pht_update_way;
    reg [8:0] pht_update_index;
    reg [9:0] pht_update_history;
    reg [1:0] pht_update_pattern;

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            cp_head <= 3'b0;
            cp_tail <= 3'b0;
            cp_empty <= 1'b1;
            ras_recover <= 1'b0;
            ras_recover_ptr_4 <= 4'b0;
            for(i = 0; i < 8; i = i + 1) begin
                cp_entry[i] <= 26'b0;
            end
            pht_update_en <= 1'b0;
            pht_update_index <= 9'b0;
            pht_update_history <= 10'b0;
            pht_update_way <= 1'b0;
            pht_update_pattern <= 2'b0;
        end else begin
            if(i_retire_en && (lv1_inst_type[lv1_tail] == 2'b00) && (cp_entry[cp_tail][1] != i_retire_isTaken)) begin
                cp_tail <= cp_head;
                cp_empty <= 1'b1;
                ras_recover <= 1'b1;
                ras_recover_ptr_4 <= cp_entry[cp_tail][3:0];
                pht_update_en <= 1'b1;
                pht_update_index <= cp_entry[cp_tail][25:17];
                pht_update_history <= {cp_entry[cp_tail][17:7], i_retire_isTaken};
                pht_update_way <= cp_entry[cp_tail][6];
                pht_update_pattern <= i_retire_isTaken ? ((cp_entry[cp_tail][5:4] == 2'b11) ? 2'b11 : (cp_entry[cp_tail][5:4] + 2'b01))
                                                       : ((cp_entry[cp_tail][5:4] == 2'b00) ? 2'b00 : (cp_entry[cp_tail][5:4] - 2'b01));
            end else begin
                if(i_retire_en && (lv1_inst_type[lv1_tail] == 2'b00)) begin
                    cp_tail <= cp_tail + 3'b1;
                end
                if(i_if_en && i_if_inst_type_3[1:0] == 2'b00) begin
                    cp_entry[cp_head] <={
                        i_if_pc_60[8:0] ^ i_if_pc_60[17:9], //index
                        lv0_history[lv0_tail], //history
                        i_if_pc_60[0], //way
                        lv0_pattern[lv0_tail], //pattern
                        ras_top_ptr
                    };
                    cp_head <= cp_head + 3'b1;
                    pht_update_en <= 1'b1;
                    pht_update_index <= i_if_pc_60[8:0] ^ i_if_pc_60[17:9];
                    pht_update_history <= {lv0_history[lv0_tail][8:0], lv0_taken[lv0_tail]};
                    pht_update_way <= i_if_pc_60[0];
                    pht_update_pattern <= lv0_pattern[lv0_tail];
                    if(cp_empty) begin
                        cp_empty <= 1'b0;
                    end
                end else begin
                    pht_update_en <= 1'b0;
                end
                ras_recover <= 1'b0;
                ras_recover_ptr_4 <= 4'b0;
            end
        end
    end
endmodule
