module stop_control(
    input wire clk,
    input wire rstn,
    //后端请求信号
    input wire i_backend_stop_req,//后端暂停请求，后端队列满或ROB满\
    input wire i_backend_clear_req,//后端清空请求，ROB异常或异常指令
    //例外和异常信号，来自提交
    input  wire i_ex_sign,
    input  wire i_ertn_sign,
    input  wire i_cacop_sign,
    //暂停状态输出信号
    output wire o_stop,//包括预取指和取指
    output wire o_clear
);

    assign o_stop = i_backend_stop_req;
    assign o_clear = i_ex_sign | i_ertn_sign | i_cacop_sign | i_backend_clear_req;

endmodule