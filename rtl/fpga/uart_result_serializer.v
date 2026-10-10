`timescale 1ns/1ps
// 共用回包格式：A5 5A type status frame_id(4LE) length(2LE) payload CRC16(2LE)。
// 81:完整128-bit输出Ring记录；82:累计Credit UINT32；83:拒绝原因UINT8。
// 只在空闲时ready并快照整个消息；TX反压时index/数据/CRC保持不变。
module uart_result_serializer (
    input clk,input rst_n,
    input result_valid,output result_ready,input [127:0] result_record,
    input credit_valid,output credit_ready,input [31:0] credit_total,
    input reject_valid,output reject_ready,input [31:0] reject_id,input [7:0] reject_reason,
    output tx_valid,input tx_ready,output reg [7:0] tx_data,
    output reg result_sent
);
reg active;              // 已持有一份快照，不能再从Ring取下一记录。
reg [5:0] index;          // 当前待发送字节号；只有tx_valid&&tx_ready才递增。
reg [7:0] kind,length;    // 报文类别81/82/83、有效payload字节数16/4/1。
reg [31:0] id;           // 回包外层帧号；Credit报文不关联音频帧，使用0。
reg [127:0] payload;     // 原子快照，上游在握手后可改变result_record。
reg [15:0] crc;          // CRC不含SOF，也不包含CRC本身；反压时不更新。
assign reject_ready=!active;
assign credit_ready=!active && !reject_valid;
assign result_ready=!active && !reject_valid && !credit_valid;
assign tx_valid=active;
function [15:0] crc16;
    input [15:0] prior;input [7:0] b;
    reg [15:0] c;integer k;
    begin c=prior^{b,8'd0};for(k=0;k<8;k=k+1)c=c[15]?((c<<1)^16'h1021):(c<<1);crc16=c;end
endfunction
always @* begin
    tx_data=0;
    case(index)
        0:tx_data=8'ha5;1:tx_data=8'h5a;2:tx_data=kind;3:tx_data=0;
        4:tx_data=id[7:0];5:tx_data=id[15:8];6:tx_data=id[23:16];7:tx_data=id[31:24];
        8:tx_data=length;9:tx_data=0;
        default: begin
            if(index<10+length) tx_data=payload[8*(index-10) +: 8];
            else if(index==10+length) tx_data=crc[7:0];
            else tx_data=crc[15:8];
        end
    endcase
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin active<=0;index<=0;kind<=0;length<=0;id<=0;payload<=0;crc<=16'hffff;result_sent<=0;end
    else begin
        result_sent<=0;
        if(!active)begin
            // NACK优先，随后Credit、结果。只仲裁整条报文，不在字节中间切换。
            if(reject_valid)begin active<=1;kind<=8'h83;length<=1;id<=reject_id;payload<={120'd0,reject_reason};end
            else if(credit_valid)begin active<=1;kind<=8'h82;length<=4;id<=0;payload<={96'd0,credit_total};end
            else if(result_valid)begin active<=1;kind<=8'h81;length<=16;id<=result_record[95:64];payload<=result_record;end
            index<=0;crc<=16'hffff;
        end else if(tx_ready)begin
            if(index>=2 && index<10+length)crc<=crc16(crc,tx_data);
            // result_sent表示完整结果包已入TX字节FIFO，并非串口最后停止位已出线。
            if(index==11+length)begin active<=0;result_sent<=(kind==8'h81);end
            else index<=index+1'b1;
        end
    end
end
endmodule
