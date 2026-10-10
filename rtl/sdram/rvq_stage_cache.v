`timescale 1ns/1ps
// 8 KiB codewords + 1 KiB norms, reused for all nine stages.
// RPREQ starts a bounded fill before returning the stage's scale parameters.
// Projection records are fetched on demand. Candidates use synchronous BRAM.
module rvq_stage_cache (
    input clk,input rst_n,input mem_req,input [15:0] byte_address,input [3:0] stage,
    output reg mem_valid,output reg [255:0] mem_data,
    output line_valid,input line_ready,output [25:0] line_addr,
    input line_rsp_valid,output line_rsp_ready,input [255:0] line_data,
    output reg fill_busy
);
localparam IDLE=0,ISSUE=1,WAIT_DATA=2,CACHED=3;
reg [1:0] state;
reg [25:0] address_q;
reg [8:0] fill_index,entry_count;
reg [5:0] norm_index,norm_count;
reg [10:0] stage_base;
reg [1:0] kind; // 0 direct, 1 codewords, 2 norms, 3 stage parameter
reg [7:0] cache_index;
reg norm_read;
reg [255:0] codewords [0:255];
reg [255:0] norms [0:31];
wire [10:0] entry=(byte_address-16'h0a00)>>5;
wire [10:0] norm_entry=(byte_address-16'haa00)>>2;
assign line_valid=state==ISSUE;
assign line_addr=address_q;
assign line_rsp_ready=state==WAIT_DATA;
always @(posedge clk)begin
    if(state==WAIT_DATA && line_rsp_valid && kind==1)codewords[fill_index[7:0]]<=line_data;
    if(state==WAIT_DATA && line_rsp_valid && kind==2)norms[norm_index[4:0]]<=line_data;
    if(state==CACHED)mem_data<=norm_read?norms[cache_index[4:0]]:codewords[cache_index];
    if(state==WAIT_DATA && line_rsp_valid && (kind==0 || kind==3))mem_data<=line_data;
end
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        state<=IDLE;mem_valid<=0;address_q<=0;fill_index<=0;entry_count<=0;
        norm_index<=0;norm_count<=0;stage_base<=0;kind<=0;cache_index<=0;norm_read<=0;fill_busy<=0;
    end else begin
        mem_valid<=0;
        case(state)
        IDLE: if(mem_req)begin
            if(byte_address>=16'hbe00)begin
                stage_base<=(stage==0)?0:256+(stage-1)*128;
                entry_count<=(stage==0)?256:128;norm_count<=(stage==0)?32:16;
                fill_index<=0;norm_index<=0;kind<=1;fill_busy<=1;
                address_q<=26'h36a00+((stage==0)?0:(256+(stage-1)*128)*32);state<=ISSUE;
            end else if(byte_address>=16'haa00)begin
                norm_read<=1;cache_index<=(norm_entry-stage_base)>>3;state<=CACHED;
            end else if(byte_address>=16'h0a00)begin
                norm_read<=0;cache_index<=entry-stage_base;state<=CACHED;
            end else begin
                kind<=0;address_q<=26'h36000+{byte_address[15:5],5'd0};state<=ISSUE;
            end
        end
        ISSUE: if(line_ready)state<=WAIT_DATA;
        WAIT_DATA: if(line_rsp_valid)begin
            if(kind==1)begin
                if(fill_index+1==entry_count)begin
                    kind<=2;address_q<=26'h40a00+stage_base*4;
                end else begin fill_index<=fill_index+1;address_q<=address_q+32;end
                state<=ISSUE;
            end else if(kind==2)begin
                if(norm_index+1==norm_count)begin kind<=3;address_q<=26'h41e00+stage*32;end
                else begin norm_index<=norm_index+1;address_q<=address_q+32;end
                state<=ISSUE;
            end else begin mem_valid<=1;fill_busy<=0;state<=IDLE;end
        end
        CACHED: begin mem_valid<=1;state<=IDLE;end
        endcase
    end
end
endmodule
