`timescale 1ns/1ps
// Assemble a possibly unaligned 112-byte record from four 32-byte lines.
// Only the response register is retained; no duplicate parameter image.
module sdram_parameter_store (
    input clk,input rst_n,input boot_done,
    input req_valid,output req_ready,input [31:0] req_addr,
    output reg rsp_valid,input rsp_ready,output reg [895:0] rsp_data,
    output line_valid,input line_ready,output [25:0] line_addr,
    input line_rsp_valid,output line_rsp_ready,input [255:0] line_data
);
localparam IDLE=0,ISSUE=1,WAIT_DATA=2,RESPONSE=3;
reg [1:0] state;
reg [31:0] address_q,block_addr;
integer lane,destination;
assign req_ready=boot_done && state==IDLE;
assign line_valid=state==ISSUE;
assign line_addr=block_addr[25:0];
assign line_rsp_ready=state==WAIT_DATA;
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin state<=IDLE;rsp_valid<=0;rsp_data<=0;address_q<=0;block_addr<=0;end
    else case(state)
    IDLE: if(req_valid && req_ready)begin
        address_q<=req_addr;block_addr<={req_addr[31:5],5'd0};rsp_data<=0;state<=ISSUE;
    end
    ISSUE: if(line_ready)state<=WAIT_DATA;
    WAIT_DATA: if(line_rsp_valid)begin
        for(lane=0;lane<32;lane=lane+1)begin
            destination=block_addr+lane-address_q;
            if(destination>=0 && destination<112)rsp_data[destination*8+:8]<=line_data[lane*8+:8];
        end
        if(block_addr+32>=address_q+112)begin rsp_valid<=1;state<=RESPONSE;end
        else begin block_addr<=block_addr+32;state<=ISSUE;end
    end
    RESPONSE: if(rsp_ready)begin rsp_valid<=0;state<=IDLE;end
    endcase
end
endmodule
