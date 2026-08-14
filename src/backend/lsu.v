module lsu (
    input  wire         clk     ,
    input  wire         rstn    ,
    input  wire         stop    ,
    input  wire         clear   ,

    // ---- 发射接口 ----
    input  wire         valid_i         ,       // 发射信号，注意需要包含tlb指令
    input  wire [  5:0] op_lsu_i        ,       // [5]原子 [4]访存 [3]load [2]有符号 [1:0]大小
    input  wire [ 31:0] base_i          ,       // 基地址 (rj)
    input  wire [ 31:0] offset_i        ,       // 偏移量 (op[4] ||cacop || preld= imm  , invtlb = rk)
    input  wire [ 31:0] st_data_i       ,       // 存储数据 (rk)
    input  wire [  4:0] rd_index_i      ,       // 目的寄存器号（用于 cacop/preld 解码）
    input  wire [ 31:0] pc_i            ,       // 程序计数器（异常用）
    input  wire [  9:0] tlb_data_i      ,       // TLB 操作 {we,fill,rd,srch,invtlb_en,invtlb_op[4:0]}
    input  wire         cacop_sign_i    ,       // cache 操作
    input  wire         preld_sign_i    ,       // preld 指令 -0
    output wire         lsu_stall_o     ,       // LSU 忙，阻塞发射

    // ---- CSR 状态（地址映射）----
    input  wire         crmd_da                 ,
    input  wire         crmd_pg                 ,
    input  wire [  1:0] crmd_datm               ,
    input  wire [  1:0] crmd_plv                ,
    input  wire [ 18:0] csr_tlbehi_vppn         ,
    input  wire [  9:0] csr_asid_asid           ,
    input  wire         dmw0_plv0, dmw0_plv3    ,
    input  wire [  1:0] dmw0_mat                ,
    input  wire [  2:0] dmw0_pseg, dmw0_vseg    ,
    input  wire         dmw1_plv0, dmw1_plv3    ,
    input  wire [  1:0] dmw1_mat,
    input  wire [  2:0] dmw1_pseg, dmw1_vseg    ,

    // ---- TLB 接口 ----  // tlb的一些操作就得借用dcache的端口
    output wire         invtlb_valid       ,
    output wire [  4:0] invtlb_op          ,
    output wire [ 18:0] invtlb_vppn        ,
    output wire [  9:0] invtlb_asid        ,
    output wire [ 18:0] tlb_s1_vppn        ,
    output wire         tlb_s1_va_odd      ,
    output wire [  9:0] tlb_s1_asid        ,
    input  wire         tlb_s1_found       ,
    input  wire [  4:0] tlb_s1_index       ,
    input  wire [ 19:0] tlb_s1_ppn         ,
    input  wire [  5:0] tlb_s1_ps          ,
    input  wire [  1:0] tlb_s1_plv         ,
    input  wire [  1:0] tlb_s1_mat         ,
    input  wire         tlb_s1_d           ,
    input  wire         tlb_s1_v           ,

    // ---- LSQ 接口 ----
    output reg          store_valid        ,
    output reg  [ 31:0] store_paddr        ,
    output reg  [ 31:0] store_data         ,
    output reg  [  3:0] store_mask         ,
    output reg  [  2:0] store_size         ,
    output reg          store_is_uncache   ,
    output reg          store_is_cacop     ,
    output reg  [  1:0] store_cacop_op     ,
    input  wire         store_ready        ,
    output reg          load_valid         ,
    output reg  [ 31:0] load_paddr         ,
    output reg  [  2:0] load_size          ,
    output reg          load_is_uncache    ,
    input  wire         load_ready         ,
    input  wire [ 31:0] load_result        ,
    input  wire         load_result_valid  ,
    input  wire         ls_stall_i         ,

    // ---- icache cacop 控制 ----
    output reg          icache_cacop_en    ,
    output reg  [  1:0] icache_cacop_op    ,
    output reg  [ 31:0] icache_cacop_va    ,

    // ---- preld 控制 ---- // 这个控制暂时不用，到时候直接给dcache传0先验证结论
    output reg          preld_en           ,
    output reg  [  4:0] preld_hint         ,

    // ---- 结果输出（至 ROB）----
    output reg  [ 31:0] lsu_result         ,
    output reg          lsu_result_valid   ,
    output reg          lsu_exception      ,
    output reg  [  5:0] lsu_exccode        ,
    output reg  [ 31:0] lsu_excaddr
);

    // ================= 内部状态 =================
    reg         load_pending;              // LSQ 中是否有未完成的 Load
    // reg         load_is_ll_pending;        // 该未完成的 Load 是否为 LL（用于设置链接位）
    reg [  1:0] load_size_pending;         // 待返回 Load 的大小
    reg         load_sign_pending;         // 待返回 Load 的有符号标志
    reg [  1:0] load_addr_lsb_pending;     // 待返回 Load 的地址低 2 位（字节/半字选择）
    reg [ 31:0] load_paddr_pending;        // 待返回 Load 的物理地址（LL 时记录链接地址）

    // llbit由ROB自行判断并发送给lsq是否需要发送给dcache
    // // LL/SC 链接位
    // reg         llbit_reg;                // 链接位
    // reg [ 31:0] lladdr_reg;               // 链接物理地址

    // ================= 组合逻辑信号 =================
    wire [31:0] vaddr = base_i + offset_i; // 虚拟地址
    wire [ 1:0] addr_2 = vaddr[1:0];

    // 操作码字段
    wire op_atom = op_lsu_i[5];
    wire op_mem  = op_lsu_i[4];
    wire op_load = op_lsu_i[3];
    wire op_sign = op_lsu_i[2];
    wire [1:0] op_size = op_lsu_i[1:0];

    wire is_store = op_mem && !op_load && !op_atom;
    wire is_sc    = op_mem && !op_load &&  op_atom;
    wire is_load  = op_mem &&  op_load && !op_atom;
    wire is_ll    = op_mem &&  op_load &&  op_atom;

    // TLB 操作解码
    wire tlb_we    = tlb_data_i[9];
    wire tlb_fill  = tlb_data_i[8];
    wire tlb_rd    = tlb_data_i[7];
    wire tlb_srch  = tlb_data_i[6];
    wire invtlb_en = tlb_data_i[5];
    wire [4:0] invtlb_op_sig = tlb_data_i[4:0];

    // ================= 地址映射（DMW/TLB）=================
    wire dmw0_taken = crmd_pg && ((crmd_plv == 2'h3 && dmw0_plv3) || (crmd_plv == 2'h0 && dmw0_plv0)) &&
                      (vaddr[31:29] == dmw0_vseg);
    wire dmw1_taken = crmd_pg && ((crmd_plv == 2'h3 && dmw1_plv3) || (crmd_plv == 2'h0 && dmw1_plv0)) &&
                      (vaddr[31:29] == dmw1_vseg);
    wire tlb_use = crmd_pg && !(dmw0_taken || dmw1_taken);

    assign tlb_s1_vppn   = tlb_srch  ? csr_tlbehi_vppn :
                           invtlb_en ? invtlb_vppn : vaddr[31:13];
    assign tlb_s1_va_odd = vaddr[12];
    assign tlb_s1_asid   = invtlb_en ? invtlb_asid : csr_asid_asid;

    wire [31:0] paddr;
    assign paddr = crmd_da                         ? vaddr                              :
                   dmw0_taken                      ? {{dmw0_pseg}, vaddr[28:0]}         :
                   dmw1_taken                      ? {{dmw1_pseg}, vaddr[28:0]}         :
                   (crmd_pg && tlb_s1_ps == 6'h15) ? {tlb_s1_ppn[19:9], vaddr[20:0]}    :
                   (crmd_pg && tlb_s1_ps == 6'h0c) ? {tlb_s1_ppn[19:0], vaddr[11:0]}    : 32'b0;

    wire is_uncache = crmd_da      ? (crmd_datm == 2'b00)  :
                      dmw0_taken   ? (dmw0_mat == 2'b00)   :
                      dmw1_taken   ? (dmw1_mat == 2'b00)   :
                      tlb_s1_found ? (tlb_s1_mat == 2'b00) : 1'b0;

    wire instr_accept ;
    wire ex_sign_local;
    // ================= invTLB 输出 =================
    assign invtlb_valid = instr_accept && invtlb_en && !ex_sign_local;
    assign invtlb_vppn  = offset_i[31:13]; // 这里就是rk_data
    assign invtlb_asid  = base_i[9:0];     // 这里就是rj_data
    assign invtlb_op    = invtlb_op_sig;

    // ================= 异常检查 =================
    wire alignment_ok = (op_size == 2'b11 && addr_2     == 2'b00) ||
                        (op_size == 2'b10 && addr_2[0]  == 1'b0)  ||
                        (op_size == 2'b01)                          ;
    
    // wire store_active = is_store || sc_success;
    wire store_active = is_store || is_sc;  // 现在不检测llbit，一定发送到lsq，如果触发异常需要ROB中先检测llbit
    wire load_active  = is_load || is_ll;
    wire access_mem   = store_active || load_active;
    wire [1:0] cacop_op ;
    wire ex_TLBR = (access_mem | (cacop_sign_i && (cacop_op == 2'h2))) && !tlb_s1_found && tlb_use;
    wire ex_PIL  = (load_active | (cacop_sign_i && (cacop_op == 2'h2))) && tlb_s1_found && !tlb_s1_v && tlb_use;
    wire ex_PIS  = store_active && tlb_s1_found && !tlb_s1_v && tlb_use;
    wire ex_PME  = store_active && tlb_s1_found && !tlb_s1_d && tlb_use;
    wire ex_PPI  = (access_mem | (cacop_sign_i && (cacop_op == 2'h2))) && tlb_s1_found && (tlb_s1_plv < crmd_plv) && tlb_use;
    wire ex_ALE  = access_mem && !alignment_ok;
    assign ex_sign_local = ex_PIL | ex_PIS | ex_PME | ex_PPI | ex_ALE | ex_TLBR;
    wire [5:0] ecode_local =  ex_ALE      ? 6'h09    :
                              ex_TLBR     ? 6'h3f    :
                              ex_PIL      ? 6'h01    :
                              ex_PIS      ? 6'h02    :
                              ex_PPI      ? 6'h07    :
                              ex_PME      ? 6'h04    : 6'b0;

    // ================= Store 数据 / 掩码 / 大小 =================
    wire [31:0] store_data_prep;
    wire [ 3:0] store_wstrb;    // 实际掩码在最终会进行判断置零
    assign {store_data_prep, store_wstrb} =
        (op_size == 2'b11)      ? {st_data_i, 4'b1111}                                  :   // word
        (op_size == 2'b10)      ? (vaddr[1] ? { {st_data_i[15:0], 16'b0}, 4'b1100 }
                                            : { {16'b0, st_data_i[15:0]}, 4'b0011 })    :   // half
        (vaddr[1:0] == 2'b00)   ? { {24'b0, st_data_i[7:0]       }, 4'b0001 }           :
        (vaddr[1:0] == 2'b01)   ? { {16'b0, st_data_i[7:0], 8'b0 }, 4'b0010 }           :
        (vaddr[1:0] == 2'b10)   ? { {8'b0,  st_data_i[7:0], 16'b0}, 4'b0100 }           :
                                  { {st_data_i[7:0], 24'b0       }, 4'b1000 }           ;   // byte
    wire [2:0] store_size_w = (op_size == 2'b11) ? 3'b010 : 
                              (op_size == 2'b10) ? 3'b001 : 3'b000;

    // ================= cacop / preld 译码 =================
    wire [4:0] cacop_code = rd_index_i;
    assign cacop_op = cacop_code[4:3];
    wire dcache_cacop = cacop_sign_i && (cacop_code[2:0] == 3'b001) && !ex_sign_local;
    wire icache_cacop = cacop_sign_i && (cacop_code[2:0] == 3'b000) && !ex_sign_local;

    // ================= 指令接受条件 =================
    // Load 需要：无未完成 Load 且 load_ready 有效
    // Store 需要：store_ready 有效
    // TLB 需要：不需要考虑lsq，随时都行
    // LSU 注意：当上一个指令为load、这一个指令为store时，lsq中load资源还没释放，就不能接受新指令
    wire need_load   = is_load || is_ll;                                                    // 表示需要lsq中的load资源
    wire need_store  = is_store || is_sc || dcache_cacop;                                   // 表示需要lsq中的store资源
    wire load_ok     = !need_load || load_ready;                                            // 表示lsq中的load资源是否可用
    wire store_ok    = !need_store || store_ready;                                          // 表示lsq中的store资源是否可用
    assign instr_accept = valid_i && !stop && !clear;   // 表示指令可被接受

    // lsq的stall信号是说lsq存不下了，但是从lsu到lsq有一个周期的延迟，lsq满了时lsu中还有一个数据
    assign lsu_stall_o = stop || clear || !load_ready || !store_ready; // 只要有一个不满足就不让发射

    // ================= LSQ 请求生成 =================
    always @(*) begin
        store_valid      = instr_accept && !ex_sign_local && (is_store || is_sc || dcache_cacop);
        store_paddr      = paddr;
        // store_paddr      = dcache_cacop ? (cacop_op == 2'h2 ? paddr : vaddr) : paddr;    // icache_cacop_va是要重走icache的tlb
        store_data       = store_data_prep;
        store_mask       = (is_store || is_sc) ? store_wstrb : 4'b0;
        store_size       = store_size_w;
        store_is_uncache = is_uncache;
        store_is_cacop   = dcache_cacop;
        store_cacop_op   = cacop_op;

        load_valid       = instr_accept && !ex_sign_local && (is_load || is_ll);
        load_paddr       = paddr;
        // load_paddr       = dcache_cacop ? (cacop_op == 2'h2 ? paddr : vaddr) : paddr;    // icache_cacop_va是要重走icache的tlb
        load_size        = store_size_w;
        load_is_uncache  = is_uncache;
    end

    // ================= Load 结果符号扩展 =================
    // 利用 pending 寄存器中保存的 Load 信息对返回数据进行扩展
    wire [31:0] load_data_ext;
    wire [15:0] half_raw = load_addr_lsb_pending[1] ? load_result[31:16] : load_result[15:0];
    wire [ 7:0] byte_raw = (load_addr_lsb_pending == 2'b00) ? load_result[ 7:0]  :
                           (load_addr_lsb_pending == 2'b01) ? load_result[15:8]  :
                           (load_addr_lsb_pending == 2'b10) ? load_result[23:16] : load_result[31:24];
    assign load_data_ext = (load_size_pending == 2'b11) ? load_result :
                           (load_size_pending == 2'b10) ? (load_sign_pending ? {{16{half_raw[15]}}, half_raw} : {16'b0, half_raw}) :
                                                          (load_sign_pending ? {{24{byte_raw[7]}}, byte_raw} : {24'b0, byte_raw});

    // ================= TLB 结果拼接 =================
    // 整体按照一定顺序输出，ROB只需要知道是tlb指令就可直接使用不需要细分
    // inv_tlb不需要返回结果，直接全0即可
    wire [31:0] tlb_result = {22'b0, tlb_we, tlb_fill, tlb_rd, tlb_srch, tlb_s1_found, (tlb_s1_found ? tlb_s1_index : 5'b0)};

    // 不再由lsu判断是否成功
    // // ================= SC 成功判断 =================
    // wire sc_success = is_sc && llbit_reg && (paddr == lladdr_reg);

    // ================= 结果输出 =================
    // 存在load数据没写回的时候，lsq中load指令就不会清除，下一个指令就不能发过来（包括tlb）
    // 因此lsu不会出现按数据错位，ROB只需顺序接收数据
    // 因为除了load数据返回，其他结果都是组合逻辑一个周期直接输出的，而ROB需要在下一个周期上升沿采样数据
    // 因此可以直接在本周期就拉高lsu_result_valid
    always @(*) begin
        lsu_result_valid = 1'b0;    
        lsu_result       = 32'b0;
        lsu_exception    = 1'b0;
        lsu_exccode      = 6'b0;
        lsu_excaddr      = pc_i;

        // 新指令异常
        if (instr_accept && ex_sign_local) begin
            lsu_exception = 1'b1;
            lsu_result_valid = 1'b1;
            lsu_exccode   = ecode_local;
            lsu_excaddr   = vaddr;
        end else if (load_result_valid) begin
            // Load 数据返回（组合逻辑直接使用 load_result_valid 和 pending 寄存器）
            lsu_result_valid = 1'b1;
            lsu_result       = load_data_ext;
        end else if (instr_accept && !ex_sign_local) begin  
            // 以下指令只要被接受就是一周期出数
            if (tlb_we || tlb_fill || tlb_rd || tlb_srch) begin
                lsu_result_valid = 1'b1;
                lsu_result       = tlb_result;          // csr需要知道的tlb操作结果
            end else if (is_store || is_sc || invtlb_en || cacop_sign_i || preld_sign_i) begin
                lsu_result_valid = 1'b1;
                lsu_result       = 32'b0;               // “store”和invtlb返回0
            end
        end
    end

    // ================= 时序逻辑（pending 和链接位更新）=================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            load_pending           <= 1'b0;
            // load_is_ll_pending     <= 1'b0;
            load_size_pending      <= 2'b0;
            load_sign_pending      <= 1'b0;
            load_addr_lsb_pending  <= 2'b0;
            load_paddr_pending     <= 32'b0;
            // llbit_reg              <= 1'b0;
            // lladdr_reg             <= 32'b0;
        end else if (clear) begin
            // 流水线清空时，LSQ 内的 Load 也应被清空，因此复位 pending 状态
            load_pending           <= 1'b0;
            // load_is_ll_pending     <= 1'b0;
            // llbit 不清空（架构要求）
        end else if (!stop) begin
            // Load 发射：保存扩展信息
            if (instr_accept && !ex_sign_local && (is_load || is_ll)) begin
                load_pending           <= 1'b1;
                // load_is_ll_pending     <= is_ll;
                load_size_pending      <= op_size;
                load_sign_pending      <= op_sign;
                load_addr_lsb_pending  <= vaddr[1:0];
                load_paddr_pending     <= paddr;
            end
            // Load 数据返回：清除 pending
            if (load_result_valid) begin
                load_pending <= 1'b0;

                // 不再于lsu中检查，也不再由lsu中完成llbit更新与判定
                // // 若为 LL，置位链接位
                // if (load_is_ll_pending) begin
                //     llbit_reg  <= 1'b1;
                //     lladdr_reg <= load_paddr_pending;
                // end
            end

            // // SC 指令执行：清除链接位
            // if (instr_accept && !ex_sign_local && is_sc) begin
            //     llbit_reg <= 1'b0;  // sucsess是组合逻辑发送，这里是时序逻辑清零正好错开
            // end
        end
    end

    // ================= icache cacop / preld 控制 =================
    // dcache cacop 因为直接传到lsq中不再外连，和icache有所不同
    always @(*) begin
        icache_cacop_en = instr_accept && icache_cacop && !ex_sign_local;
        icache_cacop_op = icache_cacop ? cacop_op : 2'b0;
        icache_cacop_va = (cacop_op == 2'h2) ? paddr : vaddr;
        preld_en   = instr_accept && preld_sign_i && (rd_index_i == 5'd0 || rd_index_i == 5'd8) && !ex_sign_local;
        preld_hint = rd_index_i;
    end

endmodule