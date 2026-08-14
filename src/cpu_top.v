module core_top(
    input  wire        aclk,
    input  wire        aresetn,
    
    //中断
    input  wire [ 7:0] intrpt,
    
    //AXI interface 
    //read reqest
    output wire [ 3:0] arid,
    output wire [31:0] araddr,
    output wire [ 7:0] arlen,
    output wire [ 2:0] arsize,
    output wire [ 1:0] arburst,
    output wire [ 1:0] arlock,
    output wire [ 3:0] arcache,
    output wire [ 2:0] arprot,
    output wire        arvalid,
    input  wire        arready,
    //read back
    input  wire [ 3:0] rid,
    input  wire [31:0] rdata,
    input  wire [ 1:0] rresp,
    input  wire        rlast,
    input  wire        rvalid,
    output wire        rready,
    //write request
    output wire [ 3:0] awid,
    output wire [31:0] awaddr,
    output wire [ 7:0] awlen,
    output wire [ 2:0] awsize,
    output wire [ 1:0] awburst,
    output wire [ 1:0] awlock,
    output wire [ 3:0] awcache,
    output wire [ 2:0] awprot,
    output wire        awvalid,
    input  wire        awready,
    //write data
    output wire [ 3:0] wid,
    output wire [31:0] wdata,
    output wire [ 3:0] wstrb,
    output wire        wlast,
    output wire        wvalid,
    input  wire        wready,
    //write back
    input  wire [ 3:0] bid,
    input  wire [ 1:0] bresp,
    input  wire        bvalid,
    output wire        bready,

    //debug
    input           break_point,//无需实现功能，仅提供接口即可，输入1’b0
    input           infor_flag,//无需实现功能，仅提供接口即可，输入1’b0
    input  [ 4:0]   reg_num,//无需实现功能，仅提供接口即可，输入5’b0
    output          ws_valid,//无需实现功能，仅提供接口即可
    output [31:0]   rf_rdata,//无需实现功能，仅提供接口即可

    //debug
    output wire [31:0] debug0_wb_pc      ,
    output wire [ 3:0] debug0_wb_rf_wen  ,
    output wire [ 4:0] debug0_wb_rf_wnum ,
    output wire [31:0] debug0_wb_rf_wdata,
    output wire [31:0] debug0_wb_inst
);

`include "LoongArch.vh"

// =========================================================================
// TODO: 占位实例 — 未在 tb_frontEnd 中出现的模块，后续连接
// =========================================================================

// --- AXI Bridge (连接 CPU 与外部 AXI 总线) ---
// inst_* 已连实际 Icache，data_* 已连实际 DCache
axi_bridge u_axi_bridge (
    .clk                (aclk),
    .reset              (~aresetn),

    .arid               (arid),
    .araddr             (araddr),
    .arlen              (arlen),
    .arsize             (arsize),
    .arburst            (arburst),
    .arlock             (arlock),
    .arcache            (arcache),
    .arprot             (arprot),
    .arvalid            (arvalid),
    .arready            (arready),
    .rid                (rid),
    .rdata              (rdata),
    .rresp              (rresp),
    .rlast              (rlast),
    .rvalid             (rvalid),
    .rready             (rready),
    .awid               (awid),
    .awaddr             (awaddr),
    .awlen              (awlen),
    .awsize             (awsize),
    .awburst            (awburst),
    .awlock             (awlock),
    .awcache            (awcache),
    .awprot             (awprot),
    .awvalid            (awvalid),
    .awready            (awready),
    .wid                (wid),
    .wdata              (wdata),
    .wstrb              (wstrb),
    .wlast              (wlast),
    .wvalid             (wvalid),
    .wready             (wready),
    .bid                (bid),
    .bresp              (bresp),
    .bvalid             (bvalid),
    .bready             (bready),

    // inst_* — 连接实际 Icache miss 接口
    .inst_rd_req        (icache_rd_req),
    .inst_rd_type       (icache_rd_type),
    .inst_rd_addr       (icache_rd_addr),
    .inst_rd_rdy        (icache_rd_rdy),
    .inst_ret_valid     (icache_ret_valid),
    .inst_ret_last      (icache_ret_last),
    .inst_ret_data      (icache_ret_data),
    .inst_wr_req        (icache_wr_req),
    .inst_wr_type       (icache_wr_type),
    .inst_wr_addr       (icache_wr_addr),
    .inst_wr_wstrb      (icache_wr_wstrb),
    .inst_wr_data       (icache_wr_data),
    .inst_wr_rdy        (icache_wr_rdy),

    // data_* — 连接实际 DCache 接口
    .data_rd_req        (data_rd_req),
    .data_rd_type       (data_rd_type),
    .data_rd_addr       (data_rd_addr),
    .data_rd_rdy        (data_rd_rdy),
    .data_ret_valid     (data_ret_valid),
    .data_ret_last      (data_ret_last),
    .data_ret_data      (data_ret_data),
    .data_wr_req        (data_wr_req),
    .data_wr_type       (data_wr_type),
    .data_wr_addr       (data_wr_addr),
    .data_wr_wstrb      (data_wr_wstrb),
    .data_wr_data       (data_wr_data),
    .data_wr_rdy        (data_wr_rdy),
    .write_buffer_empty ()
);

// --- CSR (控制与状态寄存器) ---
// 已连：读端口 ← rob，写端口/异常 ← commit，DMW → pre_if/exe_top
csr u_csr (
    .clk                (aclk),
    .rstn               (aresetn),

    .csr_raddr          (csr_raddr),      // ← rob.com_csr_raddr
    .csr_rdata          (csr_rdata),      // → rob.com_csr_rdata
    .csr_era_addr       (csr_era_addr),
    .ex_entry           (csr_ex_entry),
    .crmd_da            (csr_crmd_da),
    .crmd_pg            (csr_crmd_pg),
    .crmd_datf          (csr_crmd_datf),
    .crmd_datm          (crmd_datm),      // → exe_top.crmd_datm
    .crmd_plv           (csr_crmd_plv),

    .csr_we             (csr_we),         // ← commit.o_csr_we
    .csr_waddr          (csr_waddr),      // ← commit.o_csr_waddr
    .csr_wdata          (csr_wdata),      // ← commit.o_csr_wdata
    .csr_wmask          (csr_wmask),      // ← commit.o_csr_wmask

    .wb_ex              (ex_sign),        // ← commit.o_ex_sign
    .wb_pc              (ex_pc),          // ← commit.o_ex_pc
    .ws_addr            (ex_addr),        // ← commit.o_ex_addr
    .ertn_op            (ertn_sign),      // ← commit.o_ertn_sign
    .ecode              (ex_code),        // ← commit.o_ex_code
    .subecode           (subecode_9[8:0]),// ← commit.o_subecode_9
    .hw_int_in          (intrpt),
    .has_int            (pif_int_sign),   // 中断 → 前端
    .timer_id           (timer_id),       // → exe_top.i_cnt_id（rdcntid）

    .llbit_in           (llbit_w),        // ← commit.o_llbit
    .llbit_set_in       (llbit_set),      // ← commit.o_llbit_set
    .ds_llbit           (ds_llbit),       // → commit.i_llbit（当前 LLbit）

    // TLB 写端口 — 连接 TLB
    .tlb_w_index        (tlb_w_index),
    .tlb_w_e            (tlb_w_e),
    .tlb_w_vppn         (tlb_w_vppn),
    .tlb_w_ps           (tlb_w_ps),
    .tlb_w_asid         (tlb_w_asid),
    .tlb_w_g            (tlb_w_g),
    .tlb_w_ppn0         (tlb_w_ppn0),
    .tlb_w_plv0         (tlb_w_plv0),
    .tlb_w_mat0         (tlb_w_mat0),
    .tlb_w_d0           (tlb_w_d0),
    .tlb_w_v0           (tlb_w_v0),
    .tlb_w_ppn1         (tlb_w_ppn1),
    .tlb_w_plv1         (tlb_w_plv1),
    .tlb_w_mat1         (tlb_w_mat1),
    .tlb_w_d1           (tlb_w_d1),
    .tlb_w_v1           (tlb_w_v1),

    // TLB 读端口 — 连接 TLB
    .tlb_r_en           (tlb_r_en),       // ← commit.o_tlb_rd
    .tlb_r_index        (tlb_r_index),
    .tlb_r_e            (tlb_r_e),
    .tlb_r_vppn         (tlb_r_vppn),
    .tlb_r_ps           (tlb_r_ps),
    .tlb_r_asid         (tlb_r_asid),
    .tlb_r_g            (tlb_r_g),
    .tlb_r_ppn0         (tlb_r_ppn0),
    .tlb_r_plv0         (tlb_r_plv0),
    .tlb_r_mat0         (tlb_r_mat0),
    .tlb_r_d0           (tlb_r_d0),
    .tlb_r_v0           (tlb_r_v0),
    .tlb_r_ppn1         (tlb_r_ppn1),
    .tlb_r_plv1         (tlb_r_plv1),
    .tlb_r_mat1         (tlb_r_mat1),
    .tlb_r_d1           (tlb_r_d1),
    .tlb_r_v1           (tlb_r_v1),

    .tlb_search         (tlb_search),     // ← commit.o_tlb_search
    .tlb_s_found        (tlb_s_found),    // ← commit.o_tlb_s_found
    .tlb_s_index        (tlb_s_index),    // ← commit.o_tlb_s_index

    // DMW — 连接到 pre_if_stage
    .dmw0_plv0          (csr_dmw0_plv0),
    .dmw0_plv3          (csr_dmw0_plv3),
    .dmw0_mat           (csr_dmw0_mat),
    .dmw0_pseg          (csr_dmw0_pseg),
    .dmw0_vseg          (csr_dmw0_vseg),
    .dmw1_plv0          (csr_dmw1_plv0),
    .dmw1_plv3          (csr_dmw1_plv3),
    .dmw1_mat           (csr_dmw1_mat),
    .dmw1_pseg          (csr_dmw1_pseg),
    .dmw1_vseg          (csr_dmw1_vseg),

    // Diff 信号 — 暂不连接
    .csr_crmd_diff      (),
    .csr_prmd_diff      (),
    .csr_ectl_diff      (),
    .csr_estat_diff     (),
    .csr_era_diff       (),
    .csr_badv_diff      (),
    .csr_eentry_diff    (),
    .csr_tlbidx_diff    (),
    .csr_tlbehi_diff    (),
    .csr_tlbelo0_diff   (),
    .csr_tlbelo1_diff   (),
    .csr_asid_diff      (),
    .csr_save0_diff     (),
    .csr_save1_diff     (),
    .csr_save2_diff     (),
    .csr_save3_diff     (),
    .csr_tid_diff       (),
    .csr_tcfg_diff      (),
    .csr_tval_diff      (),
    .csr_ticlr_diff     (),
    .csr_llbctl_diff    (),
    .csr_tlbrentry_diff (),
    .csr_dmw0_diff      (),
    .csr_dmw1_diff      (),
    .csr_pgdl_diff      (),
    .csr_pgdh_diff      ()
);

// --- TLB (地址转换旁路缓冲) ---
// s0 已连 pre_if_stage，s1/invtlb 已连 exe_top，读写/we 已连 CSR/commit/counter
tlb #(
    .TLBNUM (8),
    .TLBSET (4)
) u_tlb (
    .clk                (aclk),
    .rstn               (aresetn),

    // Search port 0 (取指) — 连接到 pre_if_stage
    .s0_vppn            (pif_tlb_s0_vppn),
    .s0_va_odd          (pif_tlb_s0_va_odd),
    .s0_asid            (tlb_w_asid),     // 来自 CSR
    .s0_found           (tlb_pif_s0_found),
    .s0_index           (),
    .s0_ppn             (tlb_pif_s0_ppn),
    .s0_ps              (tlb_pif_s0_ps),
    .s0_plv             (tlb_pif_s0_plv),
    .s0_mat             (tlb_pif_s0_mat),
    .s0_d               (tlb_pif_s0_d),
    .s0_v               (tlb_pif_s0_v),

    // Search port 1 (访存) — 连接 exe_top (LSU)
    .s1_vppn            (tlb_s1_vppn),
    .s1_va_odd          (tlb_s1_va_odd),
    .s1_asid            (tlb_s1_asid),
    .s1_found           (tlb_s1_found),
    .s1_index           (tlb_s1_index),
    .s1_ppn             (tlb_s1_ppn),
    .s1_ps              (tlb_s1_ps),
    .s1_plv             (tlb_s1_plv),
    .s1_mat             (tlb_s1_mat),
    .s1_d               (tlb_s1_d),
    .s1_v               (tlb_s1_v),

    .invtlb_valid       (invtlb_valid),   // ← exe_top
    .invtlb_op          (invtlb_op),      // ← exe_top

    // Write port — 连接提交级
    .we                 (tlb_we),         // ← commit.o_tlb_we
    .tlbfill            (tlbfill_en),     // ← commit.o_tlbfill_en
    .rand_index         (tlb_w_rand_index), // ← counter.o_rand_index
    .w_index            (tlb_w_index),
    .w_e                (tlb_w_e),
    .w_vppn             (tlb_w_vppn),
    .w_ps               (tlb_w_ps),
    .w_asid             (tlb_w_asid),
    .w_g                (tlb_w_g),
    .w_ppn0             (tlb_w_ppn0),
    .w_plv0             (tlb_w_plv0),
    .w_mat0             (tlb_w_mat0),
    .w_d0               (tlb_w_d0),
    .w_v0               (tlb_w_v0),
    .w_ppn1             (tlb_w_ppn1),
    .w_plv1             (tlb_w_plv1),
    .w_mat1             (tlb_w_mat1),
    .w_d1               (tlb_w_d1),
    .w_v1               (tlb_w_v1),

    // Read port — 连接 CSR
    .r_index            (tlb_r_index),
    .r_e                (tlb_r_e),
    .r_vppn             (tlb_r_vppn),
    .r_ps               (tlb_r_ps),
    .r_asid             (tlb_r_asid),
    .r_g                (tlb_r_g),
    .r_ppn0             (tlb_r_ppn0),
    .r_plv0             (tlb_r_plv0),
    .r_mat0             (tlb_r_mat0),
    .r_d0               (tlb_r_d0),
    .r_v0               (tlb_r_v0),
    .r_ppn1             (tlb_r_ppn1),
    .r_plv1             (tlb_r_plv1),
    .r_mat1             (tlb_r_mat1),
    .r_d1               (tlb_r_d1),
    .r_v1               (tlb_r_v1)
);

// --- counter (计时器 / TLB 随机索引生成) ---
counter u_counter (
    .clk                (aclk),
    .rstn               (aresetn),
    .o_cnt_data_64      (cnt_data_64),     // → exe_top.i_cnt_data_64（rdcntvl/vh）
    .o_rand_index       (tlb_w_rand_index) // → tlb.rand_index
);

// =========================================================================
// 前端流水线 — 参考 tb_frontEnd.v 连接 (pre_if_stage → branch_predict
//              → Icache_top → if_stage → id_stage + stop_control)
// =========================================================================

// ----------------------------- 内部线网声明 -----------------------------

// 流水线控制 (stop_control → 各级)
wire pipeline_stop;
wire pipeline_clear;

// pre_if_stage ↔ branch_predict
wire        pif_pred_en;
wire [31:0] pif_pred_pc;
wire [ 1:0] pred_pif_taken;
wire [63:0] pred_pif_target;
wire [ 5:0] pred_pif_num;
wire        pred_pif_wrong;
wire [31:0] pred_pif_correct_pc;

// pre_if_stage → Icache_top
wire        pif_icache_en;
wire        pif_icache_pc_valid;
wire [ 5:0] pif_icache_num;
wire [31:0] pif_icache_pc;
wire [31:0] pif_icache_to_if_pc;
wire [ 6:0] pif_icache_exdata;
wire        pif_icache_uncache_en;

// pre_if_stage → if_stage (旁路 icache)
wire [ 1:0] pif_if_istaken;
wire [63:0] pif_if_target;

// pre_if_stage 空闲标志
wire        pif_idle_sign;

// Icache_top → if_stage
wire [31:0] icache_if_pc;
wire [ 6:0] icache_if_exdata;
wire        icache_if_valid;
wire        icache_if_inst0_valid;

// Icache_top → AXI / 实际 Icache (miss 请求)
wire [31:0] icache_axi_pc;
wire        icache_axi_uncache_en;

// if_stage → branch_predict (跳转信息包)
wire [64:0] if_pd_jump_data;

// if_stage → id_stage
wire [169:0] if_id_data;

// id_stage 输出
wire [459:0] id_issue_data;
wire [23:0]  id_inst1_stop_sign;
wire         id_inst1_tlbsrch_sign;
wire [23:0]  id_inst0_stop_sign;
wire         id_inst0_tlbsrch_sign;

// branch_predict ← 后端/写回级
wire        wb_pred_retire_en;
wire        wb_pred_retire_taken;
wire [31:0] wb_pred_retire_target;

// stop_control 输入 (来自后端)
wire backend_stop_req;
wire wb_ex_sign;
wire wb_ertn_sign;
wire wb_cacop_sign;

// reset（高有效，供 icache 使用）
wire reset;
assign reset = ~aresetn;

// Icache 握手 (来自实际 Icache)
wire icache_addr_ok;
wire icache_data_ok;

// 实际 Icache <-> AXI Bridge (inst_*)
wire        icache_rd_req;
wire [ 2:0] icache_rd_type;
wire [31:0] icache_rd_addr;
wire        icache_rd_rdy;
wire        icache_ret_valid;
wire        icache_ret_last;
wire [31:0] icache_ret_data;
wire        icache_wr_req;
wire [ 2:0] icache_wr_type;
wire [31:0] icache_wr_addr;
wire [ 3:0] icache_wr_wstrb;
wire [127:0] icache_wr_data;
wire        icache_wr_rdy;

// icache 访问地址拆分
wire [ 3:0] icache_offset;
wire [ 7:0] icache_index;
wire [19:0] icache_tag;

// icache cacop（来自后端 exe_top）
wire [ 1:0] icache_cacop_op;
wire [ 3:0] icache_cacop_offset;
wire [ 7:0] icache_cacop_index;
wire [19:0] icache_cacop_tag;

// CSR <-> TLB 写端口
wire [ 4:0] tlb_w_index;
wire        tlb_w_e, tlb_w_g, tlb_w_d0, tlb_w_v0, tlb_w_d1, tlb_w_v1;
wire [18:0] tlb_w_vppn;
wire [ 5:0] tlb_w_ps;
wire [ 9:0] tlb_w_asid;
wire [19:0] tlb_w_ppn0, tlb_w_ppn1;
wire [ 1:0] tlb_w_plv0, tlb_w_mat0, tlb_w_plv1, tlb_w_mat1;
wire [ 4:0] tlb_w_rand_index;           // counter → tlb.rand_index

// CSR <-> TLB 读端口
wire [ 4:0] tlb_r_index;
wire        tlb_r_e, tlb_r_g, tlb_r_d0, tlb_r_v0, tlb_r_d1, tlb_r_v1;
wire [18:0] tlb_r_vppn;
wire [ 5:0] tlb_r_ps;
wire [ 9:0] tlb_r_asid;
wire [19:0] tlb_r_ppn0, tlb_r_ppn1;
wire [ 1:0] tlb_r_plv0, tlb_r_mat0, tlb_r_plv1, tlb_r_mat1;

// pre_if_stage CSR / TLB / 异常输入 (来自 CSR/TLB/后端)
wire [31:0] csr_era_addr;
wire [31:0] csr_ex_entry;
wire        csr_crmd_da;
wire        csr_crmd_pg;
wire [ 1:0] csr_crmd_datf;
wire [ 1:0] csr_crmd_plv;
wire        csr_dmw0_plv0;
wire        csr_dmw0_plv3;
wire [ 1:0] csr_dmw0_mat;
wire [ 2:0] csr_dmw0_pseg;
wire [ 2:0] csr_dmw0_vseg;
wire        csr_dmw1_plv0;
wire        csr_dmw1_plv3;
wire [ 1:0] csr_dmw1_mat;
wire [ 2:0] csr_dmw1_pseg;
wire [ 2:0] csr_dmw1_vseg;

wire [18:0] pif_tlb_s0_vppn;
wire        pif_tlb_s0_va_odd;
wire        tlb_pif_s0_found;
wire [19:0] tlb_pif_s0_ppn;
wire [ 5:0] tlb_pif_s0_ps;
wire [ 1:0] tlb_pif_s0_plv;
wire [ 1:0] tlb_pif_s0_mat;
wire        tlb_pif_s0_d;
wire        tlb_pif_s0_v;

wire        pif_ex_sign;
wire        pif_ertn_sign;
wire        pif_idle_sign_i;
wire        pif_int_sign;

wire        pif_cacop_sign;
wire [31:0] pif_cacop_pc;
wire        pif_icache_cacop_en;

// ----------------------------- 模块实例化 -----------------------------

// pre_if_stage — 预取指级
pre_if_stage u_pre_if_stage (
    .clk                (aclk),
    .rstn               (aresetn),
    .stop               (pipeline_stop),

    // CSR
    .csr_era_addr       (csr_era_addr),
    .ex_entry           (csr_ex_entry),
    .crmd_da            (csr_crmd_da),
    .crmd_pg            (csr_crmd_pg),
    .crmd_datf          (csr_crmd_datf),
    .crmd_plv           (csr_crmd_plv),
    .dmw0_plv0          (csr_dmw0_plv0),
    .dmw0_plv3          (csr_dmw0_plv3),
    .dmw0_mat           (csr_dmw0_mat),
    .dmw0_pseg          (csr_dmw0_pseg),
    .dmw0_vseg          (csr_dmw0_vseg),
    .dmw1_plv0          (csr_dmw1_plv0),
    .dmw1_plv3          (csr_dmw1_plv3),
    .dmw1_mat           (csr_dmw1_mat),
    .dmw1_pseg          (csr_dmw1_pseg),
    .dmw1_vseg          (csr_dmw1_vseg),

    // TLB
    .tlb_s0_vppn        (pif_tlb_s0_vppn),
    .tlb_s0_va_odd      (pif_tlb_s0_va_odd),
    .tlb_s0_found       (tlb_pif_s0_found),
    .tlb_s0_ppn         (tlb_pif_s0_ppn),
    .tlb_s0_ps          (tlb_pif_s0_ps),
    .tlb_s0_plv         (tlb_pif_s0_plv),
    .tlb_s0_mat         (tlb_pif_s0_mat),
    .tlb_s0_d           (tlb_pif_s0_d),
    .tlb_s0_v           (tlb_pif_s0_v),

    // 异常 / 中断
    .i_ex               (pif_ex_sign),
    .i_ertn             (pif_ertn_sign),
    .i_idle             (pif_idle_sign_i),
    .i_int              (pif_int_sign),

    // CACOP
    .i_cacop_sign       (pif_cacop_sign),
    .i_cacop_pc         (pif_cacop_pc),
    .i_icache_cacop_en  (pif_icache_cacop_en),

    // Icache 握手
    .i_addr_ok          (icache_addr_ok),
    .i_data_ok          (icache_data_ok),

    // 分支预测器
    .o_pred_en          (pif_pred_en),
    .o_pred_pc_32       (pif_pred_pc),
    .i_pred_taken_2     (pred_pif_taken),
    .i_pred_target_64   (pred_pif_target),
    .i_pred_num_6       (pred_pif_num),
    .i_pred_wrong       (pred_pif_wrong),
    .i_pred_correctPC_32(pred_pif_correct_pc),

    // 输出 → Icache_top / if_stage
    .o_idle_sign        (pif_idle_sign),
    .o_pif_en           (pif_icache_en),
    .o_pif_pc_valid     (pif_icache_pc_valid),
    .o_pif_num_6        (pif_icache_num),
    .o_pc_32            (pif_icache_pc),
    .o_pc_to_if_32      (pif_icache_to_if_pc),
    .o_pif_isTaken_2    (pred_if_istaken),
    .o_pif_TakenPC_64   (pred_if_target),
    .o_preif_ex_data_7  (pif_icache_exdata),
    .o_preif_uncache_en (pif_icache_uncache_en)
);

// branch_predict — 分支预测器
wire pred_if_en, pred_if_isTaken;
wire [2:0] pred_if_inst_type_3;
wire [59:0] pred_if_pc_60; 
branch_predict u_branch_predict (
    .clk                (aclk),
    .rstn               (aresetn),
    .clear              (pipeline_clear),

    // pif 接口
    .i_pc_valid         (~pif_pred_pc[2]),
    .i_predict_en       (pif_pred_en),
    .i_nextPC_32        ({pif_pred_pc[31:2], 2'b00}),
    .o_wrong_predict    (pred_pif_wrong),
    .o_correct_pc_32    (pred_pif_correct_pc),

    // if_stage 跳转信息
    .i_if_en            (pred_if_en),
    .i_if_isTaken       (pred_if_isTaken),
    .i_if_inst_type_3   (pred_if_inst_type_3),
    .i_if_pc_60         (pred_if_pc_60),

    // 后端写回/提交
    .i_retire_en        (wb_pred_retire_en),
    .i_retire_isTaken   (wb_pred_retire_taken),
    .i_retire_target_32 (wb_pred_retire_target),

    // 预测输出 → pif
    .o_predict_taken_2  (pred_pif_taken),
    .o_predict_num_6    (pred_pif_num),
    .o_predict_target_64(pred_pif_target)
);

wire [1:0] pred_if_istaken;
wire [63:0] pred_if_target;
wire icache_top_clear_buffer;
// Icache_top — 指令缓存顶层（延时对齐时序用，保留原有连线）
Icache_top u_Icache_top (
    .clk                (aclk),
    .rstn               (aresetn),
    .clear              (pipeline_clear),

    .i_pif_en           (pif_icache_en),
    .i_addr_ok          (icache_addr_ok),
    .i_data_ok          (icache_data_ok),

    .i_preif_pc_32      (pif_icache_pc),
    .i_pc_to_if_32      (pif_icache_to_if_pc),
    .i_preif_data_7     (pif_icache_exdata),
    .i_preif_uncache_en (pif_icache_uncache_en),
    .i_inst0_valid      (pif_icache_pc_valid),
    .i_pred_isTaken_2     (pred_if_istaken),
    .i_pred_target_64     (pred_if_target),

    .o_to_icache_pc_32      (icache_axi_pc),
    .o_to_icache_uncache_en (icache_axi_uncache_en),
    .o_to_if_clear_buffer    (icache_top_clear_buffer),
    .o_to_if_pc_32          (icache_if_pc),
    .o_to_if_exdata_7       (icache_if_exdata),
    .o_to_if_pred_isTaken_2     (pif_if_istaken),
    .o_to_if_pred_target_64     (pif_if_target),
    .o_icache_valid         (icache_if_valid),
    .o_inst0_valid          (icache_if_inst0_valid)
);

// icache — 实际指令缓存（参考外部设计连线）
// 注：复位端口为 reset（高有效）；内部使用 bank_64bit / tag_tab IP
icache u_icache (
    .clk                (aclk),
    .reset              (reset),

    // cache & cpu interface
    .valid              (pif_icache_en | pif_icache_cacop_en),
    .op                 (1'b0),                    // 只读
    .size               (3'b100),                   // 字访问
    .offset             (icache_offset),
    .index              (icache_index),
    .tag                (icache_tag),
    .wdata              (32'b0),
    .wstrb              (4'b0),
    .rdata              (icache_data),             // 64 位 → if_stage.i_inst_64
    .data_ok            (icache_data_ok),
    .addr_ok            (icache_addr_ok),
    .uncache_en         (icache_axi_uncache_en),

    // cacop（来自后端 exe_top）
    .cacop_en           (pif_icache_cacop_en),
    .cacop_type         (icache_cacop_op),
    .cacop_offset       (icache_cacop_offset),
    .cacop_index        (icache_cacop_index),
    .cacop_tag          (icache_cacop_tag),

    .tlb_excp_cancel_req(1'b0),                    // 暂不用
    .icache_unbusy      (),                        // 暂不用

    // AXI interface → axi_bridge inst_*
    .rd_req             (icache_rd_req),
    .rd_type            (icache_rd_type),
    .rd_addr            (icache_rd_addr),
    .rd_rdy             (icache_rd_rdy),
    .ret_valid          (icache_ret_valid),
    .ret_last           (icache_ret_last),
    .ret_data           (icache_ret_data),
    .wr_req             (icache_wr_req),
    .wr_type            (icache_wr_type),
    .wr_addr            (icache_wr_addr),
    .wr_wstrb           (icache_wr_wstrb),
    .wr_data            (icache_wr_data),
    .wr_rdy             (icache_wr_rdy),

    // to per
    .cache_miss         ()
);

wire if_stage_valid;
// if_stage — 取指级
if_stage u_if_stage (
    .clk                (aclk),
    .rstn               (aresetn),
    .stop               (pipeline_stop),
    .clear              (pipeline_clear | icache_top_clear_buffer),

    .i_Icache_valid     (icache_if_valid),
    .i_addr_ok          (icache_addr_ok),
    .i_data_ok          (icache_data_ok),

    .i_inst_valid       (icache_if_inst0_valid),
    .i_pc_32            (icache_if_pc),
    .i_inst_64          (icache_data),
    .i_pred_isTaken_2   (pif_if_istaken),
    .i_pred_target_64   (pif_if_target),
    .i_ex_data_7        (icache_if_exdata),

    .i_int              (pif_int_sign),

    .o_if_stage_valid   (if_stage_valid),
    .o_if_stage_jump_65 ({pred_if_en, pred_if_isTaken, pred_if_inst_type_3, pred_if_pc_60}),
    .o_if_to_id_data_170(if_id_data)
);

// id_stage — 译码级
wire id_stage_valid;
id_stage u_id_stage (
    .clk                    (aclk),
    .rstn                   (aresetn),
    .stop                   (pipeline_stop),
    .clear                  (pipeline_clear),
    .i_if_to_id_valid       (if_stage_valid),

    .i_if_to_id_data_170    (if_id_data),

    .o_inst1_id_stop_sign_24(id_inst1_stop_sign),
    .o_inst1_id_tlbsrch_sign(id_inst1_tlbsrch_sign),
    .o_inst0_id_stop_sign_24(id_inst0_stop_sign),
    .o_inst0_id_tlbsrch_sign(id_inst0_tlbsrch_sign),

    .o_id_to_issue_valid    (id_stage_valid),
    .o_id_to_issue_data_460 (id_issue_data)
);

// stop_control — 流水线停顿/清空控制
stop_control u_stop_control (
    .clk                (aclk),
    .rstn               (aresetn),
    .i_backend_stop_req (backend_stop_req),
    .i_backend_clear_req(commit_flush),
    .i_ex_sign          (wb_ex_sign),
    .i_ertn_sign        (wb_ertn_sign),
    .i_cacop_sign       (wb_cacop_sign),
    .o_stop             (pipeline_stop),
    .o_clear            (pipeline_clear)
);

// =========================================================================
// 前端地址拆分 + 暂未驱动信号（后端/提交级完成后连接）
// =========================================================================

// icache 访问地址拆分（参考外部设计：offset/index 用预取指 PC，tag 用延时 PC）
assign icache_offset = {pif_icache_pc[3:2], 2'b0};
assign icache_index  = pif_icache_pc[11:4];
assign icache_tag    = icache_axi_pc[31:12];

// icache_data — 实际 Icache 的指令数据（由 icache.rdata 驱动，64 位）
wire [63:0] icache_data;

// icache cacop — 来自后端 exe 的 icache_cacop 接口
assign icache_cacop_op     = exe_icache_cacop_op;
assign icache_cacop_offset = exe_icache_cacop_va[3:0];
assign icache_cacop_index  = exe_icache_cacop_va[11:4];
assign icache_cacop_tag    = exe_icache_cacop_va[31:12];
assign pif_icache_cacop_en = exe_icache_cacop_en;

// 提交级 → 前端 控制信号（来自 commit）
assign pif_ex_sign        = ex_sign;
assign pif_ertn_sign      = ertn_sign;
assign pif_idle_sign_i    = idle_sign;
assign pif_cacop_sign     = cacop_sign;
assign pif_cacop_pc       = cacop_pc;

// 提交级 → stop_control
assign wb_ex_sign         = ex_sign;
assign wb_ertn_sign       = ertn_sign;
assign wb_cacop_sign      = cacop_sign;

// 提交级 → 分支预测器
assign wb_pred_retire_en    = feedback_en;
assign wb_pred_retire_taken = actual_taken;
assign wb_pred_retire_target= actual_target;

// debug 信号 — TODO: 连接写回级
assign debug0_wb_pc       = com_pc;
assign debug0_wb_rf_wen   = com_we;
assign debug0_wb_rf_wnum  = com_rd;
assign debug0_wb_rf_wdata = com_data;
assign debug0_wb_inst     = 32'b0;

// debug (无需实现)
assign ws_valid  = 1'b0;
assign rf_rdata  = 32'h0;

// =========================================================================
// 后端流水线 — 参考 backend.v 连接（id → dispatch → issue → exe → lsq/dcache
//              → rob → commit → rmt/grf）
// 注：csr / tlb 已与后端连接；模块名以 myCPU 实际源文件为准
// =========================================================================

// ----------------------------- 后端内部线网声明 -----------------------------

// dispatch → ROB
wire [1:0]  rob_disp_en;
wire [31:0] rob_disp_pc0, rob_disp_pc1;
wire [4:0]  rob_disp_rd0, rob_disp_rd1;
wire [1:0]  rob_disp_is_branch, rob_disp_pred_taken;
wire [31:0] rob_disp_pred_target0, rob_disp_pred_target1;
// ROB → dispatch（容量 + tail）
wire        rob_full_high, rob_almost_full_high, rob_empty_high;
wire [2:0]  rob_disp_index0, rob_disp_index1;

// dispatch → issue_top (alloc)
wire        iq_alloc_en0, iq_alloc_en1;
wire [31:0] iq_pc0, iq_pc1;
wire [82:0] iq_op0, iq_op1;
wire [ 1:0] iq_fu_type0, iq_fu_type1;
wire [ 2:0] iq_rob_idx0, iq_rob_idx1;
wire [ 4:0] iq_rd_index0, iq_rd_index1;
wire [ 4:0] iq_rj_index0, iq_rj_index1;
wire [ 4:0] iq_rk_index0, iq_rk_index1;
wire        iq_rj_ready0, iq_rj_ready1;
wire [ 2:0] iq_rj_rob0, iq_rj_rob1;
wire [31:0] iq_rj_value0, iq_rj_value1;
wire        iq_rk_ready0, iq_rk_ready1;
wire [ 2:0] iq_rk_rob0, iq_rk_rob1;
wire [31:0] iq_rk_value0, iq_rk_value1;
wire        iq_is_branch0, iq_is_branch1;
wire [31:0] iq_imm0, iq_imm1;

// dispatch → GRF 读地址 / GRF → dispatch 读数据
wire [4:0]  grf_raddr_rj0, grf_raddr_rk0, grf_raddr_rj1, grf_raddr_rk1;
wire [31:0] grf_rj_data0, grf_rk_data0, grf_rj_data1, grf_rk_data1;

// dispatch ↔ RMT
wire [4:0]  rmt_rj0, rmt_rk0, rmt_rj1, rmt_rk1;
wire        rmt_wen0, rmt_wen1;
wire [4:0]  rmt_rd0, rmt_rd1;
wire [2:0]  rmt_rob_idx0, rmt_rob_idx1;
wire        rmt_rj_ready0, rmt_rk_ready0, rmt_rj_ready1, rmt_rk_ready1;
wire [2:0]  rmt_rj_rob0, rmt_rk_rob0, rmt_rj_rob1, rmt_rk_rob1;

// issue_top → exe / exe → issue_top
wire [465:0] issue_to_exe;
wire [4:0]   fu_free;                       // {alu0, alu1, mul, div, lsu} 独热

// exe ↔ ROB / CDB
wire [153:0] exe_to_rob_wb;
wire         rob_wb_ack0, rob_wb_ack1;
wire         cdb_valid0, cdb_valid1;
wire [2:0]   cdb_rob0, cdb_rob1;
wire [31:0]  cdb_value0, cdb_value1;

// exe ↔ LSQ
wire         lsu_store_valid;
wire [31:0]  lsu_store_paddr, lsu_store_data;
wire [3:0]   lsu_store_mask;
wire [2:0]   lsu_store_size;
wire         lsu_store_is_uncache, lsu_store_is_cacop;
wire [1:0]   lsu_store_cacop_op;
wire         lsu_store_ready;
wire         lsu_load_valid;
wire [31:0]  lsu_load_paddr;
wire [2:0]   lsu_load_size;
wire         lsu_load_is_uncache;
wire         lsu_load_ready;
wire [31:0]  lsu_load_result;
wire         lsu_load_result_valid;
wire         lsu_ls_stall;

// LSQ ↔ DCache
wire         dcache_valid, dcache_op;
wire [2:0]   dcache_size;
wire [3:0]   dcache_offset;
wire [7:0]   dcache_index;
wire [19:0]  dcache_tag;
wire [31:0]  dcache_wdata;
wire [3:0]   dcache_wstrb;
wire         dcache_uncache_en, dcache_cacop_en;
wire [1:0]   dcache_cacop_mode;
wire         dcache_addr_ok;
wire [31:0]  dcache_rdata;
wire         dcache_data_ok;

// DCache → axi_bridge (data_*)
wire         data_rd_req;
wire [2:0]   data_rd_type;
wire [31:0]  data_rd_addr;
wire         data_rd_rdy;
wire         data_ret_valid, data_ret_last;
wire [31:0]  data_ret_data;
wire         data_wr_req;
wire [2:0]   data_wr_type;
wire [31:0]  data_wr_addr;
wire [3:0]   data_wr_wstrb;
wire [127:0] data_wr_data;
wire         data_wr_rdy;

// ROB → commit
wire         com_en;
wire         com_we;                    // GRF 写使能
wire [2:0]   com_idx;                   // 被提交的 ROB 条目索引
wire [31:0]  com_pc;
wire [4:0]   com_rd;
wire [31:0]  com_data;
wire         com_excp_valid;
wire [5:0]   com_excp_type;
wire [31:0]  com_excp_pc;
wire [5:0]   com_lsu_op;
wire [10:0]  com_tlb_data;
wire [1:0]     com_csr_sign;
wire [13:0]  com_csr_waddr;
wire [31:0]  com_csr_wdata, com_csr_wmask;
wire         com_ertn, com_idle;
wire         com_is_branch, com_pred_taken, com_actual_taken;
wire [31:0]  com_pred_pc, com_actual_pc;
wire         rob2rmt_com_comb;

// commit → GRF
wire         grf_we;
wire [4:0]   grf_waddr;
wire [31:0]  grf_wdata;

// commit → 前端 / 冲刷
wire         ex_sign, ertn_sign, idle_sign, cacop_sign;
wire [31:0]  cacop_pc;
wire         feedback_en, actual_taken;
wire [31:0]  actual_target;
wire         commit_flush;

// exe → icache cacop
wire         exe_icache_cacop_en;
wire [1:0]   exe_icache_cacop_op;
wire [31:0]  exe_icache_cacop_va;

// ---------- CSR/TLB 连线（commit / exe_top / rob ↔ csr / tlb） ----------
// csr 状态 → exe_top
wire [1:0]   crmd_datm;
// rob ↔ csr 读端口
wire [13:0]  csr_raddr;
wire [31:0]  csr_rdata;
// commit → csr 写端口
wire         csr_we;
wire [13:0]  csr_waddr;
wire [31:0]  csr_wdata, csr_wmask;
wire         llbit_w, llbit_set;
// commit → csr 异常
wire [31:0]  ex_pc, ex_addr;
wire [5:0]   ex_code;
wire [9:0]   subecode_9;
// commit → tlb / csr TLB 操作
wire         tlb_we, tlbfill_en;
wire         tlb_r_en;
wire         tlb_search, tlb_s_found;
wire [4:0]   tlb_s_index;
// exe_top ↔ tlb
wire         invtlb_valid;
wire [4:0]   invtlb_op;
wire [18:0]  tlb_s1_vppn;
wire         tlb_s1_va_odd;
wire [9:0]   tlb_s1_asid;
wire         tlb_s1_found;
wire [4:0]   tlb_s1_index;
wire [19:0]  tlb_s1_ppn;
wire [5:0]   tlb_s1_ps;
wire [1:0]   tlb_s1_plv, tlb_s1_mat;
wire         tlb_s1_d, tlb_s1_v;

// ----------------------------- 模块实例化 -----------------------------
wire iq_full, iq_almost_full;

// dispatch → ROB（新加：GRF写使能 / op_lsu / tlb_sign / csr 信息）
wire        rob_disp_we0, rob_disp_we1;
wire [5:0]  rob_disp_op_lsu0, rob_disp_op_lsu1;
wire        rob_disp_tlb_sign0, rob_disp_tlb_sign1;
wire [1:0]  rob_disp_is_csr;
wire [1:0]  rob_disp_csr_op0, rob_disp_csr_op1;
wire [13:0] rob_disp_csr_num0, rob_disp_csr_num1;
wire [31:0] rob_disp_csr_wdata0, rob_disp_csr_wdata1;
wire [31:0] rob_disp_csr_mask0, rob_disp_csr_mask1;
wire        rob_disp_cacop_sign0, rob_disp_cacop_sign1;

// rob → commit（cacop 指令标志）
wire        com_cacop_sign;

// commit → lsq（store 退休 / sc 是否可发送）
wire        lsq_retire, lsq_can_send;

// counter → exe_top / csr → exe_top / csr → commit
wire [63:0] cnt_data_64;
wire [31:0] timer_id;
wire        ds_llbit;
wire       rj_rob_done0       ;
wire       rk_rob_done0       ;
wire       rj_rob_done1       ;
wire       rk_rob_done1       ;
wire [2:0] o_rj_rob_index0    ;
wire [2:0] o_rk_rob_index0    ;
wire [2:0] o_rj_rob_index1    ;
wire [2:0] o_rk_rob_index1    ;
wire [31:0]i_rj_robdone_data0 ;
wire [31:0]i_rk_robdone_data0 ;
wire [31:0]i_rj_robdone_data1 ;
wire [31:0]i_rk_robdone_data1 ;
// dispatch — 分发级（参考 backend.v 的 dispatch_v2）
dispatch u_dispatch (
    .clk                        (aclk),
    .rstn                       (aresetn),
    .flush                      (commit_flush),

    // ---- ID 数据包 ----
    .i_from_id_data_460         (id_issue_data),

    // ---- 容量状态 ----
    .i_rob_idx0                 (rob_disp_index0),   // ← rob.disp_index0
    .i_rob_idx1                 (rob_disp_index1),   // ← rob.disp_index1
    .i_rob_full                 (rob_full_high),
    .i_rob_almost_full          (rob_almost_full_high),
    .i_iq_full                  (iq_full),               // ← issue_top.o_iq_full
    .i_iq_almost_full           (iq_almost_full),        // ← issue_top.o_iq_almost_full

    // ---- GRF 读数据 ----
    .i_grf_rj_data0             (grf_rj_data0),
    .i_grf_rk_data0             (grf_rk_data0),
    .i_grf_rj_data1             (grf_rj_data1),          // ← grf.o_id_rj1_data_32
    .i_grf_rk_data1             (grf_rk_data1),          // ← grf.o_id_rk1_data_32

    // ---- RMT 查询结果 ----
    .i_rmt_rj_ready0            (rmt_rj_ready0),
    .i_rmt_rk_ready0            (rmt_rk_ready0),
    .i_rmt_rj_rob0              (rmt_rj_rob0),
    .i_rmt_rk_rob0              (rmt_rk_rob0),
    .i_rmt_rj_ready1            (rmt_rj_ready1),
    .i_rmt_rk_ready1            (rmt_rk_ready1),
    .i_rmt_rj_rob1              (rmt_rj_rob1),
    .i_rmt_rk_rob1              (rmt_rk_rob1),

    // ---- 停顿信号给 ID ----
    .o_stall_id                 (backend_stop_req),

    // ---- 输出到 ROB ----
    .o_2_rob_disp_en            (rob_disp_en),
    .o_2_rob_pc0                (rob_disp_pc0),
    .o_2_rob_pc1                (rob_disp_pc1),
    .o_2_rob_rd0                (rob_disp_rd0),
    .o_2_rob_rd1                (rob_disp_rd1),
    .o_2_rob_is_branch          (rob_disp_is_branch),
    .o_2_rob_pred_taken         (rob_disp_pred_taken),
    .o_2_rob_pred_target0       (rob_disp_pred_target0),
    .o_2_rob_pred_target1       (rob_disp_pred_target1),

    // ---- 输出到 ROB（新加）----
    .o_2_rob_grf_we0            (rob_disp_we0),       // → rob.disp_we0
    .o_2_rob_grf_we1            (rob_disp_we1),       // → rob.disp_we1
    .o_2_rob_op_lsu0            (rob_disp_op_lsu0),   // → rob.disp_op_lsu0
    .o_2_rob_op_lsu1            (rob_disp_op_lsu1),   // → rob.disp_op_lsu1
    .o_2_rob_tlb_sign0          (rob_disp_tlb_sign0), // → rob.disp_tlb_sign0
    .o_2_rob_tlb_sign1          (rob_disp_tlb_sign1), // → rob.disp_tlb_sign1
    .o_2_rob_disp_is_csr        (rob_disp_is_csr),    // → rob.disp_is_csr
    .o_2_rob_csr_op0            (rob_disp_csr_op0),   // → rob.disp_csr_op0
    .o_2_rob_csr_num0           (rob_disp_csr_num0),  // → rob.disp_csr_num0
    // .o_2_rob_csr_wdata0         (rob_disp_csr_wdata0),// → rob.disp_csr_wdata0
    // .o_2_rob_csr_mask0          (rob_disp_csr_mask0), // → rob.disp_csr_mask0
    .o_2_rob_csr_op1            (rob_disp_csr_op1),   // → rob.disp_csr_op1
    .o_2_rob_csr_num1           (rob_disp_csr_num1),  // → rob.disp_csr_num1
    // .o_2_rob_csr_wdata1         (rob_disp_csr_wdata1),// → rob.disp_csr_wdata1
    // .o_2_rob_csr_mask1          (rob_disp_csr_mask1), // → rob.disp_csr_mask1
    .o_2_rob_cacop0             (rob_disp_cacop_sign0),// → rob.disp_cacop_sign0
    .o_2_rob_cacop1             (rob_disp_cacop_sign1),// → rob.disp_cacop_sign1

    // ---- 输出到 IQ (alloc) ----
    .o_2_iq_alloc_en_idx0       (iq_alloc_en0),
    .o_2_iq_pc_idx0             (iq_pc0),
    .o_2_iq_op_idx0             (iq_op0),
    .o_2_iq_fu_type_idx0        (iq_fu_type0),
    .o_2_iq_rob_idx_idx0        (iq_rob_idx0),
    .o_2_iq_rd_index_idx0       (iq_rd_index0),
    .o_2_iq_rj_index_idx0       (iq_rj_index0),
    .o_2_iq_rk_index_idx0       (iq_rk_index0),
    .o_2_iq_rj_ready_idx0       (iq_rj_ready0),
    .o_2_iq_rj_rob_idx0         (iq_rj_rob0),
    .o_2_iq_rj_value_idx0       (iq_rj_value0),
    .o_2_iq_rk_ready_idx0       (iq_rk_ready0),
    .o_2_iq_rk_rob_idx0         (iq_rk_rob0),
    .o_2_iq_rk_value_idx0       (iq_rk_value0),
    .o_2_iq_is_branch_idx0      (iq_is_branch0),
    .o_2_iq_imm_idx0            (iq_imm0),
    .o_2_iq_alloc_en_idx1       (iq_alloc_en1),
    .o_2_iq_pc_idx1             (iq_pc1),
    .o_2_iq_op_idx1             (iq_op1),
    .o_2_iq_fu_type_idx1        (iq_fu_type1),
    .o_2_iq_rob_idx_idx1        (iq_rob_idx1),
    .o_2_iq_rd_index_idx1       (iq_rd_index1),
    .o_2_iq_rj_index_idx1       (iq_rj_index1),
    .o_2_iq_rk_index_idx1       (iq_rk_index1),
    .o_2_iq_rj_ready_idx1       (iq_rj_ready1),
    .o_2_iq_rj_rob_idx1         (iq_rj_rob1),
    .o_2_iq_rj_value_idx1       (iq_rj_value1),
    .o_2_iq_rk_ready_idx1       (iq_rk_ready1),
    .o_2_iq_rk_rob_idx1         (iq_rk_rob1),
    .o_2_iq_rk_value_idx1       (iq_rk_value1),
    .o_2_iq_is_branch_idx1      (iq_is_branch1),
    .o_2_iq_imm_idx1            (iq_imm1),

    // ---- 输出给 GRF 读地址 ----
    .o_2_grf_rj_addr0           (grf_raddr_rj0),
    .o_2_grf_rk_addr0           (grf_raddr_rk0),
    .o_2_grf_rj_addr1           (grf_raddr_rj1),
    .o_2_grf_rk_addr1           (grf_raddr_rk1),

    // ---- 输出给 RMT ----
    .o_2_rmt_rj0                (rmt_rj0),
    .o_2_rmt_rk0                (rmt_rk0),
    .o_2_rmt_rj1                (rmt_rj1),
    .o_2_rmt_rk1                (rmt_rk1),
    .o_2_rmt_wen0               (rmt_wen0),
    .o_2_rmt_wen1               (rmt_wen1),
    .o_2_rmt_rd0                (rmt_rd0),
    .o_2_rmt_rd1                (rmt_rd1),
    .o_2_rmt_rob_idx0           (rmt_rob_idx0),
    .o_2_rmt_rob_idx1           (rmt_rob_idx1),
    .i_from_id_valid            (id_stage_valid),
    .rj_rob_done0      (rj_rob_done0      ),
    .rk_rob_done0      (rk_rob_done0      ),
    .rj_rob_done1      (rj_rob_done1      ),
    .rk_rob_done1      (rk_rob_done1      ),
    .o_rj_rob_index0   (o_rj_rob_index0   ),
    .o_rk_rob_index0   (o_rk_rob_index0   ),
    .o_rj_rob_index1   (o_rj_rob_index1   ),
    .o_rk_rob_index1   (o_rk_rob_index1   ),
    .i_rj_robdone_data0(i_rj_robdone_data0),
    .i_rk_robdone_data0(i_rk_robdone_data0),
    .i_rj_robdone_data1(i_rj_robdone_data1),
    .i_rk_robdone_data1(i_rk_robdone_data1) ,
    .raw_com_data        (com_data),
    .raw_com_rd         (com_rd & {5{com_we}}) ,
    //d0级数据旁路
    .disp_2_exe_rob_idx_rj0(disp_2_exe_rob_idx_rj0),
    .disp_2_exe_rob_idx_rk0(disp_2_exe_rob_idx_rk0),
    .disp_2_exe_rob_idx_rj1(disp_2_exe_rob_idx_rj1),
    .disp_2_exe_rob_idx_rk1(disp_2_exe_rob_idx_rk1),
    .exe_rj0_data          (exe_rj0_data          ),
    .exe_rk0_data          (exe_rk0_data          ),
    .exe_rj1_data          (exe_rj1_data          ),
    .exe_rk1_data          (exe_rk1_data          ),
    .exe_rj0_ready         (exe_rj0_ready         ),
    .exe_rk0_ready         (exe_rk0_ready         ),
    .exe_rj1_ready         (exe_rj1_ready         ),
    .exe_rk1_ready         (exe_rk1_ready         ),
    //d1级数据旁路
    .i_cdb_valid0           (cdb_valid0),       
    .i_cdb_rob_idx0         (cdb_rob0),           
    .i_cdb_value0           (cdb_value0),               
    .i_cdb_valid1           (cdb_valid1),       
    .i_cdb_rob_idx1         (cdb_rob1),       
    .i_cdb_value1           (cdb_value1)
);

// issue_top — 发射级（内部含 IQ）
issue_top u_issue (
    .clk                    (aclk),
    .rstn                   (aresetn),
    .flush                  (commit_flush),

    // inst0
    .i_alloc_en_idx0        (iq_alloc_en0),
    .i_pc_idx0              (iq_pc0),
    .i_op_idx0              (iq_op0),
    .i_fu_type_idx0         (iq_fu_type0),
    .i_rob_idx_idx0         (iq_rob_idx0),
    .i_id_rj_ready_idx0     (iq_rj_ready0),
    .i_id_rk_ready_idx0     (iq_rk_ready0),
    .i_rob_rj_idx0          (iq_rj_rob0),
    .i_rob_rk_idx0          (iq_rk_rob0),
    .i_rj_value_idx0        (iq_rj_value0),
    .i_rk_value_idx0        (iq_rk_value0),
    .i_is_branch_idx0       (iq_is_branch0),
    .i_imm0                 (iq_imm0),
    .i_rj_index_idx0        (iq_rj_index0),
    .i_rk_index_idx0        (iq_rk_index0),
    .i_rd_index_idx0        (iq_rd_index0),
    // inst1
    .i_alloc_en_idx1        (iq_alloc_en1),
    .i_pc_idx1              (iq_pc1),
    .i_op_idx1              (iq_op1),
    .i_fu_type_idx1         (iq_fu_type1),
    .i_rob_idx_idx1         (iq_rob_idx1),
    .i_id_rj_ready_idx1     (iq_rj_ready1),
    .i_id_rk_ready_idx1     (iq_rk_ready1),
    .i_rob_rj_idx1          (iq_rj_rob1),
    .i_rob_rk_idx1          (iq_rk_rob1),
    .i_rj_value_idx1        (iq_rj_value1),
    .i_rk_value_idx1        (iq_rk_value1),
    .i_is_branch_idx1       (iq_is_branch1),
    .i_imm1                 (iq_imm1),
    .i_rj_index_idx1        (iq_rj_index1),
    .i_rk_index_idx1        (iq_rk_index1),
    .i_rd_index_idx1        (iq_rd_index1),
    // CDB 写回
    .i_cdb_valid_idx0       (cdb_valid0),
    .i_cdb_valid_idx1       (cdb_valid1),
    .i_cdb_rob_idx_idx0     (cdb_rob0),
    .i_cdb_rob_idx_idx1     (cdb_rob1),
    .i_cdb_value_idx0       (cdb_value0),
    .i_cdb_value_idx1       (cdb_value1),
    // 输出到 exe
    .o_2_exe_466            (issue_to_exe),
    // 执行单元就绪（o_fu_free: {alu0,alu1,mul,div,lsu} 独热）
    .i_exe_alu0_ready       (fu_free[4]),
    .i_exe_alu1_ready       (fu_free[3]),
    .i_exe_div_ready        (fu_free[1]),
    .i_exe_mul_ready        (fu_free[2]),
    .i_exe_lsu_ready        (fu_free[0]),

    .o_iq_full              (iq_full),
    .o_iq_almost_full       (iq_almost_full)
);
//d0级数据旁路
wire [2:0]disp_2_exe_rob_idx_rj0 ;
wire [2:0]disp_2_exe_rob_idx_rk0 ;
wire [2:0]disp_2_exe_rob_idx_rj1 ;
wire [2:0]disp_2_exe_rob_idx_rk1 ;
wire [31:0]exe_rj0_data ;         
wire [31:0]exe_rk0_data ;         
wire [31:0]exe_rj1_data ;         
wire [31:0]exe_rk1_data ;         
wire exe_rj0_ready;         
wire exe_rk0_ready;         
wire exe_rj1_ready;         
wire exe_rk1_ready;         

//d1级旁路
// CDB 线网声明
// wire        cdb_valid0, cdb_valid1;
// wire [2:0]  cdb_rob_idx0, cdb_rob_idx1;
// wire [31:0] cdb_value0, cdb_value1;


// exe_top — 执行级（内部含 ALU/MUL/DIV/LSU）
exe_top u_exe (
    .clk                    (aclk),
    .rstn                   (aresetn),
    .flush                  (commit_flush),
    .i_from_issue_466       (issue_to_exe),
    .i_cnt_data_64          (cnt_data_64),    // ← counter.o_cnt_data_64（rdcntvl/vh）
    .i_cnt_id               (timer_id),       // ← csr.timer_id（rdcntid）
    .o_fu_free              (fu_free),
    .o_2_rob_wb             (exe_to_rob_wb),
    .o_cdb_valid0           (cdb_valid0),
    .o_cdb_rob0             (cdb_rob0),
    .o_cdb_value0           (cdb_value0),
    .o_cdb_valid1           (cdb_valid1),
    .o_cdb_rob1             (cdb_rob1),
    .o_cdb_value1           (cdb_value1),
    .i_rob_wb_ack0          (rob_wb_ack0),
    .i_rob_wb_ack1          (rob_wb_ack1),

    // CSR 状态 — 连接 CSR
    .crmd_da                (csr_crmd_da),
    .crmd_pg                (csr_crmd_pg),
    .crmd_datm              (crmd_datm),
    .crmd_plv               (csr_crmd_plv),
    .csr_tlbehi_vppn        (tlb_w_vppn),
    .csr_asid_asid          (tlb_w_asid),
    .dmw0_plv0              (csr_dmw0_plv0),
    .dmw0_plv3              (csr_dmw0_plv3),
    .dmw0_mat               (csr_dmw0_mat),
    .dmw0_pseg              (csr_dmw0_pseg),
    .dmw0_vseg              (csr_dmw0_vseg),
    .dmw1_plv0              (csr_dmw1_plv0),
    .dmw1_plv3              (csr_dmw1_plv3),
    .dmw1_mat               (csr_dmw1_mat),
    .dmw1_pseg              (csr_dmw1_pseg),
    .dmw1_vseg              (csr_dmw1_vseg),

    // TLB 接口 — 连接 tlb
    .invtlb_valid           (invtlb_valid),
    .invtlb_op              (invtlb_op),
    .invtlb_vppn            (),            // tlb 无对应端口
    .invtlb_asid            (),            // tlb 无对应端口
    .tlb_s1_vppn            (tlb_s1_vppn),
    .tlb_s1_va_odd          (tlb_s1_va_odd),
    .tlb_s1_asid            (tlb_s1_asid),
    .tlb_s1_found           (tlb_s1_found),
    .tlb_s1_index           (tlb_s1_index),
    .tlb_s1_ppn             (tlb_s1_ppn),
    .tlb_s1_ps              (tlb_s1_ps),
    .tlb_s1_plv             (tlb_s1_plv),
    .tlb_s1_mat             (tlb_s1_mat),
    .tlb_s1_d               (tlb_s1_d),
    .tlb_s1_v               (tlb_s1_v),

    // LSQ 接口
    .store_valid            (lsu_store_valid),
    .store_paddr            (lsu_store_paddr),
    .store_data             (lsu_store_data),
    .store_mask             (lsu_store_mask),
    .store_size             (lsu_store_size),
    .store_is_uncache       (lsu_store_is_uncache),
    .store_is_cacop         (lsu_store_is_cacop),
    .store_cacop_op         (lsu_store_cacop_op),
    .store_ready            (lsu_store_ready),
    .load_valid             (lsu_load_valid),
    .load_paddr             (lsu_load_paddr),
    .load_size              (lsu_load_size),
    .load_is_uncache        (lsu_load_is_uncache),
    .load_ready             (lsu_load_ready),
    .load_result            (lsu_load_result),
    .load_result_valid      (lsu_load_result_valid),
    .ls_stall_i             (lsu_ls_stall),

    // icache cacop → 前端
    .icache_cacop_en        (exe_icache_cacop_en),
    .icache_cacop_op        (exe_icache_cacop_op),
    .icache_cacop_va        (exe_icache_cacop_va),
    // preld — 暂不使用
    .preld_en               (),
    .preld_hint             (),

    .disp_rob_idx0_rj   (disp_2_exe_rob_idx_rj0),
    .disp_rob_idx0_rk   (disp_2_exe_rob_idx_rk0),
    .disp_rob_idx1_rj   (disp_2_exe_rob_idx_rj1),
    .disp_rob_idx1_rk   (disp_2_exe_rob_idx_rk1),
    .exe_2_disp_rjdata0 (exe_rj0_data          ),
    .exe_2_disp_rkdata0 (exe_rk0_data          ),
    .exe_2_disp_rjdata1 (exe_rj1_data          ),
    .exe_2_disp_rkdata1 (exe_rk1_data          ),    
    .exe_2_rj0_ready    (exe_rj0_ready         ),       
    .exe_2_rk0_ready    (exe_rk0_ready         ),       
    .exe_2_rj1_ready    (exe_rj1_ready         ),       
    .exe_2_rk1_ready    (exe_rk1_ready         )



);

// lsq — 访存队列
lsq #(
    .DEPTH       (8),
    .ADDR_WIDTH  (32),
    .DATA_WIDTH  (32),
    .PTR_WIDTH   (3)
) u_lsq (
    .clk                    (aclk),
    .rstn                   (aresetn),

    .store_valid_i          (lsu_store_valid),
    .store_paddr_i          (lsu_store_paddr),
    .store_data_i           (lsu_store_data),
    .store_mask_i           (lsu_store_mask),
    .store_size_i           (lsu_store_size),
    .store_is_uncache_i     (lsu_store_is_uncache),
    .store_is_cacop_i       (lsu_store_is_cacop),
    .store_cacop_op_i       (lsu_store_cacop_op),
    .store_ready_o          (lsu_store_ready),

    .load_valid_i           (lsu_load_valid),
    .load_paddr_i           (lsu_load_paddr),
    .load_size_i            (lsu_load_size),
    .load_is_uncache_i      (lsu_load_is_uncache),
    .dcache_rdata_i         (dcache_rdata),
    .dcache_data_ok_i       (dcache_data_ok),
    .load_result_o          (lsu_load_result),
    .load_result_valid_o    (lsu_load_result_valid),
    .load_ready_o           (lsu_load_ready),

    .retire_valid_i         (lsq_retire),     // ← commit.o_lsq_retire（store 退休）
    .can_sent_dcache_i      (lsq_can_send),   // ← commit.o_lsq_can_send（sc 是否可发送）
    .flush_valid_i          (commit_flush),

    .dcache_valid_o         (dcache_valid),
    .dcache_op_o            (dcache_op),
    .dcache_size_o          (dcache_size),
    .dcache_offset_o        (dcache_offset),
    .dcache_index_o         (dcache_index),
    .dcache_tag_o           (dcache_tag),
    .dcache_wdata_o         (dcache_wdata),
    .dcache_wstrb_o         (dcache_wstrb),
    .dcache_uncache_en_o    (dcache_uncache_en),
    .dcache_cacop_en_o      (dcache_cacop_en),
    .dcache_cacop_mode_o    (dcache_cacop_mode),
    .dcache_addr_ok_i       (dcache_addr_ok),

    .ls_stall_o             (lsu_ls_stall),
    .sq_full_o              (),
    .sq_empty_o             ()
);

// dcache — 数据缓存（复位 reset 高有效）
dcache u_dcache (
    .clk                    (aclk),
    .reset                  (reset),

    .valid                  (dcache_valid),
    .op                     (dcache_op),
    .size                   (dcache_size),
    .offset                 (dcache_offset),
    .index                  (dcache_index),
    .tag                    (dcache_tag),
    .wdata                  (dcache_wdata),
    .wstrb                  (dcache_wstrb),
    .rdata                  (dcache_rdata),
    .data_ok                (dcache_data_ok),
    .addr_ok                (dcache_addr_ok),
    .uncache_en             (dcache_uncache_en),
    .dcacop_op_en           (dcache_cacop_en),
    .cacop_op_mode          (dcache_cacop_mode),
    .preld_hint             (5'b0),        // TODO
    .preld_en               (1'b0),        // TODO
    .tlb_excp_cancel_req    (1'b0),
    .sc_cancel_req          (1'b0),
    .dcache_empty           (),

    // AXI → axi_bridge data_*
    .rd_req                 (data_rd_req),
    .rd_type                (data_rd_type),
    .rd_addr                (data_rd_addr),
    .rd_rdy                 (data_rd_rdy),
    .ret_valid              (data_ret_valid),
    .ret_last               (data_ret_last),
    .ret_data               (data_ret_data),
    .wr_req                 (data_wr_req),
    .wr_type                (data_wr_type),
    .wr_addr                (data_wr_addr),
    .wr_wstrb               (data_wr_wstrb),
    .wr_data                (data_wr_data),
    .wr_rdy                 (data_wr_rdy),
    .cache_miss             ()
);

// rob — 重排序缓冲（rob_v5）
wire [2:0] rob2rmt_robidx_comb ;
wire [4:0] rob2rmt_rd_comb ;
wire [31:0] com_excp_addr;
rob u_rob (
    .clk                    (aclk),
    .rstn                   (aresetn),

    // ---- 分发端口（来自 dispatch）----
    .disp_en                (rob_disp_en),
    .disp_pc0               (rob_disp_pc0),
    .disp_pc1               (rob_disp_pc1),
    .disp_rd0               (rob_disp_rd0),
    .disp_rd1               (rob_disp_rd1),
    .disp_index0            (rob_disp_index0),
    .disp_index1            (rob_disp_index1),
    .rob_full_high          (rob_full_high),
    .rob_almost_full_high   (rob_almost_full_high),
    .rob_empty_high         (rob_empty_high),
    .disp_we0               (rob_disp_we0),       // ← dispatch.o_2_rob_grf_we0
    .disp_we1               (rob_disp_we1),       // ← dispatch.o_2_rob_grf_we1
    .disp_op_lsu0           (rob_disp_op_lsu0),   // ← dispatch.o_2_rob_op_lsu0
    .disp_op_lsu1           (rob_disp_op_lsu1),   // ← dispatch.o_2_rob_op_lsu1
    .disp_tlb_sign0         (rob_disp_tlb_sign0), // ← dispatch.o_2_rob_tlb_sign0
    .disp_tlb_sign1         (rob_disp_tlb_sign1), // ← dispatch.o_2_rob_tlb_sign1
    .disp_cacop_sign0       (rob_disp_cacop_sign0), // ← dispatch.o_2_rob_cacop_sign0
    .disp_cacop_sign1       (rob_disp_cacop_sign1), // ← dispatch.o_2_rob_cacop_sign1
    .disp_is_csr            (rob_disp_is_csr),    // ← dispatch.o_2_rob_disp_is_csr
    .disp_csr_op0           (rob_disp_csr_op0),   // ← dispatch.o_2_rob_csr_op0
    .disp_csr_num0          (rob_disp_csr_num0),  // ← dispatch.o_2_rob_csr_num0
    // .disp_csr_wdata0        (rob_disp_csr_wdata0),// ← dispatch.o_2_rob_csr_wdata0
    // .disp_csr_mask0         (rob_disp_csr_mask0), // ← dispatch.o_2_rob_csr_mask0
    .disp_csr_op1           (rob_disp_csr_op1),   // ← dispatch.o_2_rob_csr_op1
    .disp_csr_num1          (rob_disp_csr_num1),  // ← dispatch.o_2_rob_csr_num1
    // .disp_csr_wdata1        (rob_disp_csr_wdata1),// ← dispatch.o_2_rob_csr_wdata1
    // .disp_csr_mask1         (rob_disp_csr_mask1), // ← dispatch.o_2_rob_csr_mask1
    .disp_is_branch         (rob_disp_is_branch),
    .disp_pred_taken        (rob_disp_pred_taken),
    .disp_pred_target0      (rob_disp_pred_target0),
    .disp_pred_target1      (rob_disp_pred_target1),

    // ---- 写回端口（打包，来自 exe）----
    .wb_pkg                 (exe_to_rob_wb),
    .wb_ack0                (rob_wb_ack0),
    .wb_ack1                (rob_wb_ack1),

    // ---- 提交端口（→ commit）----
    .com_en                 (com_en),
    .com_idx                (com_idx),
    .com_we                 (com_we),
    .com_pc                 (com_pc),
    .com_rd                 (com_rd),
    .com_data               (com_data),
    .com_excp_valid         (com_excp_valid),
    .com_excp_type          (com_excp_type),
    .com_excp_pc            (com_excp_pc),
    .com_excp_addr          (com_excp_addr),
    .com_lsu_op             (com_lsu_op),
    .com_tlb_data           (com_tlb_data),

    // ---- CSR 相关 — 连接 csr ----
    .com_csr_raddr          (csr_raddr),
    .com_csr_rdata          (csr_rdata),
    .com_csr_sign             (com_csr_sign),
    .com_csr_waddr          (com_csr_waddr),
    .com_csr_wdata          (com_csr_wdata),
    .com_csr_wmask          (com_csr_wmask),
    .com_cacop_sign         (com_cacop_sign),   // → commit.i_cacop_inst

    // ---- ERTN / IDLE ----
    .com_ertn               (com_ertn),
    .com_idle               (com_idle),

    // ---- 分支预测信息 ----
    .com_is_branch          (com_is_branch),
    .com_pred_taken         (com_pred_taken),
    .com_actual_taken       (com_actual_taken),
    .com_pred_pc            (com_pred_pc),
    .com_actual_pc          (com_actual_pc),

    // ---- 冲刷 ----
    .rob_flush              (commit_flush),
    .rob2rmt_com_comb       (rob2rmt_com_comb),
    .rob2rmt_robidx_comb    (rob2rmt_robidx_comb),
    .rob2rmt_rd_comb        (rob2rmt_rd_comb) ,

    //raw-exe-iq
    .rj_rob_done0               (rj_rob_done0),
    .rk_rob_done0               (rk_rob_done0),
    .rj_rob_done1               (rj_rob_done1),
    .rk_rob_done1               (rk_rob_done1),    
    .disp_rj_need_rob_index0    (o_rj_rob_index0),
    .rob_done_rjdata0           (i_rj_robdone_data0),    
    .disp_rk_need_rob_index0    (o_rk_rob_index0),        
    .rob_done_rkdata0           (i_rk_robdone_data0),    
    .disp_rj_need_rob_index1    (o_rj_rob_index1),    
    .rob_done_rjdata1           (i_rj_robdone_data1),    
    .disp_rk_need_rob_index1    (o_rk_rob_index1),
    .rob_done_rkdata1           (i_rk_robdone_data1)        
    );

// commit — 提交级
commit u_commit (
    .clk                    (aclk),
    .rstn                   (aresetn),

    // ---- 来自 ROB ----
    .i_valid                (com_en),
    .i_pc                   (com_pc),
    .i_rd                   (com_rd),
    .i_grf_we               (com_we),
    .i_grf_wdata            (com_data),
    .i_csr_sign               (com_csr_sign),
    .i_csr_waddr            (com_csr_waddr),
    .i_csr_wdata            (com_csr_wdata),
    .i_csr_wmask            (com_csr_wmask),
    .i_ex_sign              (com_excp_valid),
    .i_ex_pc                (com_excp_pc),   
    .i_ex_addr              (com_excp_addr),
    .i_ex_code              (com_excp_type),
    .i_tlb_data             (com_tlb_data),
    .i_ertn_sign            (com_ertn),
    .i_idle_sign            (com_idle),
    .i_llbit                (ds_llbit),     // ← csr.ds_llbit（SC 指令写回/判断用）
    .i_cacop_inst           (com_cacop_sign), // ← rob.com_cacop_sign（cacop 指令冲刷）
    .i_op_lsu               (com_lsu_op), // commit.i_op_lsu[5:0]
    .i_is_branch            (com_is_branch),
    .i_pred_taken           (com_pred_taken),
    .i_actual_taken         (com_actual_taken),
    .i_pred_target          (com_pred_pc),
    .i_actual_target        (com_actual_pc),

    // ---- 写回 GRF ----
    .o_grf_we               (grf_we),
    .o_grf_waddr            (grf_waddr),
    .o_grf_wdata            (grf_wdata),

    // ---- 写回 CSR ----
    .o_csr_we               (csr_we),
    .o_csr_waddr            (csr_waddr),
    .o_csr_wdata            (csr_wdata),
    .o_csr_wmask            (csr_wmask),
    .o_llbit                (llbit_w),
    .o_llbit_set            (llbit_set),

    // ---- 异常（→ 前端 / CSR）----
    .o_ex_sign              (ex_sign),
    .o_ex_pc                (ex_pc),
    .o_ex_addr              (ex_addr),
    .o_ex_code              (ex_code),
    .o_subecode_9           (subecode_9),

    // ---- TLB 操作（→ tlb / csr）----
    .o_tlb_we               (tlb_we),
    .o_tlb_rd               (tlb_r_en),
    .o_tlbfill_en           (tlbfill_en),
    .o_tlb_search           (tlb_search),
    .o_tlb_s_found          (tlb_s_found),
    .o_tlb_s_index          (tlb_s_index),

    // ---- 控制信号（→ 前端）----
    .o_ertn_sign            (ertn_sign),
    .o_idle_sign            (idle_sign),
    .o_cacop_sign           (cacop_sign),
    .o_cacop_pc             (cacop_pc),

    // ---- LSQ 退休/发送控制（→ lsq）----
    .o_lsq_retire           (lsq_retire),   // → lsq.retire_valid_i
    .o_lsq_can_send         (lsq_can_send), // → lsq.can_sent_dcache_i

    // ---- 分支预测反馈（→ 前端）----
    .o_feedback_en          (feedback_en),
    .o_actual_taken         (actual_taken),
    .o_actual_target        (actual_target),
    .o_flush                (commit_flush)
);

// RMT — 寄存器重命名映射表
RMT u_rmt (
    .clk                (aclk),
    .rstn               (aresetn),
    .flush              (commit_flush),

    .i_rj_idx0          (rmt_rj0),
    .i_rk_idx0          (rmt_rk0),
    .i_rd_idx0          (rmt_rd0),
    .i_rob_entry_idx0   (rmt_rob_idx0),
    .o_rj_ready_idx0    (rmt_rj_ready0),
    .o_rk_ready_idx0    (rmt_rk_ready0),
    .o_rj_rob_idx0      (rmt_rj_rob0),
    .o_rk_rob_idx0      (rmt_rk_rob0),

    .i_rj_idx1          (rmt_rj1),
    .i_rk_idx1          (rmt_rk1),
    .i_rd_idx1          (rmt_rd1),
    .i_rob_entry_idx1   (rmt_rob_idx1),
    .o_rj_ready_idx1    (rmt_rj_ready1),
    .o_rk_ready_idx1    (rmt_rk_ready1),
    .o_rj_rob_idx1      (rmt_rj_rob1),
    .o_rk_rob_idx1      (rmt_rk_rob1),

    .i_wen_idx0         (rmt_wen0),
    .i_wen_idx1         (rmt_wen1),
    .i_com_rd           (rob2rmt_rd_comb),
    .i_com_rob_idx      (rob2rmt_robidx_comb),
    .i_com_en_comb      (rob2rmt_com_comb)
    
);

// grf — 通用寄存器堆（4 读端口双发射）
grf u_grf (
    .clk                (aclk),
    .rstn               (aresetn),

    // inst0 读端口
    .i_id_rj0_index_5    (grf_raddr_rj0),
    .i_id_rk0_index_5    (grf_raddr_rk0),
    .i_id_rj1_index_5    (grf_raddr_rj1),
    .i_id_rk1_index_5    (grf_raddr_rk1),
    .o_id_rj0_data_32    (grf_rj_data0),
    .o_id_rk0_data_32    (grf_rk_data0),
    .o_id_rj1_data_32    (grf_rj_data1),
    .o_id_rk1_data_32    (grf_rk_data1),


    // commit 写端口
    .i_com_en           (grf_we),
    .i_com_addr_5       (grf_waddr),
    .i_com_data_32      (grf_wdata)
);

endmodule