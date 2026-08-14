`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/16 11:05:36
// Design Name: 
// Module Name: arf
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

module grf(
    input clk,
    input rstn,

    //id-dispatch
    input  wire [4:0]  i_id_rj0_index_5,
    input  wire [4:0]  i_id_rk0_index_5,
    input  wire [4:0]  i_id_rj1_index_5,
    input  wire [4:0]  i_id_rk1_index_5,
    output wire [31:0] o_id_rj0_data_32,
    output wire [31:0] o_id_rk0_data_32,
    output wire [31:0] o_id_rj1_data_32,
    output wire [31:0] o_id_rk1_data_32,

    //commit
    input wire          i_com_en     ,
    input wire [4:0]    i_com_addr_5 ,
    input wire [31:0]   i_com_data_32

`ifdef DIFFTEST_EN
    output wire [31:0] rf_o [31:0]
`endif    
    );

    //commit 
    reg [31:0] regs[31:0];
    integer i;
    always@(posedge clk or negedge rstn)begin
        if(!rstn) begin
            for (i = 0; i < 32 ; i = i + 'd1) regs[i] <= 32'h0000;
        end
        else begin
            if( i_com_en && i_com_addr_5 != 5'd0 )begin
                regs[i_com_addr_5] <= i_com_data_32;
            end 
        
        
        
        end
    end

    //id:
    assign o_id_rj0_data_32 = (i_id_rj0_index_5 == 5'b0 ) ? 32'h0000: regs[i_id_rj0_index_5];
    assign o_id_rk0_data_32 = (i_id_rk0_index_5 == 5'b0 ) ? 32'h0000: regs[i_id_rk0_index_5];
    assign o_id_rj1_data_32 = (i_id_rj1_index_5 == 5'b0 ) ? 32'h0000: regs[i_id_rj1_index_5];
    assign o_id_rk1_data_32 = (i_id_rk1_index_5 == 5'b0 ) ? 32'h0000: regs[i_id_rk1_index_5];


    

`ifdef DIFFTEST_EN
    assign rf_o = regs;
`endif
endmodule
