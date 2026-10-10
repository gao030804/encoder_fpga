`timescale 1ns/1ps
// 累计授予额度：初始4，释放/丢弃一个已预约槽后+1。
// PC可发送数=grant_total-已发送包数；累计值避免多个在途通知重复加额度。
// 未发出的旧通知可合并；serializer握手时快照grant_total。
module credit_flow_ctrl (
    input clk,input rst_n,input link_ready,input slot_released,input refresh,
    output credit_valid,input credit_ready,output reg [31:0] grant_total
);
reg initialized;         // 只在Boot和参数就绪后授予本会话初始4个槽。
reg force_pending;       // PC查询请求；即使累计值未变也需要重发。
reg [31:0] announced;    // 已被serializer快照的累计额度，不是PC已使用额度。
assign credit_valid=initialized && (grant_total!=announced || force_pending);
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin initialized<=0;grant_total<=0;announced<=0;force_pending<=0;end
    else begin
        if (!initialized && link_ready) begin initialized<=1;grant_total<=4;end
        else if (initialized && slot_released) grant_total<=grant_total+1'b1;
        if (credit_valid && credit_ready) begin announced<=grant_total;force_pending<=0;end
        if (refresh)force_pending<=1;
    end
end
endmodule
