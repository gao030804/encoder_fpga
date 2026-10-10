`timescale 1ns/1ps
// 独立的4帧PCM缓存：每槽320×INT16，共2560 Byte。
// 接收端先reserve，再写样本，CRC通过才commit；CRC失败abort整槽。
// 计算端握手取得帧后逐样本读取；最后一个样本被接受才释放槽位。
module pcm_frame_fifo (
    input clk, input rst_n,
    input reserve_valid, output reserve_ready, input [31:0] reserve_id,
    input write_valid, input [8:0] write_index, input [15:0] write_data,
    input commit, input abort_frame,
    output frame_valid, input frame_ready, output [31:0] frame_id,
    output sample_valid, input sample_ready, output [15:0] sample_data,
    output reg slot_released, output reg frame_committed,
    output [2:0] occupied, output reg error
);
reg [15:0] samples [0:1279]; // 不复位数组，允许FPGA推断RAM
reg [31:0] ids [0:3];
reg [1:0] wr_slot,rd_slot; // 环形写/读槽号；两位加法自动模4绕回。
reg [2:0] level;          // 已提交槽数，包含正在向前端交付的槽。
reg reserved,draining;   // reserved：接收侧占用一个未提交槽；draining：读帧进行中。
reg [8:0] rd_index;       // 当前帧样本号0..319，按sample握手而不是每个clk递增。
wire push=commit && reserved;
wire pop=sample_valid && sample_ready && rd_index==9'd319;
assign reserve_ready=!reserved && level<4;
assign frame_valid=(level!=0) && !draining;
assign frame_id=ids[rd_slot];
assign sample_valid=draining;
assign sample_data=samples[rd_slot*320+rd_index];
assign occupied=level+reserved;
always @(posedge clk) begin
    // 数据阵列无复位，只有成功预约/合法写入才允许改写，避免清空RAM影响推断。
    if (reserve_valid && reserve_ready) ids[wr_slot]<=reserve_id;
    if (write_valid && reserved && write_index<320)
        samples[wr_slot*320+write_index]<=write_data;
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_slot<=0;rd_slot<=0;level<=0;reserved<=0;draining<=0;
        rd_index<=0;slot_released<=0;frame_committed<=0;error<=0;
    end else begin
        slot_released<=0;frame_committed<=0;
        if (reserve_valid && reserve_ready) reserved<=1;
        if (write_valid && (!reserved || write_index>=320)) error<=1;
        if (push) begin
            reserved<=0;wr_slot<=wr_slot+1'b1;frame_committed<=1;
        end
        if (abort_frame && reserved) begin reserved<=0;slot_released<=1;end
        if (frame_valid && frame_ready) begin draining<=1;rd_index<=0;end
        if (sample_valid && sample_ready) begin
            if (pop) begin
                draining<=0;rd_slot<=rd_slot+1'b1;slot_released<=1;
            end else rd_index<=rd_index+1'b1;
        end
        // 两个不同槽可以同周期提交和释放；此时level不变，指针各自前进。
        case ({push,pop})
            2'b10: level<=level+1'b1;
            2'b01: level<=level-1'b1;
            default: level<=level;
        endcase
    end
end
endmodule
