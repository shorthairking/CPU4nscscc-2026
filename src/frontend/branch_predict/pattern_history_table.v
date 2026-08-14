module pattern_history_table(
    input wire          clk,
    input wire          rstn,
    //查询接口
    input wire [17:0]   i_index_18,
    input wire [19:0]   i_history_20,
    output wire [3:0]   o_taken_4,
    output wire [17:0]  o_index_18,
    output wire [19:0]  o_history_20,
    //更新接口
    input wire          i_update_en,
    input wire [8:0]    i_update_index_9,
    input wire [9:0]    i_update_history_10,
    input wire          i_update_way,
    input wire [1:0]    i_update_pattern_2
   );
    //PHT给16K，一共占用32Kbit空间
    //PHT的地址由index和查询得到的bht异或得到

    wire [12:0] pht0_index, pht1_index;

    assign pht0_index = {i_index_18[8:6], i_index_18[5:0] ^ i_history_20[9:4], i_history_20[3:0]};
    assign pht1_index = {i_index_18[17:15], i_index_18[14:9] ^ i_history_20[19:14], i_history_20[13:10]};

    wire [12:0] update_addr;
    
    assign update_addr = {i_update_index_9[8:6], i_update_index_9[5:0] ^ i_update_history_10[9:4], i_update_history_10[3:0]};

    reg [19:0] history;
    reg [17:0] index;

    assign o_history_20 = history;
    assign o_index_18 = index;

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            history <= 20'b0;
            index <= 18'b0;
        end else begin
            history <= i_history_20;
            index <= i_index_18;
        end
    end

    pht_bank pht0(
        .clk(clk),
        .rstn(rstn),
        .raddr(pht0_index),
        .rdata(o_taken_4[1:0]),
        .we(i_update_en && !i_update_way),
        .waddr(update_addr),
        .wdata(i_update_pattern_2)
    );

    pht_bank pht1(
        .clk(clk),
        .rstn(rstn),
        .raddr(pht1_index),
        .rdata(o_taken_4[3:2]),
        .we(i_update_en && i_update_way),
        .waddr(update_addr),
        .wdata(i_update_pattern_2)
    );


endmodule

//每个PHT表占用16Kbit，分为两张表交叉存储，修改为读优先
module pht_bank(
    input wire          clk,
    input wire          rstn,
    input wire [12:0]   raddr,
    output reg [1:0]    rdata,
    input wire          we,
    input wire [12:0]   waddr,
    input wire [1:0]    wdata
);
    (* ram_style = "block" *) reg [1:0] pattern_table [0:8191]; //8192行2位饱和计数器

    integer i;
    initial begin
        for(i = 0; i < 8192; i = i + 1) begin
            pattern_table[i] <= 2'b01;
        end
    end

    always @(posedge clk) begin
        if (we)
            pattern_table[waddr] <= wdata;
    end

    always @(posedge clk) begin
        if (!rstn)
            rdata <= 2'b01;
        else
            rdata <= pattern_table[raddr];
    end
endmodule