`timescale 1ns/1ps

// 单时钟、首字直通的字节 FIFO。输入/输出均按 valid && ready 握手。
// DEPTH 必须是 2 的整数次幂；存储无复位，读写指针和占用量复位。
module stream_byte_fifo #(
    parameter DEPTH=1024,
    parameter ADDR_WIDTH=10,
    parameter DROP_ON_FULL=0 // 无法接受反压的UART RX置1；普通valid/ready接口置0
) (
    input clk, input rst_n,
    input in_valid, output in_ready, input [7:0] in_data,
    output out_valid, input out_ready, output reg [7:0] out_data,
    output reg [ADDR_WIDTH:0] level,
    output reg overflow
);
reg [7:0] mem [0:DEPTH-1];
reg [ADDR_WIDTH-1:0] wr_ptr, rd_ptr;
wire push=in_valid && in_ready;
wire pop=out_valid && out_ready;
assign in_ready=(level<DEPTH);
assign out_valid=(level!=0);
// Registered head; bypass a just-written empty head. No reset on data/RAM.
wire [ADDR_WIDTH-1:0] next_rd_ptr=rd_ptr+1'b1;
always @(posedge clk)begin
    if(push)mem[wr_ptr]<=in_data;
    if(pop && level>1)out_data<=mem[next_rd_ptr];
    else if(push && (level==0 || (pop && level==1)))out_data<=in_data;
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr<=0; rd_ptr<=0; level<=0; overflow<=0;
    end else begin
        if (push) wr_ptr<=wr_ptr+1'b1;
        if (pop) rd_ptr<=rd_ptr+1'b1;
        case ({push,pop})
            2'b10: level<=level+1'b1;
            2'b01: level<=level-1'b1;
            default: level<=level;
        endcase
        if (DROP_ON_FULL && in_valid && !in_ready) overflow<=1'b1;
    end
end
endmodule
