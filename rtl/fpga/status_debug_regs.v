`timescale 1ns/1ps

// 可接到 LED/ILA 的最小状态视图；不会改变数据通路时序。
module status_debug_regs (
    input clk, input rst_n,
    input boot_ready, input params_ready, input frame_busy,
    input encoder_busy, input encoder_error,
    input packet_error, input rx_overflow, input tx_overflow,
    input [31:0] completed_frames,
    output [3:0] led, output [31:0] debug_status
);
reg sticky_error;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sticky_error<=0;
    else if (encoder_error || packet_error || rx_overflow || tx_overflow)
        sticky_error<=1;
end
assign led={sticky_error,frame_busy,params_ready,boot_ready};
assign debug_status={completed_frames[23:0],tx_overflow,rx_overflow,
                     packet_error,encoder_error,encoder_busy,frame_busy,
                     params_ready,boot_ready};
endmodule
