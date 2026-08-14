module icache (
        input              clk,
        input              reset,
        // cache & cpu interface
        input              valid,
        input              op,
        // [NEED_MODIFY]index要变小，offset要变大？于此相关的都要改
        input      [  2:0] size,
        input      [  3:0] offset,
        input      [  7:0] index,
        input      [ 19:0] tag,
        input      [ 31:0] wdata,
        input      [  3:0] wstrb,
        // [MODIFY]
        // output     [ 31:0] rdata,
        output     [ 63:0] rdata,
        output             data_ok,
        output             addr_ok,
        input              uncache_en,
        input              cacop_en,
        input      [  1:0] cacop_type,
        // [NEED_MODIFY] 这里也是一样
        input      [  3:0] cacop_offset,
        input      [  7:0] cacop_index,
        input      [ 19:0] cacop_tag,
        input              tlb_excp_cancel_req,
        output             icache_unbusy,
        // AXI interface
        output             rd_req,
        output     [  2:0] rd_type,
        output     [ 31:0] rd_addr,
        input              rd_rdy,
        input              ret_valid,
        input              ret_last,
        input      [ 31:0] ret_data,
        output reg         wr_req,
        output     [  2:0] wr_type,
        output     [ 31:0] wr_addr,
        output     [  3:0] wr_wstrb,
        output     [127:0] wr_data,
        input              wr_rdy,
        // to per
        output             cache_miss
    );
    // State machine
    parameter IDLE = 3'b000;
    parameter LOOKUP = 3'b001;
    parameter REPLACE = 3'b011;
    parameter REFILL = 3'b100;

    reg [2:0] m_state;
    wire mstate_is_IDLE;
    wire mstate_is_LOOKUP;
    wire mstate_is_REPLACE;
    wire mstate_is_REFILL;
    wire mstate_idle2look;
    wire mstate_look2look;

    assign mstate_is_IDLE = m_state == IDLE;
    assign mstate_is_LOOKUP = m_state == LOOKUP;
    assign mstate_is_REPLACE = m_state == REPLACE;
    assign mstate_is_REFILL = m_state == REFILL;
    assign mstate_idle2look = 1'b1;

    assign mstate_look2look = cache_hit;

    genvar i, j;

    // [MODIFY] 此处应该在cpu_top中修改，不过为了方便测试先在这里修改，到时候直接改为以下即可
    // wire [6:0] icache_index = index;
    // wire [4:0] icache_offset = offset;
    // wire [6:0] icache_cacop_index = cacop_index;
    // wire [4:0] icache_cacop_offset = cacop_offset;
    wire [6:0] icache_index = index[7:1];
    wire [4:0] icache_offset = {index[0], offset[3:0]};
    wire [6:0] icache_cacop_index = cacop_index[7:1];
    wire [4:0] icache_cacop_offset = {cacop_index[0], cacop_offset[3:0]};

    // [MODIFY]
    // // cache table
    // reg [255:0] way0_valid;
    // reg [255:0] way1_valid;
    reg [127:0] way0_valid;
    reg [127:0] way1_valid;

    // input buf
    reg op_r;
    // [MODIFY]
    // reg [7:0] index_r;
    // reg [3:0] offset_r;
    reg [6:0] index_r;
    reg [4:0] offset_r;

    reg [19:0] tag_r;
    reg [2:0] size_r;
    reg [31:0] wdata_r;
    reg [3:0] wstrb_r;
    reg       uncache_en_r;

    // [MODIFY]
    // wire [3:0] real_offset;
    // wire [7:0] real_index;
    wire [4:0] real_offset;
    wire [6:0] real_index;

    wire [19:0] real_tag;

    // bank table control signals
    // [MODIFY]
    // wire [31:0] way_bank_rdata[1:0][3:0];
    wire [63:0] way_bank_rdata[1:0][3:0];

    // [MODIFY]
    // wire [3:0] way_bank_wea[1:0][3:0];
    wire [7:0] way_bank_wea[1:0][3:0];  // 一位只管一字节

    wire wr_match_bank[1:0][3:0];
    // [MODIFY]
    // wire [31:0] way_bank_wdata[1:0][3:0];
    wire [63:0] way_bank_wdata[1:0][3:0];

    // [MODIFY]
    // wire [7:0] way_bank_addr;
    wire [6:0] way_bank_addr;

    wire way_bank_ena;

    // plru modify
    // wire [1:0] rand_val;
    // [MODIFY]
    // reg [255:0] plru_tree;
    reg [127:0] plru_tree;

    wire replace_way;
    wire has_invalid_way;
    wire invalid_way;
    wire cacop_chose_way;

    // plru modify
    // wire rand_repl_way;
    wire plru_repl_way;

    // [MODIFY]
    // wire [31:0] write_in;
    wire [63:0] write_in;

    // tag & v
    wire way0_valid_rd;
    wire way1_valid_rd;

    // [MODIFY]
    // wire [7:0] tag_tab_addr;
    wire [6:0] tag_tab_addr;

    wire [1:0] way_tag_wea;
    wire [1:0] way_tag_ena;
    wire [19:0] way0_tag_rd;
    wire [19:0] way1_tag_rd;
    wire [19:0] tag_tab_wdata;

    // cache hit judgment
    wire way0_hit;
    wire way1_hit;
    wire cache_hit;
    wire [1:0] way_hit;

    assign way0_hit = way0_valid_rd && (real_tag == way0_tag_rd);
    assign way1_hit = way1_valid_rd && (real_tag == way1_tag_rd);
    assign cache_hit = (way0_hit || way1_hit) && !(uncache_en || cacop_mode0 || cacop_mode1 || cacop_mode2);
    assign way_hit = {way1_hit, way0_hit};

    // [MODIFY]
    // assign data_ok = ((mstate_is_LOOKUP && (cache_hit || tlb_excp_cancel_req)) ||
    //        (mstate_is_REFILL && (ret_valid && (offset_r[3:2] == miss_buf_ret_num || uncache_en_r)))) && !cacop_en_r;
    assign data_ok = ((mstate_is_LOOKUP && (cache_hit || tlb_excp_cancel_req)) ||
           (mstate_is_REFILL && (ret_valid && ((~uncache_en_r && (offset_r[4:3] == miss_buf_ret_num[2:1]) && miss_buf_ret_num[0]) || (uncache_en_r && miss_buf_ret_num == 3'b001))))) && !cacop_en_r;
    assign addr_ok = (mstate_is_IDLE && mstate_idle2look) || (mstate_is_LOOKUP && mstate_look2look) && !cacop_en;

    // miss buffer
    reg [1:0] miss_buf_replace_way;

    // [MODIFY]
    // reg [1:0] miss_buf_ret_num;
    reg [2:0] miss_buf_ret_num;

    // cacop
    wire req_inst_valid;
    reg [1:0] cacop_type_r;
    reg       cacop_en_r;
    wire      cacop_mode0;
    wire      cacop_mode1;
    wire      cacop_mode2;
    wire      cacop_mode2_hit;

    reg       lookup_hit_r;

    always @(posedge clk) begin
        if(reset) begin
            lookup_hit_r <= 0;
        end
        else if (cacop_mode2 && mstate_is_LOOKUP) begin
            lookup_hit_r <= {way1_hit, way0_hit};
        end
    end

    assign req_inst_valid = valid || cacop_en;

    assign cacop_mode0 = cacop_en_r && (cacop_type_r == 2'b00);
    assign cacop_mode1 = cacop_en_r && (cacop_type_r == 2'b01);
    assign cacop_mode2 = cacop_en_r && (cacop_type_r == 2'b10);
    assign cacop_mode2_hit = cacop_mode2 && |lookup_hit_r;

    // [MODIFY]
    // assign real_offset = cacop_en ? cacop_offset : offset;
    // assign real_index = cacop_en ? cacop_index : index;
    assign real_offset = cacop_en ? cacop_offset : icache_offset;
    assign real_index = cacop_en ? cacop_index : icache_index;

    assign real_tag = cacop_en_r ? cacop_tag : tag;

    // State machine transition logic
    always @(posedge clk) begin
        if (reset) begin
            op_r <= 0;
            index_r <= 0;
            offset_r <= 0;
            tag_r <= 0;
            size_r <= 0;
            wdata_r <= 0;
            wstrb_r <= 0;
            uncache_en_r <= 0;

            cacop_en_r <= 0;
            cacop_type_r <= 0;

            miss_buf_replace_way <= 0;

            wr_req <= 0;

            plru_tree <= 0;  // plru modify
            miss_buf_ret_num <= 0;  // sim_modify

            m_state <= IDLE;
        end
        else begin
            // plru modify
            if (mstate_is_LOOKUP && cache_hit && !tlb_excp_cancel_req) begin
                if (way0_hit) begin
                    plru_tree[index_r] <= 1'b1;
                end else if (way1_hit) begin
                    plru_tree[index_r] <= 1'b0;
                end
            end

            case (m_state)
                IDLE: begin
                    if (req_inst_valid && mstate_idle2look) begin
                        op_r <= op;
                        index_r <= real_index;
                        offset_r <= real_offset;
                        size_r <= size;
                        wdata_r <= wdata;
                        wstrb_r <= wstrb;

                        cacop_en_r <= cacop_en;
                        cacop_type_r <= cacop_type;

                        m_state <= LOOKUP;
                    end
                    else
                        m_state <= IDLE;
                end
                LOOKUP: begin
                    if(req_inst_valid && mstate_look2look) begin
                        op_r <= op;
                        index_r <= real_index;
                        offset_r <= real_offset;
                        size_r <= size;
                        wdata_r <= wdata;
                        wstrb_r <= wstrb;
                        cacop_en_r <= cacop_en;
                        cacop_type_r <= cacop_type;

                        m_state <= LOOKUP;
                    end
                    else if (tlb_excp_cancel_req) begin
                        m_state <= IDLE;
                    end
                    else if (!cache_hit) begin
                        miss_buf_replace_way <= replace_way ? 2'b10 : 2'b01;
                        tag_r <= real_tag;
                        uncache_en_r <= uncache_en && !cacop_en_r;
                        m_state <= REPLACE;
                    end
                    else
                        m_state <= IDLE;
                end
                REPLACE: begin
                    if (rd_rdy) begin
                        m_state <= REFILL;
                        // [MODIFY]
                        // miss_buf_ret_num <= 2'b00;
                        miss_buf_ret_num <= 3'b000;
                    end
                    else
                        m_state <= REPLACE;
                end
                REFILL: begin
                    if (ret_valid && ret_last || cacop_en_r) begin
                        m_state <= IDLE;
                    end
                    else if(ret_valid) begin
                        miss_buf_ret_num <= miss_buf_ret_num + 1;
                    end
                end
                default:
                    m_state <= m_state;
            endcase
        end
    end

    assign icache_unbusy = mstate_is_IDLE;

    // [MODIFY]
    // assign way_bank_addr = {8{addr_ok}}  & real_index |
    //                         {8{!addr_ok}} & index_r ;
    assign way_bank_addr = {7{addr_ok}}  & real_index |
                            {7{!addr_ok}} & index_r ;

    assign way0_valid_rd = way0_valid[index_r];
    assign way1_valid_rd = way1_valid[index_r];
    assign tag_tab_addr  = mstate_is_REFILL ? index_r : real_index;

    // [MODIFY]
    // // Select data
    // wire [127:0] way_data[1:0];
    // wire [31:0] way_data_hit[1:0];
    // wire [31:0] fina_data;
    wire [255:0] way_data[1:0];
    wire [63:0] way_data_hit[1:0];
    wire [63:0] fina_data;

    generate
        for (i = 0; i < 2; i = i + 1) begin : data_select
            assign way_data[i] = {
                       way_bank_rdata[i][3], way_bank_rdata[i][2], way_bank_rdata[i][1], way_bank_rdata[i][0]
                   };
            // [MODIFY]
            // assign way_data_hit[i] = way_data[i][offset_r[3:2]*32+:32];
            assign way_data_hit[i] = way_data[i][offset_r[4:3]*64+:64];
        end
    endgenerate
    // [MODIFY]
    // assign fina_data = ({32{way0_hit}} & way_data_hit[0]) | ({32{way1_hit}} & way_data_hit[1]);
    assign fina_data = ({64{way0_hit}} & way_data_hit[0]) | ({64{way1_hit}} & way_data_hit[1]);

    // [MODIFY]
    // assign rdata = {32{mstate_is_LOOKUP}} & fina_data |
    //        {32{mstate_is_REFILL}} & ret_data;
    assign rdata = ({64{mstate_is_LOOKUP}} & fina_data) |
               ({64{mstate_is_REFILL && !uncache_en_r}} & write_in) |
               ({64{mstate_is_REFILL && uncache_en_r}} & write_in);

    // MISS
    assign way_bank_ena = mstate_is_IDLE || mstate_is_LOOKUP || !(uncache_en_r || cacop_mode0);

    assign has_invalid_way = ~(way0_valid[index_r] & way1_valid[index_r]);
    assign invalid_way = way0_valid[index_r] ? 1'b1 : 0;
    assign cacop_chose_way = offset_r[0];

    // plru modify
    // assign rand_repl_way = has_invalid_way ? invalid_way : rand_val[0];
    // assign replace_way = (cacop_mode0 || cacop_mode1) && cacop_chose_way ||
    //                         cacop_mode2 && way1_hit||
    //                         !cacop_en_r && rand_repl_way;
    assign plru_repl_way = has_invalid_way ? invalid_way : plru_tree[index_r];
    assign replace_way = (cacop_mode0 || cacop_mode1) && cacop_chose_way ||
                            cacop_mode2 && way1_hit||
                            !cacop_en_r && plru_repl_way;

    // [MODIFY]
    reg [31:0] ret_data_high, ret_data_low;
    always @(posedge clk) begin
        if (reset) begin
            ret_data_high <= 0;
            ret_data_low <= 0;
        end
        else if (mstate_is_REFILL && ret_valid) begin
            if (miss_buf_ret_num[0]) begin
                ret_data_high <= ret_data;
            end
            else begin
                ret_data_low <= ret_data;
            end
        end
    end
    

    // [MODIFY]
    // assign write_in = ret_data;
    // assign write_in = {ret_data_high, ret_data_low};
    assign write_in = {ret_data, ret_data_low};  // 由于miss_buf_ret_num[0]为1时会直接写入，所以不能用ret_data_high，否则会有时序问题

    // AXI interface
    // [MODIFY]
    // assign rd_addr = uncache_en_r ? {tag_r, index_r, offset_r} : {tag_r, index_r, 4'b0};
    assign rd_addr = uncache_en_r ? {tag_r, index_r, offset_r} : {tag_r, index_r, 5'b0};

    assign rd_type = uncache_en_r ? size_r : 3'b100;

    assign rd_req = mstate_is_REPLACE && !(cacop_mode0 || cacop_mode1 || cacop_mode2);

    // REFILL
    generate
        for (i = 0; i < 2; i = i + 1) begin : way
            for (j = 0; j < 4; j = j + 1) begin : bank
                assign way_bank_wdata[i][j] = write_in;
                // [MODIFY]
                // assign way_bank_wea[i][j] = {4{mstate_is_REFILL && miss_buf_replace_way[i] && (miss_buf_ret_num == j[1:0] && ret_valid)}} & 4'hf;
                assign way_bank_wea[i][j] = {8{mstate_is_REFILL && miss_buf_replace_way[i] && (miss_buf_ret_num[2:1] == j[1:0] && miss_buf_ret_num[0] && ret_valid)}} & 8'hff;
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (reset) begin
            way0_valid <= 0;
            way1_valid <= 0;
        end
        if(mstate_is_REFILL && ret_valid && ret_last && !uncache_en_r && !cacop_en_r) begin
            way0_valid[index_r] <= miss_buf_replace_way[0] ? 1'b1 : way0_valid[index_r];
            way1_valid[index_r] <= miss_buf_replace_way[1] ? 1'b1 : way1_valid[index_r];
        end else if(mstate_is_REFILL && (cacop_mode0 || cacop_mode1 || cacop_mode2_hit)) begin
            way0_valid[index_r] <= miss_buf_replace_way[0] ? 1'b0 : way0_valid[index_r];
            way1_valid[index_r] <= miss_buf_replace_way[1] ? 1'b0 : way1_valid[index_r];
        end
    end

    assign tag_tab_wdata = cacop_mode0 ? 20'b0 : tag_r;
    assign way_tag_ena = {2{mstate_is_IDLE || mstate_is_LOOKUP || !uncache_en_r}};
    assign way_tag_wea = miss_buf_replace_way[1] ? {2{mstate_is_REFILL && ((ret_valid && ret_last) || cacop_mode0)}} & 2'b10 : {2{mstate_is_REFILL && ((ret_valid && ret_last) || cacop_mode0)}} & 2'b01;

    assign cache_miss = mstate_is_REFILL && ret_last && !(uncache_en_r || cacop_en_r);

    // plru modify
    // lfsr_8bit u_lfsr_8bit (
    //               .clk     (clk),
    //               .reset     (reset),
    //               .lfsr_out(rand_val)
    //           );

    generate
        for (i = 0; i < 2; i = i + 1) begin : data_way
            for (j = 0; j < 4; j = j + 1) begin : data_bank
                // [NEED_MODIFY]创建一个64位宽的bank
                // bank u (
                bank_64bit u (
                         .clka   (clk),
                         .addra  (way_bank_addr),
                         .douta  (way_bank_rdata[i][j]),
                         .dina   (way_bank_wdata[i][j]),
                         .ena    (way_bank_ena),
                         .wea    (way_bank_wea[i][j])
                     );
            end
        end
    endgenerate

    // only use half
    tag_tab way0_tag (
                .clka  (clk),
                .addra ({1'b0,tag_tab_addr}),
                .dina(tag_tab_wdata),
                .douta(way0_tag_rd),
                .ena  (way_tag_ena[0]),
                .wea  (way_tag_wea[0])
            );

    tag_tab way1_tag (
                .clka  (clk),
                .addra ({1'b0,tag_tab_addr}),
                .dina(tag_tab_wdata),
                .douta(way1_tag_rd),
                .ena  (way_tag_ena[1]),
                .wea  (way_tag_wea[1])
            );

endmodule