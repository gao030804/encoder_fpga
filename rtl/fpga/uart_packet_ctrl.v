`timescale 1ns/1ps
// RX专用解析器：A5 5A 01 frame_id[4LE] length=640[2LE] PCM[640] CRC16[2LE]。
// 在payload之前预约FIFO槽，CRC通过后提交；失败时整帧回滚并返还Credit。
// 物理UART无反压，rx_ready只控制前置字节FIFO；PC必须遵守帧Credit。
module uart_packet_ctrl (
    input clk,input rst_n,input rx_valid,output rx_ready,input [7:0] rx_data,
    output reserve_valid,input reserve_ready,output [31:0] reserve_id,
    output write_valid,output [8:0] write_index,output [15:0] write_data,
    output commit,output abort_frame,
    output reg reject_valid,input reject_ready,
    output reg [31:0] reject_id,output reg [7:0] reject_reason,
    output credit_refresh,output reg packet_error
);
localparam R_SYNC0=0,R_SYNC1=1,R_HEADER=2,R_RESERVE=3,R_PAYLOAD=4,R_CRC0=5,R_CRC1=6,R_DISCARD=7,Q_CRC0=8,Q_CRC1=9;
reg [3:0] rx_state;
reg [2:0] header_index;
reg [9:0] payload_count;
reg [31:0] frame_id_q;
reg [7:0] low_byte,length_low,crc_low;
reg [7:0] header_cmd;
reg [15:0] rx_crc;
wire fire=rx_valid && rx_ready;
assign rx_ready=(rx_state!=R_RESERVE);
assign reserve_valid=(rx_state==R_RESERVE);
assign reserve_id=frame_id_q;
assign write_valid=fire && rx_state==R_PAYLOAD && payload_count[0];
assign write_index=payload_count[9:1];
assign write_data={rx_data,low_byte};
assign commit=fire && rx_state==R_CRC1 && {rx_data,crc_low}==rx_crc;
assign abort_frame=fire && rx_state==R_CRC1 && {rx_data,crc_low}!=rx_crc;
// CMD=02、length=0为状态查询，重发累计Credit；不会预约PCM槽。
assign credit_refresh=fire && rx_state==Q_CRC1 && {rx_data,crc_low}==rx_crc;
function [15:0] crc16;
    input [15:0] prior;input [7:0] b;reg [15:0] c;integer k;
    begin c=prior^{b,8'd0};for(k=0;k<8;k=k+1)c=c[15]?((c<<1)^16'h1021):(c<<1);crc16=c;end
endfunction
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin rx_state<=R_SYNC0;header_index<=0;payload_count<=0;frame_id_q<=0;
        low_byte<=0;length_low<=0;crc_low<=0;header_cmd<=0;rx_crc<=16'hffff;
        reject_valid<=0;reject_id<=0;reject_reason<=0;packet_error<=0;end
    else begin
        if(reject_valid && reject_ready)reject_valid<=0;
        if(rx_state==R_RESERVE)begin
            payload_count<=0;
            if(reserve_ready)rx_state<=R_PAYLOAD;
            else begin
                // 无槽说明PC超额度；丢弃本包，禁止覆盖任何在用槽。
                rx_state<=R_DISCARD;packet_error<=1;
                reject_valid<=1;reject_id<=frame_id_q;reject_reason<=3;
            end
        end
        if(fire)case(rx_state)
            R_SYNC0:if(rx_data==8'ha5)rx_state<=R_SYNC1;
            R_SYNC1:begin
                if(rx_data==8'h5a)begin rx_state<=R_HEADER;header_index<=0;rx_crc<=16'hffff;end
                else if(rx_data!=8'ha5)rx_state<=R_SYNC0;
            end
            R_HEADER:begin
                rx_crc<=crc16(rx_crc,rx_data);header_index<=header_index+1'b1;
                case(header_index)
                    0:begin header_cmd<=rx_data;if(rx_data!=1 && rx_data!=2)begin rx_state<=R_SYNC0;packet_error<=1;end end
                    1:frame_id_q[7:0]<=rx_data;2:frame_id_q[15:8]<=rx_data;
                    3:frame_id_q[23:16]<=rx_data;4:frame_id_q[31:24]<=rx_data;
                    5:length_low<=rx_data;
                    6:if(header_cmd==1 && {rx_data,length_low}==640)rx_state<=R_RESERVE;
                      else if(header_cmd==2 && {rx_data,length_low}==0)rx_state<=Q_CRC0;
                      else begin rx_state<=R_SYNC0;packet_error<=1;reject_valid<=1;reject_id<=frame_id_q;reject_reason<=2;end
                endcase
            end
            R_PAYLOAD:begin
                rx_crc<=crc16(rx_crc,rx_data);
                if(!payload_count[0])low_byte<=rx_data;
                if(payload_count==639)rx_state<=R_CRC0;
                else payload_count<=payload_count+1'b1;
            end
            R_CRC0:begin crc_low<=rx_data;rx_state<=R_CRC1;end
            Q_CRC0:begin crc_low<=rx_data;rx_state<=Q_CRC1;end
            Q_CRC1:begin rx_state<=R_SYNC0;if({rx_data,crc_low}!=rx_crc)packet_error<=1;end
            R_CRC1:begin
                rx_state<=R_SYNC0;
                if({rx_data,crc_low}!=rx_crc)begin packet_error<=1;reject_valid<=1;reject_id<=frame_id_q;reject_reason<=1;end
            end
            R_DISCARD:if(payload_count==641)rx_state<=R_SYNC0;else payload_count<=payload_count+1'b1;
            default:rx_state<=R_SYNC0;
        endcase
    end
end
endmodule
