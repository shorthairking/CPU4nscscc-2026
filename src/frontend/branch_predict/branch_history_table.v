//存储10位历史模式
module branch_history_table(
    input wire          clk,
    input wire          rstn,
    //查询端口
    input wire [17:0]   i_index_18,
    output wire [19:0]  o_history_20,
    //更新端口
    input wire          i_update_en,
    input wire [8:0]    i_update_index_9,
    input wire [9:0]    i_update_history_10
);
    (* ram_style = "distributed" *) reg [9:0] history_table [0:511]; //512行10位历史记录
    reg [511:0] history_valid;

    //查询输出逻辑
    assign o_history_20[9:0] = history_valid[i_index_18[8:0]] ? history_table[i_index_18[8:0]] : 10'b0;
    assign o_history_20[19:10] = history_valid[i_index_18[17:9]] ? history_table[i_index_18[17:9]] : 10'b0;

    //更新逻辑
    integer i;
    always @(posedge clk) begin
        if(!rstn) begin
            history_valid <= 512'b0;
        end else begin
            if(i_update_en) begin
                history_valid[i_update_index_9] <= 1'b1;
                history_table[i_update_index_9] <= i_update_history_10;
            end
        end
    end


endmodule