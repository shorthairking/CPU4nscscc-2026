`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/14 13:13:08
// Design Name: 
// Module Name: icache_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`include "LoongArch.vh"

module Icache_top(
    input  wire clk,
    input  wire rstn,
    input  wire clear,

    input  wire        i_pif_en,     
    input  wire        i_addr_ok,
    input  wire        i_data_ok,

    input  wire [31:0] i_preif_pc_32     ,
    input  wire [31:0] i_pc_to_if_32     ,
    input  wire [ 6:0] i_preif_data_7    ,
    input  wire        i_preif_uncache_en,
    input  wire        i_inst0_valid     ,
    input  wire [ 1:0] i_pred_isTaken_2  ,
    input  wire [63:0] i_pred_target_64  ,

    output wire [31:0] o_to_icache_pc_32 ,
    output wire        o_to_icache_uncache_en,
    output wire        o_to_if_clear_buffer,
    output wire [31:0] o_to_if_pc_32     ,
    output wire [ 6:0] o_to_if_exdata_7  ,
    output wire [ 1:0]  o_to_if_pred_isTaken_2,
    output wire [63:0] o_to_if_pred_target_64,
    output wire        o_icache_valid    ,
    output  wire        o_inst0_valid
    );

//..................................................级间数据

reg        valid, uncache_en;
reg [31:0] pc, to_if_pc;
reg [ 6:0] ex_data;
reg        inst0_valid;
reg [ 1:0]  pred_isTaken_2;
reg [63:0] pred_target_64;

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        pc <= 32'h0;
        inst0_valid <= 1'b0;
    end
    else begin
        if(i_addr_ok & i_pif_en) begin
            pc <= i_preif_pc_32;
            inst0_valid <= i_inst0_valid;
        end
        else begin
            pc <= pc;
            inst0_valid <= inst0_valid;
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        to_if_pc <= 32'h0;
    end
    else begin
        if(i_addr_ok & i_pif_en) begin
            to_if_pc <= i_pc_to_if_32;
        end
        else begin
            to_if_pc <= to_if_pc;
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        ex_data <= 7'h0;
    end
    else begin
        if(i_addr_ok & i_pif_en) begin
            ex_data <= i_preif_data_7;
        end
        else begin
            ex_data <= ex_data;
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        valid <= 1'h0;
    end
    else begin
        if(i_addr_ok & i_pif_en) begin
            valid <= 1'b1;
        end
        else if(i_data_ok) begin
            valid <= 1'b0;
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        uncache_en <= 1'b0;
    end
    else begin
        if(i_addr_ok & i_pif_en) begin
            uncache_en <= i_preif_uncache_en;
        end
        else if(i_data_ok) begin
            uncache_en <= 1'b0;
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        pred_isTaken_2 <= 2'b0;
        pred_target_64 <= 64'b0;
    end
    else begin
        if(i_addr_ok & i_pif_en) begin
            pred_isTaken_2 <= i_pred_isTaken_2;
            pred_target_64 <= i_pred_target_64;
        end
        else if(i_data_ok) begin
            pred_isTaken_2 <= 2'b0;
            pred_target_64 <= 64'b0;
        end
    end
end

reg clear_buff;
always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
        clear_buff <= 1'b0;
    end else if(clear && (valid || (i_addr_ok & i_pif_en))) begin
        clear_buff <= 1'b1;
    end else if (i_data_ok) begin
        clear_buff <= 1'b0;
    end
end

assign o_to_icache_pc_32 = pc;
assign o_to_icache_uncache_en = uncache_en;
assign o_to_if_pc_32  = to_if_pc;
assign o_to_if_exdata_7 = ex_data;
assign o_icache_valid  = valid & ~i_data_ok;
assign o_inst0_valid = inst0_valid;
assign o_to_if_pred_isTaken_2 = pred_isTaken_2;
assign o_to_if_pred_target_64 = pred_target_64;
assign o_to_if_clear_buffer = clear_buff;
endmodule
