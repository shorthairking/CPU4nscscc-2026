`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/03/31 22:14:48
// Design Name: 
// Module Name: RAT
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
//  1.通过rob中的data域作为物理寄存器完成对WAW和WAR两种伪相关性的解决，
//  2.但是对于RAW真相关性，需要通过寄存器映射表来完成管理，源寄存器通过查看这个映射表来确定操作数是否准备好
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module RMT(
    input wire clk,
    input wire rstn,
    input wire flush,   //高电平有效
    
    //数据信号
    input  wire [4:0]    i_rj_idx0,
    input  wire [4:0]    i_rk_idx0,   
    input  wire [4:0]    i_rd_idx0,
    input  wire [2:0]    i_rob_entry_idx0,  //写入的这条指令对应的rob索引，应该从rob中发送过来，而不是dispatch
    output wire          o_rj_ready_idx0,
    output wire          o_rk_ready_idx0,
    output wire [2:0]    o_rj_rob_idx0,//当ready == 1 的时候，建立的映射关系需要传出到发射队列
    output wire [2:0]    o_rk_rob_idx0,

    input  wire [4:0]    i_rj_idx1,
    input  wire [4:0]    i_rk_idx1,
    input  wire [4:0]    i_rd_idx1,
    input  wire [2:0]    i_rob_entry_idx1,
    output wire          o_rj_ready_idx1,
    output wire          o_rk_ready_idx1,
    output wire [2:0]    o_rj_rob_idx1,
    output wire [2:0]    o_rk_rob_idx1,

    //控制信号,dispatch
    input wire           i_wen_idx0,
    input wire           i_wen_idx1,

    //这三个清楚映射的信号都要是从rob中组合逻辑传递的提交数据
    //提交周期清空映射,由于单周期只能提交一条指令，所以只有一个寄存器映射能恢复
    input wire [4:0]     i_com_rd,
    input wire [2:0]     i_com_rob_idx,
    input wire           i_com_en_comb   //提交的使能信号，一条指令，使能信号会被拉高一个周期，在这个时钟周期进行恢复,在rob中，使能信号是一个reg型的信号，需要通过组合逻辑电路来使用获取（在写回周期）
                                    //这个com_comb既不能使用写回的使能，也不能使用提交的使能，而是写回周期判断valid，done，excp_valid，rob_empty_high等信号来判断是否可以正常提交

    );

    //rmt中的基本单元,valid == 1 标志着这个寄存器被映射了，tag用来映射到对应的rob条目，只有在valid ==1 的时候，这个值才是有效的
    reg         valid [0:31];
    reg  [2:0]  tag [0:31];

    //更新映射，写数据
    integer i,j;
    always@(posedge clk or negedge rstn)begin
        if( !rstn )begin
            for (i = 0 ; i < 'd32 ; i = i + 'd1)begin
                valid[i]    <= 0;
                tag[i]      <= 3'b000;    
            end
        end
        else begin
            if ( flush )begin
                for(j = 0 ; j <32 ; j= j+ 'd1)begin
                    valid[j]    <= 0;
                    tag[j]      <= 3'b000;    
                end
            end
            else begin //实现的是拉高com_en的那个上升沿，同时释放rmt的映射
                if( i_com_en_comb && i_com_rd != 5'd0 )begin    //提交逻辑需要写在分发逻辑的前面，这样才能避免多驱动的问题
                    if (valid[i_com_rd] && ( tag[i_com_rd] == i_com_rob_idx) ) begin
                        valid[i_com_rd] <= 1'b0;
                    end   
                end
                //非冲刷的时候，进行正常的建立映射关系
                if( i_wen_idx0 ) begin
                    valid[i_rd_idx0] <= 1;
                    tag[i_rd_idx0]   <= i_rob_entry_idx0;
                end
                
                if( i_wen_idx1)begin
                    valid[i_rd_idx1] <= 1;
                    tag[i_rd_idx1]   <= i_rob_entry_idx1;
                end
            end
        
        end
    end
    

//查询数据
wire hint_rj_idx1_from_idx0 ;   //主要用于解决同周期的raw相关性
wire hint_rk_idx1_from_idx0 ;

assign hint_rj_idx1_from_idx0 = i_wen_idx0 && i_rj_idx1 == i_rd_idx0 &&  i_rd_idx0 != 5'd0;
assign hint_rk_idx1_from_idx0 = i_wen_idx0 && i_rk_idx1 == i_rd_idx0 &&  i_rd_idx0 != 5'd0;

/*不需要处理提交和分发同周期的情况了！！！*/
//特殊情况的解决：分发的指令和该周期提交的指令存在raw相关性
// wire [1:0] disp_commit_hint0;//0位标识rj，1位标识rk
// wire [1:0] disp_commit_hint1;
// assign disp_commit_hint0 = ( i_rj_idx0 == i_com_rd ) && (i_rk_idx0 == i_com_rd) ? 2'b11 :
//                                                         i_rj_idx0 == i_com_rd   ? 2'b01 :
//                                                         i_rk_idx0 == i_com_rd   ? 2'b10 : 2'b00 ;

// assign disp_commit_hint1 = ( i_rj_idx1 == i_com_rd ) && (i_rk_idx1 == i_com_rd) ? 2'b11 :
//                                                         i_rj_idx1 == i_com_rd   ? 2'b01 :
//                                                         i_rk_idx1 == i_com_rd   ? 2'b10 : 2'b00 ;

//当出现这种该周期分发指令和提交指令存在raw的时候，当作ready=0，下一个周期在iq的时候从arf获取数据
//综上：三种比较的优先级为：同周期raw > 提交-分发raw > 跨周期raw（rmt状态）

//inst0
// assign o_rj_ready_idx0 = disp_commit_hint0[0] ? 1'b1 : ~valid[i_rj_idx0]; //如果分发-提交raw产生，ready置1;由于寄存器映射是1为有效，而ready是只有为1的时候才能从arf读取，所以这里要取反一下
// assign o_rk_ready_idx0 = disp_commit_hint0[1] ? 1'b1 : ~valid[i_rk_idx0];
// //inst1
// assign o_rj_ready_idx1 = hint_rj_idx1_from_idx0 ? 1'b0 : 
//                          disp_commit_hint1[0]   ? 1'b1 : ~valid[i_rj_idx1] ; //只有当valid映射为0，并且，同周期两条指令没有相关性（hint==0），ready才为1，也就是可以从arf或许操作数

// assign o_rk_ready_idx1 = hint_rk_idx1_from_idx0 ? 1'b0 :
//                          disp_commit_hint1[1]   ? 1'b1 : ~valid[i_rk_idx1] ;

// //输出对应rob条目信息
// assign o_rj_rob_idx0 = disp_commit_hint0[0] ? 'd0 :     //如果存在分发-提交raw，因为ready被当作1，不需要索引，但查询的上升沿，valid一定是1，不应该被采用
//                            valid[i_rj_idx0] ? tag[i_rj_idx0] : 'd0;
// assign o_rk_rob_idx0 = disp_commit_hint0[1] ? 'd0 :
//                            valid[i_rk_idx0] ? tag[i_rk_idx0] : 'd0;

// assign o_rj_rob_idx1 = hint_rj_idx1_from_idx0 ? i_rob_entry_idx0 :
//                        disp_commit_hint1[0]   ? 'd0              :
//                              valid[i_rj_idx1] ?  tag[i_rj_idx1]  :  'd0;
// assign o_rk_rob_idx1 = hint_rk_idx1_from_idx0 ? i_rob_entry_idx0 :
//                        disp_commit_hint1[1]   ? 'd0              :
//                              valid[i_rk_idx1] ?  tag[i_rk_idx1]  :  'd0;


assign o_rj_ready_idx0 =  ~valid[i_rj_idx0]; 
assign o_rk_ready_idx0 =  ~valid[i_rk_idx0];
//inst1
assign o_rj_ready_idx1 = hint_rj_idx1_from_idx0 ? 1'b0 : ~valid[i_rj_idx1] ; 
//同周期的相关性优先级最高，同周期没有优先级再去查表得到跨周期的相关性
assign o_rk_ready_idx1 = hint_rk_idx1_from_idx0 ? 1'b0 : ~valid[i_rk_idx1] ;
                      

//输出对应rob条目信息
assign o_rj_rob_idx0 = valid[i_rj_idx0] ? tag[i_rj_idx0] : 'd0;     //因为ready已经是1了，此时的tag不会被使用到了，设置为0应该也不会有问题
                           
assign o_rk_rob_idx0 = valid[i_rk_idx0] ? tag[i_rk_idx0] : 'd0;
                           

assign o_rj_rob_idx1 = hint_rj_idx1_from_idx0 ? i_rob_entry_idx0 :
                             valid[i_rj_idx1] ?  tag[i_rj_idx1]  :  'd0;
assign o_rk_rob_idx1 = hint_rk_idx1_from_idx0 ? i_rob_entry_idx0 :
                             valid[i_rk_idx1] ?  tag[i_rk_idx1]  :  'd0;


endmodule
