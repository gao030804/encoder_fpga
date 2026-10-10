`timescale 1ns/1ps
// One outstanding 32-byte transaction. Owner is latched until response accepted.
// Rotation bounds starvation; boot has exclusive access before model_loaded.
module sdram_arbiter (
    input clk,input rst_n,input model_loaded,
    input boot_valid,output boot_ready,input [25:0] boot_addr,input [255:0] boot_data,
    output boot_rsp_valid,input boot_rsp_ready,
    input [2:0] rd_valid,output [2:0] rd_ready,input [77:0] rd_addr,
    output [2:0] rsp_valid,input [2:0] rsp_ready,output [255:0] rsp_data,
    output req_valid,input req_ready,output req_write,
    output [25:0] req_addr,output [255:0] req_data,
    input mem_rsp_valid,output mem_rsp_ready,input [255:0] mem_rsp_data,
    output reg [1:0] owner,output reg outstanding
);
reg [1:0] next_owner;
reg [1:0] chosen;
reg chosen_valid;
integer i,index;
always @* begin
    chosen=0;chosen_valid=0;index=0;
    for(i=0;i<3;i=i+1) begin
        index=next_owner+i;if(index>=3)index=index-3;
        if(!chosen_valid && rd_valid[index]) begin chosen=index;chosen_valid=1;end
    end
end
assign req_valid=!outstanding && (model_loaded ? chosen_valid : boot_valid);
assign req_write=!model_loaded;
assign req_addr=model_loaded ? rd_addr[chosen*26+:26] : boot_addr;
assign req_data=boot_data;
assign boot_ready=!model_loaded && !outstanding && req_ready;
assign rd_ready=(model_loaded && !outstanding && req_ready && chosen_valid) ? (3'b001<<chosen) : 0;
assign boot_rsp_valid=outstanding && owner==3 && mem_rsp_valid;
assign rsp_valid=(outstanding && owner!=3 && mem_rsp_valid)?(3'b001<<owner):0;
assign rsp_data=mem_rsp_data;
assign mem_rsp_ready=outstanding && ((owner==3)?boot_rsp_ready:rsp_ready[owner]);
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin owner<=0;outstanding<=0;next_owner<=0;end
    else begin
        if(req_valid && req_ready)begin owner<=model_loaded?chosen:2'd3;outstanding<=1;end
        if(mem_rsp_valid && mem_rsp_ready)begin
            outstanding<=0;if(owner!=3)next_owner<=(owner==2)?0:owner+1'b1;
        end
    end
end
endmodule
