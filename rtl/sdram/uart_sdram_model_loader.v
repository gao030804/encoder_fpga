`timescale 1ns/1ps
// Boot protocol: ASCII SDR1, then MODEL_BLOCKS records of 32 LE bytes + CRC16 LE.
// CRC16-CCITT-FALSE covers each 32-byte block. Addresses are implicit/sequential.
// Every block is CRC checked before SDRAM write; model_loaded waits for final ack.
// Any corrupt upload requires reset/retry and never enables the codec.
module uart_sdram_model_loader #(
    parameter MODEL_BLOCKS=8448
) (
    input clk,input rst_n,input rx_valid,output rx_ready,input [7:0] rx_data,
    input sdram_initialized,
    output write_valid,input write_ready,output [25:0] write_addr,output [255:0] write_data,
    input write_rsp_valid,output write_rsp_ready,
    output reg model_loaded,output reg error,output reg [15:0] blocks_written
);
localparam MAGIC=0,DATA=1,CRC_LOW=2,CRC_HIGH=3,ISSUE=4,WAIT_ACK=5,DONE=6,FAILED=7;
reg [2:0] state;
reg [1:0] magic_index;
reg [4:0] byte_index;
reg [255:0] buffer;
reg [15:0] crc;
reg [7:0] crc_low;
wire [31:0] magic=32'h31524453;
wire fire=rx_valid && rx_ready;
assign rx_ready=sdram_initialized && state<=CRC_HIGH;
assign write_valid=state==ISSUE;
assign write_addr={5'd0,blocks_written,5'd0};
assign write_data=buffer;
assign write_rsp_ready=state==WAIT_ACK;
function [15:0] crc16;
    input [15:0] prior;input [7:0] b;reg [15:0] c;integer k;
    begin c=prior^{b,8'd0};for(k=0;k<8;k=k+1)c=c[15]?((c<<1)^16'h1021):(c<<1);crc16=c;end
endfunction
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin state<=MAGIC;magic_index<=0;byte_index<=0;buffer<=0;crc<=16'hffff;
        crc_low<=0;model_loaded<=0;error<=0;blocks_written<=0;end
    else begin
        if(fire)case(state)
        MAGIC: if(rx_data==magic[magic_index*8+:8])begin
            if(magic_index==3)begin state<=DATA;crc<=16'hffff;end else magic_index<=magic_index+1;
        end else begin error<=1;state<=FAILED;end
        DATA: begin
            buffer[byte_index*8+:8]<=rx_data;crc<=crc16(crc,rx_data);
            if(byte_index==31)state<=CRC_LOW;else byte_index<=byte_index+1;
        end
        CRC_LOW:begin crc_low<=rx_data;state<=CRC_HIGH;end
        CRC_HIGH: if({rx_data,crc_low}==crc)state<=ISSUE;else begin error<=1;state<=FAILED;end
        endcase
        if(state==ISSUE && write_ready)state<=WAIT_ACK;
        if(state==WAIT_ACK && write_rsp_valid)begin
            blocks_written<=blocks_written+1;
            if(blocks_written==MODEL_BLOCKS-1)begin model_loaded<=1;state<=DONE;end
            else begin byte_index<=0;crc<=16'hffff;state<=DATA;end
        end
    end
end
endmodule
