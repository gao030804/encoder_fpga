`timescale 1ns/1ps
// service_cycles覆盖取帧->PCM写入->Encoder63->Projection/RVQ9->入输出Ring。
// 不把UART传输/排队算进service；20ms在50MHz下为1,000,000周期。
module status_perf_counter (
    input clk,input rst_n,input frame_committed,input frame_taken,
    input encode_done,input result_sent,input [2:0] fifo_occupied,
    output reg [31:0] received_frames,encoded_frames,sent_frames,
    output reg [31:0] last_service_cycles,worst_service_cycles,
    output reg [2:0] max_fifo_occupied,output reg realtime_fault
);
reg [31:0] cycles,start_cycle; // 内部自由运行计数；start_cycle在取帧握手时快照。
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin cycles<=0;start_cycle<=0;received_frames<=0;encoded_frames<=0;sent_frames<=0;
        last_service_cycles<=0;worst_service_cycles<=0;max_fifo_occupied<=0;realtime_fault<=0;end
    else begin
        cycles<=cycles+1'b1;
        if(frame_committed)received_frames<=received_frames+1'b1;
        if(frame_taken)start_cycle<=cycles;
        if(encode_done)begin
            encoded_frames<=encoded_frames+1'b1;last_service_cycles<=cycles-start_cycle;
            if(cycles-start_cycle>worst_service_cycles)worst_service_cycles<=cycles-start_cycle;
            if(cycles-start_cycle>1000000)realtime_fault<=1;
        end
        // sent_frames为发送器完成字节入队数；端到端TB另检查PC实际接收数。
        if(result_sent)sent_frames<=sent_frames+1'b1;
        if(fifo_occupied>max_fifo_occupied)max_fifo_occupied<=fifo_occupied;
    end
end
endmodule
