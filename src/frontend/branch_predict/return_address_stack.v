module return_address_stack(
    input wire          clk,
    input wire          rstn,
    //push接口
    input wire          i_push_en,
    input wire [29:0]   i_push_pc_30,
    //pop接口
    input wire          i_pop_en,
    output wire         o_target_ready,
    output wire [29:0]  o_pop_target_30,//始终读取栈顶，但只有enable时才弹栈
    output wire [3:0]   o_stack_ptr_4,
    //恢复控制端口，checkpoint控制
    input wire          i_recover_en,
    input wire [3:0]    i_recover_ptr_4
);
    //ras内部做两套更新机制，主要是checkpoint的更新时机和预测时机不一致
    wire [31:0] stack_top;

    reg [3:0] top_ptr;
    reg [29:0] stack_regs [0:15];
    reg stack_empty;

    assign stack_top = stack_regs[top_ptr];

    assign o_pop_target_30 = i_push_en ? i_push_pc_30 : stack_top; //如果同时有push和pop请求，优先返回push的地址
    assign o_target_ready = !stack_empty || i_push_en; //如果栈不空或者有push请求，返回地址有效
    assign o_stack_ptr_4 = top_ptr;

    integer i;
    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            for (i = 0; i < 16; i = i + 1) begin
                stack_regs[i] <= 30'b0;
            end
            stack_empty <= 1'b1;
            top_ptr <= 4'b0;
        end else begin
            if(i_recover_en) begin
                top_ptr <= i_recover_ptr_4;
            end else begin
                case ({i_push_en, i_pop_en, stack_empty})
                    3'b101: begin
                        stack_empty <= 1'b0;
                        top_ptr <= top_ptr;
                        stack_regs[top_ptr] <= i_push_pc_30;
                    end
                    3'b100: begin
                        if(top_ptr != 4'b1111) begin
                            top_ptr <= top_ptr + 4'd1;
                            stack_regs[top_ptr + 4'd1] <= i_push_pc_30;
                        end else begin
                            top_ptr <= top_ptr;
                        end
                    end
                    3'b011: begin
                        stack_empty <= 1'b1;
                        top_ptr <= top_ptr;
                    end
                    3'b010: begin
                        if(!top_ptr) begin
                            stack_empty <= 1'b1;
                            top_ptr <= top_ptr;
                        end else begin
                            top_ptr <= top_ptr - 1'd1;
                        end
                    end
                    3'b111, 3'b110: begin
                        //同时有读写请求，不压入也不弹出
                        top_ptr <= top_ptr;
                    end
                    default: begin
                        top_ptr <= top_ptr;
                    end
                endcase
            end
        end
    end
endmodule