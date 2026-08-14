// =============================================================================
// Module: lsq (Load-Store Queue)：
//   1. 单端口入队，顺序接收 store/cacop/uncache 请求（load和store的ready信号分离）
//   2. 退休仅需 retire_valid_i 脉冲，LSQ 内部自动记录最老未退休条目
//   3. Load 转发+合并：检查所有有效条目，从新到老逐字节提供最新数据，
//      并与 D-Cache 返回数据合并，输出最终 Load 结果（无需顶层处理）
//   4. cacop 冲突阻塞：若 load 地址与 SQ 中任一有效 cacop 条目同 cache‑line，
//      则阻塞该 load（通过 ls_stall_o），并将 load 地址暂存，冲突解除后自动重试
//   5. 冲刷：收到 flush_valid_i 后，自动从第一个未退休条目开始清除所有未退休条目（load 和 store）
//   6. 发送 D‑Cache：从 head 顺序弹出已退休条目，兼容普通 store、uncache、cacop
//   7. 无 free_cnt，使用 head/tail 判断满空
//   8. 为方便时序及逻辑，目前暂无写合并
// =============================================================================

`timescale 1ns / 1ps

module lsq #(
    // 想要拓展不能直接更改参数，有些地方用参数不好写故直接写死了
    parameter DEPTH       = 8,          // SQ 深度
    parameter ADDR_WIDTH  = 32,         // 物理地址宽度
    parameter DATA_WIDTH  = 32,         // 数据宽度
    parameter PTR_WIDTH   = 3           // 指针宽度 = log2(DEPTH)
) (
    input                            clk,
    input                            rstn,

    // ---------- SQ 入队接口 ----------
    input                            store_valid_i,          // 入队有效
    input   [ADDR_WIDTH-1:0]         store_paddr_i,          // 物理地址
    input   [DATA_WIDTH-1:0]         store_data_i,           // 写入数据
    input   [DATA_WIDTH/8-1:0]       store_mask_i,           // 字节掩码（4 位）
    input   [2:0]                    store_size_i,           // 写粒度编码（如字/半字/字节）
    input                            store_is_uncache_i,     // 是否为 uncache 类型
    input                            store_is_cacop_i,       // 是否为 cacop 指令
    input   [1:0]                    store_cacop_op_i,       // cacop 操作码
    output                           store_ready_o,          // 队列未满，可接收

    // ---------- Load 查询与合并 ----------
    input                            load_valid_i,
    input   [ADDR_WIDTH-1:0]         load_paddr_i,
    input   [2:0]                    load_size_i,           // Load 的 size（与 store_size_i 类似）
    input                            load_is_uncache_i,     // Load 是否为 uncache 访问
    input   [DATA_WIDTH-1:0]         dcache_rdata_i,        // 来自 D‑Cache 的读数据
    input                            dcache_data_ok_i,      // D‑Cache 读数据有效
    output  [DATA_WIDTH-1:0]         load_result_o,         // 最终 Load 数据
    output                           load_result_valid_o,   // load_result_o 有效
    output                           load_ready_o,          // load 可接收

    // ---------- 退休接口 ----------
    input                            retire_valid_i,         // 退休脉冲（高有效单周期）
    input                            can_sent_dcache_i,      // 是否可发送 D-Cache（因为sc指令可能失效）

    // ---------- 冲刷接口 ----------
    input                            flush_valid_i,          // 冲刷有效

    // ---------- 发送 D‑Cache 接口 ----------
    output reg                       dcache_valid_o,         // 发送请求有效
    output reg                       dcache_op_o,            // 操作类型（1 = store）
    output reg  [2:0]                dcache_size_o,          // 写粒度
    output reg  [3:0]                dcache_offset_o,        // 块内偏移
    output reg  [7:0]                dcache_index_o,         // 组索引
    output reg  [19:0]               dcache_tag_o,           // 标签
    output reg  [31:0]               dcache_wdata_o,         // 数据
    output reg  [3:0]                dcache_wstrb_o,         // 字节掩码
    output reg                       dcache_uncache_en_o,    // 是否 uncache 请求
    output reg                       dcache_cacop_en_o,      // 是否 cacop 请求
    output reg  [1:0]                dcache_cacop_mode_o,    // cacop 操作码
    input                            dcache_addr_ok_i,       // D‑Cache 可接收（握手信号）

    // ---------- 阻塞输出 ----------
    output                           ls_stall_o,             // 阻塞 LSU 发射（满或 cacop 冲突）

    // ---------- 状态输出 ----------
    output                           sq_full_o,              // 队列满
    output                           sq_empty_o              // 队列空
);

    localparam BYTE_WIDTH = DATA_WIDTH / 8;  // 字节掩码宽度（4）

    // SQ 存储阵列
    reg  [DEPTH-1:0]                 valid_r;        // 条目有效
    reg  [DEPTH-1:0]                 retired_r;      // 已退休
    reg  [DEPTH-1:0]                 can_sent_r;     // 是否可发送
    reg  [DEPTH-1:0]                 is_uncache_r;   // 是否为 uncache
    reg  [DEPTH-1:0]                 is_cacop_r;     // 是否为 cacop
    reg  [1:0]                       cacop_op_r   [0:DEPTH-1];  // cacop 操作码
    reg  [2:0]                       size_r       [0:DEPTH-1];  // 写粒度
    reg  [ADDR_WIDTH-1:0]            paddr_r      [0:DEPTH-1];  // 物理地址
    reg  [DATA_WIDTH-1:0]            data_r       [0:DEPTH-1];  // 数据
    reg  [BYTE_WIDTH-1:0]            mask_r       [0:DEPTH-1];  // 字节掩码

    // 队列指针与满空判断
    // head指向发送给dcache的条目，tail指向新条目将放入的地方，retire指向未退休的最老条目
    reg  [PTR_WIDTH-1:0] head, tail, retire;
    // wire sq_full  = (tail == head) && valid_r[head];    // 这个有bug，就是正好还剩一个有效会显示满了
    // wire sq_empty = (tail == head) && !valid_r[head];
    wire sq_full  = &valid_r;       // 队列满就是全有效
    wire sq_empty = ~|valid_r;      // 队列空就是不存在一个无效
    assign sq_full_o  = sq_full;
    assign sq_empty_o = sq_empty;
    assign store_ready_o = ~sq_full;
    

    // 用 busy + is_load 标志替代状态机实现连续发送（模拟流水线）
    reg  busy;                  // 正在发送请求（任何类型）
    reg  is_load;               // 当前发送的是否为 load（1 = load，0 = store/cacop）

    // Load 相关寄存器（相当于深度为1的 LQ ，因为目前不是非阻塞）
    reg load_wait_valid;    // 1 表示 load 正在等待 cacop 清除【注意是“正在”等待而非存在等待】
    reg load_valid_r;
    reg [2:0] load_size_r;
    reg [ADDR_WIDTH-1:0] load_paddr_r;
    reg load_is_uncache;
    assign load_ready_o = ~(load_valid_r || (eff_load_valid && cacop_conflict) || load_wait_valid);  // 只有当 LQ 中没有未完成的 load 且没有被 cacop 冲突阻塞时才接受新 load

    // 有效 load 地址
    wire [ADDR_WIDTH-1:0] eff_load_addr = load_valid_r ? load_paddr_r : load_paddr_i;
    wire eff_load_valid = load_valid_r | load_valid_i;

    // cacop 冲突检测
    // 检查是否有任何有效 cacop 条目与当前 load 地址同 cache-line
    wire [DEPTH-1:0] cacop_match;
    genvar gi;
    generate
        for (gi = 0; gi < DEPTH; gi = gi + 1) begin : gen_cacop_conflict
            assign cacop_match[gi] = valid_r[gi] && is_cacop_r[gi] &&
                                     (paddr_r[gi][ADDR_WIDTH-1:4] == eff_load_addr[ADDR_WIDTH-1:4]);
        end
    endgenerate
    wire cacop_conflict = |cacop_match;

    // 阻塞条件：队列满，或 load 有效且有 cacop 冲突，或 load 等待还没结束
    assign ls_stall_o = sq_full || (eff_load_valid && cacop_conflict) || load_wait_valid;

    // Load 转发逻辑（从尾向头扫描）
    integer li, bi, idx_fwd;
    reg  [DATA_WIDTH-1:0] fwd_data_comb;
    reg  [BYTE_WIDTH-1:0] fwd_mask_comb;
    // wire load_active = load_valid_r && !load_wait_valid;   // 说明load有效且没有等待，即load可以被发送
    // cacop冲突是组合逻辑检测，但是要在下一个周期才会拉高等待，但是有可能这一周期就发送了
    wire load_ready_to_send = load_valid_r && !load_wait_valid && !cacop_conflict;

     // 发送控制 
    wire head_valid_retired = valid_r[head] && retired_r[head];
    wire [PTR_WIDTH-1:0] head_next = (head == DEPTH-1) ? {PTR_WIDTH{1'b0}} : head + 1;
    wire next_valid_retired = valid_r[head_next] && retired_r[head_next];

    // 找出sq中与此次load地址相同的有效数据并合并
    always @(*) begin
        fwd_mask_comb = {BYTE_WIDTH{1'b0}};
        fwd_data_comb = {DATA_WIDTH{1'bx}};
        if (load_ready_to_send) begin
            // 从 tail-1 开始环形向 head 方向扫描（新 -> 老），这样覆盖完全部字节即可返回
            idx_fwd = (tail == 0) ? DEPTH-1 : tail - 1;
            for (li = 0; li < DEPTH; li = li + 1) begin
                // 字地址匹配（忽略低 2 位）
                if (valid_r[idx_fwd] &&
                    (paddr_r[idx_fwd][ADDR_WIDTH-1:2] == eff_load_addr[ADDR_WIDTH-1:2])) begin
                    // 逐字节填充尚未命中的字节
                    for (bi = 0; bi < BYTE_WIDTH; bi = bi + 1) begin
                        if (mask_r[idx_fwd][bi] && !fwd_mask_comb[bi]) begin
                            fwd_data_comb[8*bi +: 8] = data_r[idx_fwd][8*bi +: 8];
                            fwd_mask_comb[bi] = 1'b1;
                        end
                    end
                    // // 若全部字节已覆盖，提前退出循环
                    // if (fwd_mask_comb == {BYTE_WIDTH{1'b1}})
                    //     li = DEPTH;
                end
                // 指针环形递减
                idx_fwd = (idx_fwd == 0) ? DEPTH-1 : idx_fwd - 1;
            end
        end
    end

    // 由于dcache设计，uncache和tag需要延迟一个周期发送
    reg dcache_uncache_en;
    reg [19:0] dcache_tag;
    always @(posedge clk  or negedge rstn) begin 
        if (!rstn) begin 
            dcache_uncache_en_o <= 1'b0;
            dcache_tag_o        <= 20'b0;
        end
        else begin
            dcache_uncache_en_o <= dcache_uncache_en;
            dcache_tag_o        <= dcache_tag;
        end
    end
    
    wire [31:0] fwd_mask_32 = { {8{fwd_mask_comb[3]}}, {8{fwd_mask_comb[2]}},
                                {8{fwd_mask_comb[1]}}, {8{fwd_mask_comb[0]}} };
    // 最终合并：SQ 提供的字节用 fwd_data，其余用 D‑Cache 数据
    assign load_result_o = (fwd_data_comb & fwd_mask_32) |
                           (dcache_rdata_i & ~fwd_mask_32);
    // dcache返回load数据的过程中sq就已经查好了，因此dcache的data_ok则整体data_ok
    assign load_result_valid_o = load_ready_to_send && dcache_data_ok_i;

    // 时序逻辑：包含冲刷、退休、发送、入队、load寄存器管理
    integer i,  fidx, fcnt;
    integer retire_idx;

    always @(posedge clk  or negedge rstn) begin
        if (!rstn) begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                valid_r[i]      <= 1'b0;
                retired_r[i]    <= 1'b0;
                is_uncache_r[i] <= 1'b0;
                is_cacop_r[i]   <= 1'b0;
                cacop_op_r[i]   <= 2'b0;
                size_r[i]       <= 3'b0;
                can_sent_r[i]   <= 1'b0;
            end
            head          <= {PTR_WIDTH{1'b0}};
            tail          <= {PTR_WIDTH{1'b0}};
            retire        <= {PTR_WIDTH{1'b0}};
            dcache_valid_o <= 1'b0;
            load_wait_valid <= 1'b0;
            load_valid_r <= 1'b0;
            load_size_r <= 3'b0;
            load_paddr_r <= {ADDR_WIDTH{1'b0}};
            load_is_uncache <= 1'b0;
            busy <= 1'b0;
            is_load <= 1'b0;
            dcache_uncache_en <= 1'b0;
            dcache_tag <= 20'b0;
        end else begin
            // Load 等待寄存器更新（cacop 冲突管理）---------------------------------------
            // 当 load 到来且遇到 cacop 冲突，将阻塞流水线
            if (load_valid_i && cacop_conflict && !load_wait_valid) begin
                load_wait_valid <= 1'b1;    // 此处拉高即可阻塞流水线
            end
            // 冲突解除（cacop 已被发送或冲刷），可结束等待，ls_stall 即将拉低，
            // 下一周期组合逻辑自动用等待地址进行转发并输出结果。
            else if (load_wait_valid && !cacop_conflict) begin
                load_wait_valid <= 1'b0;    
            end

            // 冲刷处理（根据retire标定范围）---------------------------------------------
            if (flush_valid_i) begin    // 注意冲刷时load一定要被冲刷，留在LQ中的load都是没执行完的，因此rob提交（触发flush）的一定不可能是load之后的指令
                fidx = retire;
                for (fcnt = 0; fcnt < DEPTH; fcnt = fcnt + 1) begin
                    if (valid_r[fidx] && !retired_r[fidx]) begin    // 直接遍历一遍，涵盖了栈满情况
                        valid_r[fidx] <= 1'b0;
                    end
                    fidx = (fidx == DEPTH-1) ? {PTR_WIDTH{1'b0}} : fidx + 1;
                end
                tail = retire;  // 移动到第一个无效的条目

                load_valid_r <= 1'b0;    // 无条件冲刷load
                load_wait_valid <= 1'b0;
                
                busy <= 1'b0;
                is_load <= 1'b0;
                dcache_valid_o <= 1'b0;
            end

            // 退休------------------------------------------------------------------
            // if (retire_valid_i && !flush_valid_i) begin
            if (retire_valid_i) begin   // store指令被提交时触发冲刷代表这一条可以被提交，其后的都要被冲刷
                retire_idx = retire;
                if (valid_r[retire_idx]) begin  // 只要是有效的就可以退休
                    if(flush_valid_i)begin  // 当这一条指令不能被提交时不会拉高retire
                        valid_r[retire_idx] <= 1'b1;    // 让这一条指令不被冲刷
                    end
                    retired_r[retire_idx] <= 1'b1;                  // 标记为本周期退休
                    can_sent_r[retire_idx] <= can_sent_dcache_i;    // 同步写入是否允许发送
                    retire <= (retire == DEPTH-1) ? {PTR_WIDTH{1'b0}} : retire + 1;
                end
            end

            // 发送------------------------------------------------------------------
            if (!flush_valid_i) begin
                // 当前发送完成处理
                if (busy) begin
                    if (is_load) begin
                        // load 发送中
                        if (dcache_addr_ok_i) begin // 接收到了就可以拉低有效位了（还可能要等待数据）
                            dcache_valid_o <= 1'b0;
                        end
                        if (dcache_data_ok_i) begin // 数据接收到代表load指令完全结束
                            load_valid_r <= 1'b0;
                            if (head_valid_retired && dcache_addr_ok_i) begin   // 刚发完load只有可能再发load
                                // 不让发那就相当于是无效，反正写指令下一周期还是会检测到dcache的addr_ok，借这个方便统一无效化该条目
                                dcache_valid_o      <= can_sent_r[head];
                                dcache_op_o         <= 1'b1;
                                dcache_size_o       <= size_r[head];
                                dcache_offset_o     <= paddr_r[head][3:0];
                                dcache_index_o      <= paddr_r[head][11:4];
                                dcache_tag          <= paddr_r[head][31:12];
                                dcache_wdata_o      <= data_r[head];
                                dcache_wstrb_o      <= mask_r[head];
                                dcache_uncache_en   <= is_uncache_r[head];
                                dcache_cacop_en_o   <= is_cacop_r[head];
                                dcache_cacop_mode_o <= cacop_op_r[head];
                                busy      <= 1'b1;
                                is_load   <= 1'b0;
                            end
                            else begin  // 发不了就清零
                                busy         <= 1'b0;
                                is_load      <= 1'b0;
                            end
                        end
                    end else begin
                        // store/cacop 发送中
                        if (dcache_addr_ok_i) begin
                            valid_r[head] <= 1'b0;
                            can_sent_r[head] <= 1'b0;
                            head <= head_next;

                            // 优先发 load
                            if (load_ready_to_send && dcache_addr_ok_i) begin
                                dcache_valid_o      <= 1'b1;    // load是一定能发的
                                dcache_op_o         <= 1'b0;
                                dcache_size_o       <= load_size_r;
                                dcache_offset_o     <= load_paddr_r[3:0];
                                dcache_index_o      <= load_paddr_r[11:4];
                                dcache_tag          <= load_paddr_r[31:12];
                                dcache_uncache_en   <= load_is_uncache;
                                dcache_wdata_o      <= {DATA_WIDTH{1'b0}};
                                dcache_wstrb_o      <= {BYTE_WIDTH{1'b0}};
                                dcache_cacop_en_o   <= 1'b0;
                                dcache_cacop_mode_o <= 2'b00;
                                busy      <= 1'b1;
                                is_load   <= 1'b1;
                            end
                            // 否则继续发下一个 store
                            else if (next_valid_retired && dcache_addr_ok_i) begin
                                dcache_valid_o      <= can_sent_r[head_next];
                                dcache_op_o         <= 1'b1;
                                dcache_size_o       <= size_r[head_next];
                                dcache_offset_o     <= paddr_r[head_next][3:0];
                                dcache_index_o      <= paddr_r[head_next][11:4];
                                dcache_tag          <= paddr_r[head_next][31:12];
                                dcache_wdata_o      <= data_r[head_next];
                                dcache_wstrb_o      <= mask_r[head_next];
                                dcache_uncache_en   <= is_uncache_r[head_next];
                                dcache_cacop_en_o   <= is_cacop_r[head_next];
                                dcache_cacop_mode_o <= cacop_op_r[head_next];
                                busy  <= 1'b1;
                                is_load <= 1'b0;
                            end
                            // 都没有则结束
                            else begin
                                dcache_valid_o <= 1'b0;
                                busy <= 1'b0;
                                is_load <= 1'b0;
                            end
                        end
                    end
                end

                // ----- 空闲发起新请求 -----
                if (!busy) begin
                    if (load_ready_to_send && dcache_addr_ok_i) begin
                        dcache_valid_o      <= 1'b1;
                        dcache_op_o         <= 1'b0;
                        dcache_size_o       <= load_size_r;
                        dcache_offset_o     <= load_paddr_r[3:0];
                        dcache_index_o      <= load_paddr_r[11:4];
                        dcache_tag          <= load_paddr_r[31:12];
                        dcache_uncache_en   <= load_is_uncache;
                        dcache_wdata_o      <= {DATA_WIDTH{1'b0}};
                        dcache_wstrb_o      <= {BYTE_WIDTH{1'b0}};
                        dcache_cacop_en_o   <= 1'b0;
                        dcache_cacop_mode_o <= 2'b00;
                        busy      <= 1'b1;
                        is_load   <= 1'b1;
                    end else if (head_valid_retired && dcache_addr_ok_i) begin
                        dcache_valid_o      <= can_sent_r[head];
                        dcache_op_o         <= 1'b1;
                        dcache_size_o       <= size_r[head];
                        dcache_offset_o     <= paddr_r[head][3:0];
                        dcache_index_o      <= paddr_r[head][11:4];
                        dcache_tag          <= paddr_r[head][31:12];
                        dcache_wdata_o      <= data_r[head];
                        dcache_wstrb_o      <= mask_r[head];
                        dcache_uncache_en   <= is_uncache_r[head];
                        dcache_cacop_en_o   <= is_cacop_r[head];
                        dcache_cacop_mode_o <= cacop_op_r[head];
                        busy      <= 1'b1;
                        is_load   <= 1'b0;
                    end else begin
                        dcache_valid_o <= 1'b0;
                    end
                end
            end

            // 入队--------------------------------
            if (store_valid_i && store_ready_o && !flush_valid_i) begin
                valid_r[tail]      <= 1'b1;
                retired_r[tail]    <= 1'b0;
                is_uncache_r[tail] <= store_is_uncache_i;
                is_cacop_r[tail]   <= store_is_cacop_i;
                cacop_op_r[tail]   <= store_cacop_op_i;
                size_r[tail]       <= store_size_i;
                paddr_r[tail]      <= store_paddr_i;
                data_r[tail]       <= store_data_i;
                mask_r[tail]       <= store_mask_i;
                tail <= (tail == DEPTH-1) ? {PTR_WIDTH{1'b0}} : tail + 1;
            end

            if (load_valid_i && !load_valid_r && !flush_valid_i) begin  // LQ 里面没有读请求
                load_valid_r <= 1'b1;
                load_size_r  <= load_size_i;
                load_paddr_r <= load_paddr_i;
                load_is_uncache <= load_is_uncache_i;
            end
        end
    end

endmodule