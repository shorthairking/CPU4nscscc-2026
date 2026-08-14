module dcache (
        input              clk,
        input              reset,
        // cache & cpu interface
        input              valid,
        input              op,
        input      [  2:0] size,
        input      [  3:0] offset,
        input      [  7:0] index,
        input      [ 19:0] tag,
        input      [ 31:0] wdata,
        input      [  3:0] wstrb,
        output     [ 31:0] rdata,
        output             data_ok,
        output             addr_ok,
        input              uncache_en,
        // tmp signals
        input              dcacop_op_en,
        input      [  1:0] cacop_op_mode,
        input      [  4:0] preld_hint,
        input              preld_en,
        input              tlb_excp_cancel_req,
        input              sc_cancel_req,
        output             dcache_empty,
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
        //to perf_counter
        output             cache_miss
    );
    // State machine
    parameter IDLE = 3'b000;
    parameter LOOKUP = 3'b001;
    parameter MISS = 3'b010;
    parameter REPLACE = 3'b011;
    parameter REFILL = 3'b100;

    parameter W_IDLE = 2'b00;
    parameter W_WRITE = 2'b01;

    reg [2:0] m_state;
    reg [1:0] w_state;
    wire mstate_is_IDLE;
    wire mstate_is_LOOKUP;
    wire mstate_is_MISS;
    wire mstate_is_REPLACE;
    wire mstate_is_REFILL;
    wire wstate_is_IDLE;
    wire wstate_is_WRITE;
    wire mstate_idle2look;
    wire mstate_look2look;

    assign mstate_is_IDLE = m_state == IDLE;
    assign mstate_is_LOOKUP = m_state == LOOKUP;
    assign mstate_is_MISS = m_state == MISS;
    assign mstate_is_REPLACE = m_state == REPLACE;
    assign mstate_is_REFILL = m_state == REFILL;
    assign wstate_is_IDLE = w_state == W_IDLE;
    assign wstate_is_WRITE = w_state == W_WRITE;
    assign mstate_idle2look = !(wstate_is_WRITE && ((write_buf_offset[3:2] == offset[3:2]) || dcacop_op_en));

    assign mstate_look2look = !(wstate_is_WRITE && ((write_buf_offset[3:2] == offset[3:2]) || dcacop_op_en)) &&
           !(op_r && !op && ((offset_r[3:2] == offset[3:2]) || dcacop_op_en)) && cache_hit;

    wire cancel_req = tlb_excp_cancel_req || sc_cancel_req;

    genvar i, j;

    // cache table
    reg  [255:0] way0_valid;
    reg  [255:0] way1_valid;
    reg  [255:0] way0_dirty;
    reg  [255:0] way1_dirty;

    // input buf
    reg          op_r;
    reg  [  7:0] index_r;
    reg  [  3:0] offset_r;
    reg  [ 19:0] tag_r;
    reg  [  2:0] size_r;
    reg  [ 31:0] wdata_r;
    reg  [  3:0] wstrb_r;
    reg          preld_r;

    reg          uncache_en_r;
    reg          uncache_wr_r;

    // bank table control signals
    wire [ 31:0] way_bank_rdata  [1:0][3:0];
    wire [  3:0] way_bank_wea    [1:0][3:0];
    wire         wr_match_bank   [1:0][3:0];
    wire [ 31:0] way_bank_wdata  [1:0][3:0];
    wire [  7:0] way_bank_addr   [1:0][3:0];
    wire         way_bank_ena;

    // [MODIFY1] 新增：二叉树PLRU状态寄存器（两路组相联，每个cache组(8bit index=256组)仅需1bit PLRU位）
    // PLRU位定义：0 = way0是最近未使用(LRU)，1 = way1是最近未使用(LRU)
    reg  [255:0] plru_tree; 

    wire [127:0] replace_data;
    wire [ 19:0] replace_tag;
    wire         replace_way;
    wire         replace_v;
    wire         way1_d;
    wire         way0_d;
    wire         replace_d;
    wire         has_invalid_way;
    wire         invalid_way;
    wire         cacop_chose_way;
    wire         plru_repl_way;    

    wire [ 31:0] write_in;

    wire         uncache_wr;

    // tag & v
    wire         way0_valid_rd;
    wire         way1_valid_rd;
    wire         way0_dirty_rd;
    wire         way1_dirty_rd;

    wire [  7:0] tag_tab_addr;
    wire [  1:0] way_tag_wea;
    wire [  1:0] way_tag_ena;
    wire [ 19:0] way0_tag_rd;
    wire [ 19:0] way1_tag_rd;
    wire [ 19:0] tag_tab_wdata;

    wire [31:0] refill_data;

    // cache hit judgment
    wire         way0_hit;
    wire         way1_hit;
    wire         cache_hit;
    wire [  1:0] way_hit;

    assign way0_hit = way0_valid_rd && (tag == way0_tag_rd);
    assign way1_hit = way1_valid_rd && (tag == way1_tag_rd);
    assign cache_hit = (way0_hit || way1_hit) && !(uncache_en || cacop_mode0 || cacop_mode1 || cacop_mode2);
    assign way_hit = {way1_hit, way0_hit};

    assign data_ok = ((mstate_is_LOOKUP && (cache_hit || op_r || cancel_req)) ||
           (mstate_is_REFILL && (!op_r && ret_valid && (offset_r[3:2] == miss_buf_ret_num || uncache_en_r)))) && !(cacop_en_r || preld_r);
    assign addr_ok = (mstate_is_IDLE && mstate_idle2look) || (mstate_is_LOOKUP && mstate_look2look);
    assign dcache_empty = mstate_is_IDLE;
    assign cache_miss = mstate_is_REFILL && ret_last && !(uncache_en_r || cacop_en_r || preld_r);

    // write buffer
    reg [31:0] write_buf_wr_data;
    reg [ 7:0] write_buf_index;
    reg [ 3:0] write_buf_offset;
    reg [ 1:0] write_buf_way_hit;
    reg [ 3:0] write_buf_wstrb;

    always @(posedge clk) begin
        if (reset) begin
            write_buf_wr_data <= 0;
            write_buf_index   <= 0;
            write_buf_offset  <= 0;
            write_buf_way_hit <= 0;
            write_buf_wstrb   <= 0;

            w_state <= W_IDLE;
        end
        else begin
            case (w_state)
                W_IDLE: begin
                    if (mstate_is_LOOKUP && cache_hit && op_r && !cancel_req) begin
                        w_state <= W_WRITE;

                        write_buf_wr_data <= wdata_r;
                        write_buf_index   <= index_r;
                        write_buf_offset  <= offset_r;
                        write_buf_wstrb   <= wstrb_r;
                        write_buf_way_hit <= way_hit;
                    end
                end
                W_WRITE: begin
                    if (mstate_is_LOOKUP && cache_hit && op_r && !cancel_req) begin
                        w_state <= W_WRITE;

                        write_buf_wr_data <= wdata_r;
                        write_buf_index   <= index_r;
                        write_buf_offset  <= offset_r;
                        write_buf_wstrb   <= wstrb_r;
                        write_buf_way_hit <= way_hit;
                    end
                    else begin
                        w_state <= W_IDLE;
                    end
                    
                end
            endcase
        end
    end

    wire request_uncache_en;
    assign request_uncache_en = uncache_en && !cacop_en_r;
    assign uncache_wr = request_uncache_en && op_r && !cacop_mode1 && !cacop_mode2_hit;

    // miss buffer
    reg [1:0] miss_buf_replace_way;
    reg [1:0] miss_buf_ret_num;

    // cacop
    wire req_inst_valid;
    reg [1:0] cacop_type_r;
    reg       cacop_en_r;
    wire      cacop_mode0;
    wire      cacop_mode1;
    wire      cacop_mode2;
    wire      cacop_mode2_hit;

    reg       cacop_mode2_hit_r;

    assign req_inst_valid = valid || dcacop_op_en || preld_en;

    assign cacop_mode0 = cacop_en_r && (cacop_type_r == 2'b00);
    assign cacop_mode1 = cacop_en_r && (cacop_type_r == 2'b01);
    assign cacop_mode2 = cacop_en_r && (cacop_type_r == 2'b10);
    assign cacop_mode2_hit = cacop_mode2 && (way0_hit || way1_hit);

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
            preld_r <= 0;
            uncache_en_r <= 0;
            uncache_wr_r <= 0;

            cacop_en_r <= 0;
            cacop_type_r <= 0;
            cacop_mode2_hit_r <= 0;

            miss_buf_replace_way <= 0;

            wr_req <= 0;

            plru_tree <= 256'b0;

            m_state <= IDLE;
        end
        else begin
            if (mstate_is_LOOKUP && cache_hit && !cancel_req) begin
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
                        index_r <= index;
                        offset_r <= offset;
                        size_r <= size;
                        wdata_r <= wdata;
                        wstrb_r <= wstrb;
                        preld_r <= preld_en;

                        cacop_en_r <= dcacop_op_en;
                        cacop_type_r <= cacop_op_mode;

                        m_state <= LOOKUP;
                    end
                    else
                        m_state <= IDLE;
                end
                LOOKUP: begin
                    if (req_inst_valid && mstate_look2look) begin
                        op_r <= op;
                        index_r <= index;
                        offset_r <= offset;
                        size_r <= size;
                        wdata_r <= wdata;
                        wstrb_r <= wstrb;
                        preld_r <= preld_en;

                        cacop_en_r <= dcacop_op_en;
                        cacop_type_r <= cacop_op_mode;

                        m_state <= LOOKUP;
                    end
                    else if(cancel_req) begin
                        m_state <= IDLE;
                    end
                    else if (!cache_hit) begin
                        if (uncache_wr || ((replace_d && replace_v) && (!request_uncache_en || cacop_mode2_hit) && !cacop_mode0))
                            m_state <= MISS;
                        else
                            m_state <= REPLACE;
                        
                        miss_buf_replace_way <= replace_way ? 2'b10 : 2'b01;
                        tag_r <= tag;
                        uncache_en_r <= request_uncache_en;
                        uncache_wr_r <= uncache_wr;
                        cacop_mode2_hit_r <= cacop_mode2_hit;
                    end
                    else
                        m_state <= IDLE;
                end
                MISS: begin
                    if (wr_rdy) begin
                        wr_req  <= 1'b1;
                        m_state <= REPLACE;
                    end
                    else
                        m_state <= MISS;
                end
                REPLACE: begin
                    if (rd_rdy) begin
                        m_state <= REFILL;
                        miss_buf_ret_num <= 2'b00;
                    end
                    else
                        m_state <= REPLACE;

                    wr_req <= 1'b0;
                end
                REFILL: begin
                    if ((ret_valid && ret_last)|| !rd_req_buffer) begin
                        m_state <= IDLE;
                    end
                    else if (ret_valid) begin
                        miss_buf_ret_num <= miss_buf_ret_num + 1;
                    end
                end
                default:
                    m_state <= m_state;
            endcase
        end
    end

    assign way0_valid_rd = way0_valid[index_r];
    assign way1_valid_rd = way1_valid[index_r];
    assign way0_dirty_rd = way0_dirty[index_r];
    assign way1_dirty_rd = way1_dirty[index_r];
    assign tag_tab_addr  = {8{addr_ok}}  & index |
                            {8{!addr_ok}} & index_r;

    // Select data
    wire [127:0] way_data[1:0];
    wire [31:0] way_data_hit[1:0];
    wire [31:0] fina_data;

    generate
        for (i = 0; i < 2; i = i + 1) begin : data_select
            assign way_data[i] = {
                       way_bank_rdata[i][3], way_bank_rdata[i][2], way_bank_rdata[i][1], way_bank_rdata[i][0]
                   };
            assign way_data_hit[i] = way_data[i][offset_r[3:2]*32+:32];
        end
    endgenerate
    assign fina_data = ({32{way0_hit}} & way_data_hit[0]) | ({32{way1_hit}} & way_data_hit[1]);

    assign rdata = {32{mstate_is_LOOKUP}} & fina_data | {32{mstate_is_REFILL}} & ret_data;

    // MISS
    assign has_invalid_way = ~(way0_valid[index_r] & way1_valid[index_r]);
    assign invalid_way = way0_valid[index_r] ? 1'b1 : 0;
    assign cacop_chose_way = offset_r[0];

    assign plru_repl_way = has_invalid_way ? invalid_way : plru_tree[index_r];
    assign replace_way = ((cacop_mode0 || cacop_mode1) && cacop_chose_way) ||
                        (cacop_mode2 && way1_hit) || // select way hit
                        !cacop_en_r && plru_repl_way;

    assign replace_v = replace_way ? way1_valid[index_r] : way0_valid[index_r];

    assign way1_d = way1_dirty[index_r] || write_buf_way_hit[1] && wstate_is_WRITE && (write_buf_index == index_r);
    assign way0_d = way0_dirty[index_r] || write_buf_way_hit[0] && wstate_is_WRITE && (write_buf_index == index_r);
    assign replace_d = replace_way ? way1_d : way0_d;
    assign replace_tag = miss_buf_replace_way[1] ? way1_tag_rd : way0_tag_rd;

    assign replace_data = miss_buf_replace_way[1] ? way_data[1] : way_data[0];

    assign write_in = {
               wstrb_r[3] ? wdata_r[31:24] : ret_data[31:24],
               wstrb_r[2] ? wdata_r[23:16] : ret_data[23:16],
               wstrb_r[1] ? wdata_r[15:8] : ret_data[15:8],
               wstrb_r[0] ? wdata_r[7:0] : ret_data[7:0]
           };

    assign wr_wstrb = uncache_wr_r ? wstrb_r : 4'hf;

    // memory interface
    assign rd_addr = uncache_en_r ? {tag_r, index_r, offset_r} : {tag_r, index_r, 4'b0};
    assign rd_type = uncache_en_r ? size_r : 3'b100;
    assign wr_addr = uncache_wr_r ? {tag_r, index_r, offset_r} : {replace_tag, index_r, 4'b0};
    assign wr_type = uncache_wr_r ? size_r : 3'b100;
    assign wr_data = uncache_wr_r ? {96'b0, wdata_r} : replace_data;

    assign rd_req = mstate_is_REPLACE && !(cacop_mode0 || cacop_mode1 || cacop_mode2 || uncache_wr_r);

    // REFILL
    assign way_bank_ena = mstate_is_IDLE || mstate_is_LOOKUP || !(uncache_en_r || cacop_mode0);
    assign refill_data = (op_r && (offset_r[3:2] == miss_buf_ret_num)) ? write_in : ret_data; 
    generate
        for (i = 0; i < 2; i = i + 1) begin : way
            for (j = 0; j < 4; j = j + 1) begin : bank
                assign wr_match_bank[i][j] = wstate_is_WRITE && write_buf_way_hit[i] && (write_buf_offset[3:2] == j[1:0]);
                // select matched bank by write buffer
                assign way_bank_addr[i][j] = wr_match_bank[i][j] ? write_buf_index : {8{addr_ok}}  & index |
                                            {8{!addr_ok}} & index_r;

                assign way_bank_wdata[i][j] = {32{wstate_is_WRITE}}  & write_buf_wr_data |
                                     {32{mstate_is_REFILL}} & refill_data;
                
                assign way_bank_wea[i][j] = {4{wr_match_bank[i][j]}} & write_buf_wstrb |
                       {4{mstate_is_REFILL && miss_buf_replace_way[i] && (miss_buf_ret_num == j[1:0]) && ret_valid}} & 4'hf;
            end
        end
    endgenerate

    reg rd_req_buffer;
    always @(posedge clk) begin
        if (reset) begin
            rd_req_buffer <= 1'b0;
        end
        else if (rd_req) begin
            rd_req_buffer <= 1'b1;
        end
        else if (mstate_is_REFILL && (ret_valid && ret_last)) begin
            rd_req_buffer <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (reset) begin    // [MODIFY]
            way0_valid <= 256'b0;
            way1_valid <= 256'b0;
        end
        if (mstate_is_REFILL && ret_valid && ret_last && !uncache_en_r && !cacop_en_r) begin
            way0_valid[index_r] <= miss_buf_replace_way[0] ? 1'b1 : way0_valid[index_r];
            way1_valid[index_r] <= miss_buf_replace_way[1] ? 1'b1 : way1_valid[index_r];
        end else if(mstate_is_REFILL && (cacop_mode0 || cacop_mode1 || cacop_mode2_hit_r)) begin
            way0_valid[index_r] <= miss_buf_replace_way[0] ? 1'b0 : way0_valid[index_r];
            way1_valid[index_r] <= miss_buf_replace_way[1] ? 1'b0 : way1_valid[index_r];
        end
    end

    always @(posedge clk) begin
        if (reset) begin    // [MODIFY]
            way0_dirty <= 256'b0;
            way1_dirty <= 256'b0;
        end
        if (mstate_is_REFILL && ((ret_valid && ret_last) || !rd_req_buffer) && (!(uncache_en_r || cacop_mode0))) begin
            way0_dirty[index_r] <= miss_buf_replace_way[0] ? op_r : way0_dirty[index_r];
            way1_dirty[index_r] <= miss_buf_replace_way[1] ? op_r : way1_dirty[index_r];
        end
        else if (wstate_is_WRITE) begin
            if(write_buf_way_hit[1]) begin
                way1_dirty[write_buf_index] <= 1'b1;
            end
            else begin
                way0_dirty[write_buf_index] <= 1'b1;
            end
        end
    end

    assign tag_tab_wdata = cacop_mode0 ? 20'b0 : tag_r;
    assign way_tag_ena = {2{mstate_is_IDLE || mstate_is_LOOKUP || !uncache_en_r}};
    assign way_tag_wea = miss_buf_replace_way[1] ? {2{mstate_is_REFILL && ((ret_valid && ret_last) || cacop_mode0)}} & 2'b10 : {2{mstate_is_REFILL && ((ret_valid && ret_last) || cacop_mode0)}} & 2'b01;

    generate
        for (i = 0; i < 2; i = i + 1) begin : data_way
            for (j = 0; j < 4; j = j + 1) begin : data_bank
                bank u (
                         .clka   (clk),
                         .addra  (way_bank_addr[i][j]),
                         .douta(way_bank_rdata[i][j]),
                         .dina(way_bank_wdata[i][j]),
                         .ena   (way_bank_ena),
                         .wea   (way_bank_wea[i][j])
                     );
            end
        end
    endgenerate

    tag_tab way0_tag (
                .clka  (clk),
                .addra (tag_tab_addr),
                .dina(tag_tab_wdata),
                .douta(way0_tag_rd),
                .ena  (way_tag_ena[0]),
                .wea  (way_tag_wea[0])
            );

    tag_tab way1_tag (
                .clka  (clk),
                .addra (tag_tab_addr),
                .dina(tag_tab_wdata),
                .douta(way1_tag_rd),
                .ena  (way_tag_ena[1]),
                .wea  (way_tag_wea[1])
            );
endmodule
