`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 模块: rob_v5
// 描述: 带有打包写回、ERTN/IDLE 提交支持、完善的分支预测更新逻辑的 ROB
// 拓展了csr的数据端口
//////////////////////////////////////////////////////////////////////////////////
module rob(
    input  wire        clk,
    input  wire        rstn,

    // ---- 分发端口 ----
    input  wire [1:0]  disp_en,
    input  wire [31:0] disp_pc0,
    input  wire [31:0] disp_pc1,
    input  wire        disp_we0 ,
    input  wire        disp_we1 ,
    input  wire [4:0]  disp_rd0,
    input  wire [4:0]  disp_rd1,
    output wire [2:0]  disp_index0,
    output wire [2:0]  disp_index1,
    output wire        rob_full_high,
    output wire        rob_almost_full_high,
    output wire        rob_empty_high,
    // output wire        rob_tail  ,

    input  wire [1:0]  disp_is_branch,
    input  wire [1:0]  disp_pred_taken,
    input  wire [31:0] disp_pred_target0,
    input  wire [31:0] disp_pred_target1,
    input  wire [5:0]  disp_op_lsu0 , disp_op_lsu1 ,
    input  wire        disp_tlb_sign0 , disp_tlb_sign1 ,
    input  wire        disp_cacop_sign0 , disp_cacop_sign1,

    //在分发阶段写入csr需要的操作数
    input  wire [1:0]  disp_is_csr,      // 对应 disp_en[1:0]
    input  wire [1:0]  disp_csr_op0,     // inst0 的 csr_op
    input  wire [13:0] disp_csr_num0,    // inst0 的 csr_num
    // input  wire [31:0] disp_csr_wdata0,  // inst0 的 csr_wdata (rd 旧值)
    // input  wire [31:0] disp_csr_mask0,   // inst0 的 csr_mask (rj 掩码)
    input  wire [1:0]  disp_csr_op1,     // inst1 的 ...
    input  wire [13:0] disp_csr_num1,
    // input  wire [31:0] disp_csr_wdata1,
    // input  wire [31:0] disp_csr_mask1 ,

    // ---- 写回端口（打包） ----
    input  wire [153:0] wb_pkg,
    output wire          wb_ack0,
    output wire          wb_ack1,

    // ---- 提交端口 ----
    output reg          com_en,
    output reg  [31:0]  com_pc,
    output reg  [4:0]   com_rd,
    output reg  [31:0]  com_data,   //这个端口存放的是更改grf的数据，包括从csr读到的数据
    output reg          com_we ,
    output reg  [2:0]   com_idx , //清空rmt索引的时候

    output reg          com_excp_valid,
    output reg  [5:0]   com_excp_type,
    output reg  [31:0]  com_excp_pc,
    output reg  [31:0]  com_excp_addr ,
    output reg  [5:0]   com_lsu_op ,
    output reg  [10:0]  com_tlb_data ,
    output reg          com_cacop_sign ,

    
    //csr相关接口
    output wire [13:0] com_csr_raddr,     // 读地址
    input  wire [31:0] com_csr_rdata,     // 读数据（组合逻辑）
    output reg   [1:0] com_csr_sign,        // 写使能
    output reg  [13:0] com_csr_waddr,
    output reg  [31:0] com_csr_wdata,      //rd
    output reg  [31:0] com_csr_wmask,       //rj

    // ERTN / IDLE 提交信号
    output reg          com_ertn,
    output reg          com_idle,
    // output reg  [31:0]  com_idle_pc,   // IDLE 指令的 PC+4（供中断唤醒时使用）

    //将分支预测的信息统一放到提交阶段处理，rob只输出分支预测的信息
    output reg          com_is_branch       ,
    output reg          com_pred_taken       ,
    output reg          com_actual_taken    ,
    output reg [31:0]   com_pred_pc          ,
    output reg [31:0]   com_actual_pc       ,

    // 分支预测器更新
    // output reg          bp_update_valid,
    // output reg  [31:0]  bp_update_pc,
    // output reg          bp_update_taken,
    // output reg  [31:0]  bp_update_target,

    // output reg          rob_flush,
    //冲刷信号统一在提交流水级完成，并且传到rob中
    input  wire         rob_flush ,
    output wire         rob2rmt_com_comb, //使能
    output wire   [2:0] rob2rmt_robidx_comb,//rob索引
    output wire   [4:0] rob2rmt_rd_comb, //rd寄存器索引

    output wire  rj_rob_done0,
    output wire  rk_rob_done0,
    output wire  rj_rob_done1,
    output wire  rk_rob_done1,
    input [2:0] disp_rj_need_rob_index0 , 
    output[31:0]rob_done_rjdata0 ,
    input [2:0] disp_rk_need_rob_index0 , 
    output[31:0]rob_done_rkdata0 ,
    input [2:0] disp_rj_need_rob_index1 , 
    output[31:0]rob_done_rjdata1 ,
    input [2:0] disp_rk_need_rob_index1 , 
    output[31:0]rob_done_rkdata1  
);

    parameter ROB_DEPTH = 8;

    // ---------- 拆解写回包 ----------
    wire        wb0_valid  = wb_pkg[76];
    wire [2:0]  wb0_idx    = wb_pkg[75:73];
    wire [31:0] wb0_data   = wb_pkg[72:41];
    wire        wb0_exc    = wb_pkg[40];
    wire [5:0]  wb0_ecode  = wb_pkg[39:34];
    wire        wb0_btaken = wb_pkg[33];
    wire [31:0] wb0_btarget= wb_pkg[32:1];

    wire        wb1_valid  = wb_pkg[153];
    wire [2:0]  wb1_idx    = wb_pkg[152:150];
    wire [31:0] wb1_data   = wb_pkg[149:118];
    wire        wb1_exc    = wb_pkg[117];
    wire [5:0]  wb1_ecode  = wb_pkg[116:111];
    wire        wb1_btaken = wb_pkg[110];
    wire [31:0] wb1_btarget= wb_pkg[109:78];

    // ---------- ROB 存储体 ----------
    reg         valid         [0:ROB_DEPTH-1];
    reg         done          [0:ROB_DEPTH-1];
    reg [31:0]  pc            [0:ROB_DEPTH-1];
    reg         we            [0:ROB_DEPTH-1]; // 新增的写使能信号
    reg [4:0]   rd            [0:ROB_DEPTH-1];
    reg [31:0]  data          [0:ROB_DEPTH-1];
    reg         excp_valid    [0:ROB_DEPTH-1];
    reg [5:0]   excp_type     [0:ROB_DEPTH-1];
    reg         is_branch     [0:ROB_DEPTH-1];
    reg         pred_taken    [0:ROB_DEPTH-1];
    reg [31:0]  pred_target   [0:ROB_DEPTH-1];
    reg         actual_taken  [0:ROB_DEPTH-1];
    reg [31:0]  actual_target [0:ROB_DEPTH-1];
    //新添加的数据:dispatch阶段写入
    reg [5 :0] op_lsu         [0:ROB_DEPTH-1]; //sc判断逻辑：oplsu[5] = 1 &&  oplsu[3] =0
    reg        tlb_sign       [0:ROB_DEPTH-1];
    reg        cacop_sign     [0:ROB_DEPTH-1] ;
    //csr相关的数据
    reg        is_csr         [0:ROB_DEPTH-1];
    reg [1:0]  csr_op           [0:ROB_DEPTH-1]; //csr指令的类型
    reg [13:0] csr_num          [0:ROB_DEPTH-1] ;
    reg [31:0] csr_wdata        [0:ROB_DEPTH-1] ; //来源是rd中的数据，从分发阶段获得
    reg [31:0] csr_mask         [0:ROB_DEPTH-1] ; //来源是rj中的数据，从分发阶段获得

    // ---------- 指针 ----------
    reg [2:0] head;
    reg [2:0] tail;
    wire [3:0] count;
    reg [3:0] count_disp;
    reg [3:0] count_com;
     
    assign count = count_disp - count_com;
    assign rob_full_high = (count >= ROB_DEPTH);
    assign rob_almost_full_high = (count >= (ROB_DEPTH - 1));
    assign rob_empty_high = (count == 4'd0);
    assign disp_index0 = tail;
    assign disp_index1 = disp_en[0] ? (tail + 3'd1) % ROB_DEPTH : tail;
    //将rob内部的tail指针输出
    // assign rob_tail = tail ;

    //写回rob的应答信号：
    assign wb_ack0 = wb0_valid && valid[wb0_idx] && !done[wb0_idx];
    assign wb_ack1 = wb1_valid && valid[wb1_idx] && !done[wb1_idx];

    // // ---------- 分配组合逻辑（支持 NOP 过滤后的非嵌套分配）----------
    // wire        s0_alloc      = disp_en[0] && !rob_full_high;
    // wire [4:0]  count_after_s0 = count + {4'd0, s0_alloc};
    // wire        s1_alloc      = disp_en[1] && (count_after_s0 < ROB_DEPTH);
    // wire [2:0]  s0_idx        = tail;
    // wire [2:0]  s1_idx        = s0_alloc ? (tail + 3'd1) % ROB_DEPTH : tail;
    // wire [2:0]  tail_next     = (s0_alloc && s1_alloc) ? (tail + 3'd2) % ROB_DEPTH :
    //                           (s0_alloc || s1_alloc) ? (tail + 3'd1) % ROB_DEPTH : tail;
    // wire [3:0]  count_incr    = {3'd0, s0_alloc} + {3'd0, s1_alloc};

     //csr的读数据地址
    assign com_csr_raddr = (is_csr[head] && done[head]) ? csr_num[head] : 14'd0; //这个done信号从alu中写回的时候就能被置为1了


    integer i;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            tail           <= 3'd0;
            head           <= 3'd0;
            count_disp     <= 4'd0;
            count_com      <= 4'd0;
            // wb_ack0        <= 1'b0;
            // wb_ack1        <= 1'b0;

            com_en         <= 1'b0;
            com_pc         <= 32'd0;
            com_rd         <= 5'd0;
            com_data       <= 32'd0;
            com_we         <= 1'b0 ;
            com_idx        <= 1'b0 ;
            com_excp_valid <= 1'b0;
            com_excp_type  <= 6'd0;
            com_excp_pc    <= 32'd0;
            com_lsu_op      <= 6'b0 ;
            com_tlb_data    <= 11'b0 ;
            com_cacop_sign  <= 1'b0 ;
            com_csr_waddr     <= 0 ;
            com_csr_wdata     <= 0 ;
            com_csr_wmask     <= 0 ;
            com_ertn       <= 1'b0;
            com_idle       <= 1'b0;
            // com_idle_pc    <= 32'd0;
            com_is_branch     <= 0 ;
            com_pred_taken     <= 0 ;
            com_actual_taken  <= 0 ;
            com_pred_pc        <= 0 ;
            com_actual_pc     <= 0 ;
            com_excp_addr   <=  0 ;

            for (i = 0; i < ROB_DEPTH; i = i + 1) begin
                valid[i]          <= 1'b0;
                done[i]           <= 1'b0;
                pc[i]             <= 32'd0;
                we[i]             <= 1'b0;
                rd[i]             <= 5'd0;
                data[i]           <= 32'd0;
                excp_type[i]      <= 6'd0;
                excp_valid[i]     <= 1'b0;
                is_branch[i]      <= 1'b0;
                pred_taken[i]     <= 1'b0;
                pred_target[i]    <= 32'd0;
                actual_taken[i]   <= 1'b0;
                actual_target[i]  <= 32'd0;
                is_csr[i]      <= 1'b0;
                csr_op[i]      <= 2'b0;
                csr_num[i]     <= 14'd0;
                csr_wdata[i]   <= 32'd0;
                csr_mask[i]    <= 32'd0;     
                op_lsu[i]       <= 6'b0 ;
                tlb_sign[i]     <= 1'b0 ;
                cacop_sign[i]   <= 1'b0 ;       
            end
        end
        else begin
            // 默认值
            com_en          <= 1'b0;
            com_we          <= 1'b0;
            com_idx         <= 1'b0;
            com_excp_valid  <= 1'b0;
            com_ertn        <= 1'b0;
            com_idle        <= 1'b0;
            com_lsu_op      <= 6'd0;      // 新增
            com_tlb_data    <= 11'd0;     // 新增
            com_csr_sign      <= 2'b0;      // 新增
            com_csr_waddr   <= 14'd0;     // 新增
            com_csr_wdata   <= 32'd0;     // 新增
            com_csr_wmask   <= 32'd0;     // 新增
            com_cacop_sign  <= 1'b0;
            com_is_branch    <= 1'b0;
            com_pred_taken   <= 1'b0 ;
            com_actual_taken <= 1'b0 ;
            com_pred_pc      <= 32'd0 ;
            com_actual_pc    <= 32'd0 ;
            com_excp_addr   <=  0 ;
            // com_pc         <= 32'd0;
            // com_rd         <= 5'd0;
            // com_data       <= 32'd0;
            // com_we         <= 1'b0 ;
            // com_idx        <= 1'b0 ;
            // com_excp_valid <= 1'b0;
            // com_excp_type  <= 6'd0;
            // com_excp_pc    <= 32'd0;
            // com_lsu_op      <= 6'b0 ;
            // com_tlb_data    <= 11'b0 ;
            // com_cacop_sign  <= 1'b0 ;
            // com_csr_waddr     <= 0 ;
            // com_csr_wdata     <= 0 ;
            // com_csr_wmask     <= 0 ;
            // com_ertn       <= 1'b0;
            // com_idle       <= 1'b0;
            // // com_idle_pc    <= 32'd0;
            // com_is_branch     <= 0 ;
            // com_pred_taken     <= 0 ;
            // com_actual_taken  <= 0 ;
            // com_pred_pc        <= 0 ;
            // com_actual_pc     <= 0 ;


            if (!rob_flush) begin
                if (disp_en[0] && !rob_full_high) begin
                    valid[tail]         <= 1'b1;
                    done[tail]          <= 1'b0;
                    pc[tail]            <= disp_pc0;
                    we[tail]            <= disp_we0;
                    rd[tail]            <= disp_rd0;
                    excp_type[tail]     <= 6'd0;
                    excp_valid[tail]    <= 1'b0;
                    is_branch[tail]     <= disp_is_branch[0];
                    pred_taken[tail]    <= disp_pred_taken[0];
                    pred_target[tail]   <= disp_pred_target0;
                    actual_taken[tail]  <= 1'b0;
                    actual_target[tail] <= 32'd0;
                    //tlb
                    tlb_sign [tail ]    <= disp_tlb_sign0;
                    //op_lsu
                    op_lsu[tail]       <= disp_op_lsu0;   // ����
                    cacop_sign[tail]    <= disp_cacop_sign0 ;
                    if (disp_is_csr[0]) begin
                        is_csr[tail]      <= 1'b1;
                        csr_op[tail]      <= disp_csr_op0;
                        csr_num[tail]     <= disp_csr_num0;
                        // csr_wdata[tail]   <= disp_csr_wdata0;
                        // csr_mask[tail]    <= disp_csr_mask0;
                    end else begin
                        is_csr[tail]      <= 1'b0;
                    end
                end

                if (disp_en[1] && (count < (ROB_DEPTH - 1))) begin
                    valid           [(tail+1)%ROB_DEPTH]        <= 1'b1;
                    done            [(tail+1)%ROB_DEPTH]        <= 1'b0;
                    pc              [(tail+1)%ROB_DEPTH]        <= disp_pc1;
                    we              [(tail+1)%ROB_DEPTH]        <= disp_we1;
                    rd              [(tail+1)%ROB_DEPTH]        <= disp_rd1;
                    excp_type       [(tail+1)%ROB_DEPTH]        <= 6'd0;
                    excp_valid      [(tail+1)%ROB_DEPTH]        <= 1'b0;
                    is_branch       [(tail+1)%ROB_DEPTH]        <= disp_is_branch[1];
                    pred_taken      [(tail+1)%ROB_DEPTH]        <= disp_pred_taken[1];
                    pred_target     [(tail+1)%ROB_DEPTH]        <= disp_pred_target1;
                    actual_taken    [(tail+1)%ROB_DEPTH]        <= 1'b0;
                    actual_target   [(tail+1)%ROB_DEPTH]        <= 32'd0;
                    //tlb
                    tlb_sign        [(tail+1)%ROB_DEPTH ]       <= disp_tlb_sign1;
                    //lsu_op
                    op_lsu[(tail+1)%ROB_DEPTH]    <= disp_op_lsu1;   // ����
                    cacop_sign[(tail+1)%ROB_DEPTH] <= disp_cacop_sign1 ;
                    
                    if (disp_is_csr[1]) begin
                        is_csr[(tail+1)%ROB_DEPTH]      <= 1'b1;
                        csr_op[(tail+1)%ROB_DEPTH]      <= disp_csr_op1;
                        csr_num[(tail+1)%ROB_DEPTH]     <= disp_csr_num1;
                        // csr_wdata[(tail+1)%ROB_DEPTH]   <= disp_csr_wdata1;
                        // csr_mask[(tail+1)%ROB_DEPTH]    <= disp_csr_mask1;
                    end else begin
                        is_csr[(tail+1)%ROB_DEPTH]      <= 1'b0;
                    end                        
                    tail                                        <= (tail + 3'd2) % ROB_DEPTH;
                    count_disp                                  <= count_disp + 4'd2;
                end 
                    // else begin
                    //     tail <= (tail + 1'b1) % ROB_DEPTH;
                    //     count_disp <= count_disp + 4'd1;
                    // end
                

                // ---------- 写回 ----------
                // wb_ack0 <= 1'b0;
                // wb_ack1 <= 1'b0;
                if (wb0_valid && valid[wb0_idx] && !done[wb0_idx]) begin
                    data[wb0_idx]         <= wb0_data;
                    done[wb0_idx]         <= 1'b1;
                    excp_valid[wb0_idx]   <= wb0_exc;
                    excp_type[wb0_idx]    <= wb0_ecode;
                    actual_taken[wb0_idx] <= wb0_btaken;
                    actual_target[wb0_idx]<= wb0_btarget;
                    csr_wdata[wb0_idx]    <= wb0_data ;
                    csr_mask[wb0_idx]     <= wb0_btarget;

                    // wb_ack0 <= 1'b1;
                end
                if (wb1_valid && valid[wb1_idx] && !done[wb1_idx]) begin
                    data[wb1_idx]         <= wb1_data;
                    done[wb1_idx]         <= 1'b1;
                    excp_valid[wb1_idx]   <= wb1_exc;
                    excp_type[wb1_idx]    <= wb1_ecode;
                    actual_taken[wb1_idx] <= wb1_btaken;
                    actual_target[wb1_idx]<= wb1_btarget;
                    csr_wdata[wb1_idx]    <= wb1_data ;
                    csr_mask[wb1_idx]     <= wb1_btarget;

                    // wb_ack1 <= 1'b1;
                end

                // ---------- 提交 ----------
                if (!rob_empty_high && valid[head] && done[head]) begin
                    // 检查是否为真实异常（排除 ERTN/IDLE）
                    if (excp_valid[head] && (excp_type[head] != 6'h3D) && (excp_type[head] != 6'h3E) && excp_type[head] != 6'h00) begin
                        com_excp_valid  <= 1'b1;
                        com_we          <= 1'b0 ; //异常绝对不能写 grf
                        com_excp_type   <= excp_type[head];
                        com_excp_pc     <= pc[head];
                        com_excp_addr   <= actual_target[head];
                        // rob_flush       <= 1'b1;
                    end 
                    else begin
                        if(excp_valid[head] &&  excp_type[head] == 6'h00)begin
                            com_excp_valid  <= 1'b1;
                            // com_we          <= 1'b ; //异常绝对不能写 grf
                            com_excp_type   <= excp_type[head];
                            com_excp_pc     <= pc[head];
                            com_excp_addr   <= actual_target[head];
                        end
                        // CSR 指令处理
                        if (is_csr[head]) begin
                            com_pc   <= pc[head];
                            // 读 CSR 旧值（组合逻辑）
                            com_en   <= 1'b1;
                            com_we   <= 1'b1 ; //无论是csrrd还是csrwr其实都会写grf
                            com_rd   <= rd[head];
                            com_data <= com_csr_rdata;       // csr_rdata 在 csr_raddr 有效时组合返回
                            com_idx  <= head ;

                            // 写 CSR（CSRWR / CSRXCHG）
                            com_csr_sign    <= csr_op[head]  ;          // CSRRD 不写
                            com_csr_waddr <= csr_num[head];
                            com_csr_wdata <= csr_wdata[head];                 // rd 旧值
                            com_csr_wmask <= (csr_op[head] == 2'b11) ? csr_mask[head] : 32'hFFFFFFFF;

                            // 通知外部：CSR 写操作需要冲刷流水线（外部综合成 rob_flush）
                            // 可添加一个输出信号，例如 com_csr_write_valid，此处未显式列出，你可根据需要增加

                            valid[head] <= 1'b0;
                            done [head]  <= 1'b0;
                            pc[head]     <= 32'h0000;
                            rd [head]    <= 32'h0000; 
                            data [head]  <= 32'h0000;
                            head <= (head + 3'd1) % ROB_DEPTH;
                            count_com <= count_com + 4'd1;
                        end
                        else begin
                            // 正常提交（包括 ERTN、IDLE）
                            com_en   <= 1'b1;
                            com_we   <= we[head];
                            com_pc   <= pc[head];
                            com_rd   <= rd[head];
                            valid[head] <= 1'b0;
                            done [head]  <= 1'b0;
                            pc[head]     <= 32'h0000;
                            rd [head]    <= 32'h0000; 
                            data [head]  <= 32'h0000;
                            com_idx  <= head ;
                            if(!tlb_sign[head])begin
                                com_data <= data[head];
                                com_tlb_data <= 11'b0 ;
                            end
                            else begin
                                com_data  <= 32'b0 ;
                                com_tlb_data <= data[head] ;
                            end
                            //op_lsu也要被正常提交
                            com_lsu_op <= op_lsu[head];
                            com_cacop_sign <= cacop_sign[head] ;
                        
                            // ERTN
                            if (excp_valid[head] && (excp_type[head] == 6'h3D)) begin
                                com_ertn <= 1'b1;
                                com_rd   <= 5'd0;
                            end
                            // IDLE
                            else if (excp_valid[head] && (excp_type[head] == 6'h3E)) begin
                                com_idle    <= 1'b1;
                                // com_idle_pc <= pc[head] + 32'd4;
                                com_rd      <= 5'd0;
                            end

                        
                            com_is_branch    <= is_branch[head];
                            com_pred_taken   <= pred_taken[head] ;
                            com_actual_taken <= actual_taken[head] ;
                            com_pred_pc      <= pred_target[head] ;
                            com_actual_pc    <= actual_target[head] ;

                            head <= (head + 3'd1) % ROB_DEPTH;
                            count_com <= count_com + 4'd1;
                        end

                    end
                end
            end 
            
            else begin
                com_excp_valid  <= 1'b0;
                com_excp_type   <= 6'd0;
                com_excp_pc     <= 32'd0;
                com_en          <= 1'b0;
                com_we          <= 1'b0;
                com_idx         <= 3'b0 ;
                com_ertn        <= 1'b0;
                com_idle        <= 1'b0;
                com_lsu_op      <= 6'd0;      // 新增
                com_tlb_data    <= 11'd0;     // 新增
                com_csr_sign      <= 2'b0;      // 新增
                com_csr_waddr   <= 14'd0;     // 新增
                com_csr_wdata   <= 32'd0;     // 新增
                com_csr_wmask   <= 32'd0;     // 新增
                com_cacop_sign  <= 1'b0;
                com_is_branch    <= 1'b0;
                com_pred_taken   <= 1'b0 ;
                com_actual_taken <= 1'b0 ;
                com_pred_pc      <= 32'd0 ;
                com_actual_pc    <= 32'd0 ;
                for (i = 0; i < ROB_DEPTH; i = i + 1) begin
                    valid[i] <= 1'b0;
                    done[i]  <= 1'b0;
                    is_csr[i] <= 1'b0;
                    csr_op[i] <= 2'b0;
                    csr_num[i] <= 2'b0;
                    csr_wdata[i] <= 32'b0;
                    csr_mask[i] <= 8'b0;
                end
                head        <= 3'd0;
                tail        <= 3'd0;
                count_disp  <= 4'd0;
                count_com   <= 4'd0;

                // wb_ack0     <= 1'b0;
                // wb_ack1     <= 1'b0;
            end
        end
    end

    // RMT 释放信号：正常（非 ERTN/IDLE）指令提交时释放
    assign rob2rmt_com_comb = !rob_empty_high && valid[head] && done[head]
                              && !excp_valid[head];
    assign rob2rmt_robidx_comb = head ;
    assign rob2rmt_rd_comb  = rd[head] ;
    //为了解决r指令在exe先执行完成cdb写回，而指令w后写进发射队列
    assign rob_done_rjdata0 = done[disp_rj_need_rob_index0] ? data[disp_rj_need_rob_index0] :32'b0 ;
    assign rob_done_rkdata0 = done[disp_rk_need_rob_index0] ? data[disp_rk_need_rob_index0] :32'b0 ;
    assign rob_done_rjdata1 = done[disp_rj_need_rob_index1] ? data[disp_rj_need_rob_index1] :32'b0 ;
    assign rob_done_rkdata1 = done[disp_rk_need_rob_index1] ? data[disp_rk_need_rob_index1] :32'b0 ;
    //done信号也要被传回去
    assign rj_rob_done0 = done[disp_rj_need_rob_index0];
    assign rk_rob_done0 = done[disp_rk_need_rob_index0];
    assign rj_rob_done1 = done[disp_rj_need_rob_index1];
    assign rk_rob_done1 = done[disp_rk_need_rob_index1];
endmodule