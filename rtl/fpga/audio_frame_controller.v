`timescale 1ns/1ps
// 只调度PCM加载及编码。done代表结果入Ring，马上调度下一帧；不等UART发完。
// Activation A/B只属于当前编码事务，待Encoder/RVQ空闲后才写下一帧。
module audio_frame_controller (
    input clk,input rst_n,input boot_ready,input params_ready,
    input frame_valid,output frame_ready,input [31:0] frame_id,
    output pcm_frontend_start,input pcm_frontend_done,output sample_enable,
    input encoder_start_ready,output encoder_start,input encoder_done,input encoder_error,
    output busy,output reg error,output reg [31:0] completed_frames,
    output reg [31:0] active_frame_id
);
localparam S_IDLE=0,S_FRONT_START=1,S_FRONT_WAIT=2,S_ENCODER_START=3,S_ENCODER_WAIT=4;
reg [2:0] state;
assign frame_ready=state==S_IDLE && boot_ready && params_ready && encoder_start_ready;
assign pcm_frontend_start=state==S_FRONT_START;
assign sample_enable=state==S_FRONT_WAIT;
assign encoder_start=state==S_ENCODER_START && encoder_start_ready;
assign busy=state!=S_IDLE;
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin state<=S_IDLE;error<=0;completed_frames<=0;active_frame_id<=0;end
    else begin
        if(encoder_error)error<=1;
        case(state)
            S_IDLE:if(frame_valid && frame_ready)begin
                active_frame_id<=frame_id;if(frame_id!=completed_frames)error<=1;
                state<=S_FRONT_START;
            end
            S_FRONT_START:state<=S_FRONT_WAIT;
            S_FRONT_WAIT:if(pcm_frontend_done)state<=S_ENCODER_START;
            S_ENCODER_START:if(encoder_start_ready)state<=S_ENCODER_WAIT;
            S_ENCODER_WAIT:if(encoder_done)begin completed_frames<=completed_frames+1'b1;state<=S_IDLE;end
            default:state<=S_IDLE;
        endcase
    end
end
endmodule
