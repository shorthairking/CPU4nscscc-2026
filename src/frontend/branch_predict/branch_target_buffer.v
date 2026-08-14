module branch_target_buffer(
    input wire          clk,
    input wire          rstn,
    //查询端口
    input wire [17:0]   i_index_18,
    input wire [39:0]   i_tag_40,
    output wire [1:0]   o_hit_2,
    output wire [3:0]   o_type_4,
    output wire [59:0]  o_target_60,
    //更新端口
    input wire          i_update_en,
    input wire [8:0]    i_update_index_9,
    input wire [19:0]   i_update_tag_20,
    input wire [29:0]   i_update_target_30,
    input wire [1:0]    i_update_inst_type_2
);
    reg target_valid [0:511]; //有效位
    (* ram_style = "block" *) reg [29:0] target_table [0:511]; //512行32位目标地址
    (* ram_style = "block" *) reg [19:0] target_tag [0:511]; //标签位
    (* ram_style = "block" *) reg [1:0] inst_type [0:511]; //00: may b 01: must b/jirl 10: call 11: ret

    reg [19:0] tag0, tag1;
    reg [1:0] type0, type1;
    reg [29:0] target0, target1;
    reg [1:0] valid;

    //输出逻辑
    assign o_type_4 = {type1, type0};
    assign o_target_60 = {target1, target0};
    assign o_hit_2[0] = valid[0] && (tag0 == i_tag_40[19:0]);
    assign o_hit_2[1] = valid[1] && (tag1 == i_tag_40[39:20]);

    integer i;
    //新增：初始化三个block ram
    initial begin
        for(i = 0; i < 512; i = i + 1) begin
            target_valid[i] = 1'b0;
            target_table[i] = 30'b0;
            target_tag[i] = 20'b0;
            inst_type[i] = 2'b0;
        end
    end

    always @(posedge clk) begin
        if(!rstn) begin
            tag0 <= 20'b0;
            tag1 <= 20'b0;
            type0 <= 2'b0;
            type1 <= 2'b0;
            target0 <= 30'b0;
            target1 <= 30'b0;
            valid <= 2'b0;
            for(i = 0; i < 512; i = i + 1) begin
                target_valid[i] <= 1'b0;
            end
        end else begin
            tag0 <= target_tag[i_index_18[8:0]];
            target0 <= target_table[i_index_18[8:0]];
            type0 <= inst_type[i_index_18[8:0]];
            tag1 <= target_tag[i_index_18[17:9]];
            target1 <= target_table[i_index_18[17:9]];
            type1 <= inst_type[i_index_18[17:9]];
            valid <= {target_valid[i_index_18[17:9]], target_valid[i_index_18[8:0]]};
            //更新逻辑
            if(i_update_en) begin
                target_table[i_update_index_9] <= i_update_target_30;
                target_valid[i_update_index_9] <= 1'b1;
                target_tag[i_update_index_9] <= i_update_tag_20;
                inst_type[i_update_index_9] <= i_update_inst_type_2;
            end
        end
    end
endmodule