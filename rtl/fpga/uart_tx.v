`timescale 1ns/1ps

// 8N1 UART 发送。valid&&ready 时锁存一个字节，低位先发；ready 表示空闲。
module uart_tx #(
    parameter CLK_HZ=50000000, parameter BAUD=921600,
    parameter TICKS_PER_BIT=(CLK_HZ+BAUD/2)/BAUD
) (
    input clk, input rst_n,
    input valid, output ready, input [7:0] data,
    output reg tx
);
reg busy;
reg [15:0] timer;
reg [3:0] bit_index;
reg [9:0] shift;
assign ready=!busy;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin busy<=0;timer<=0;bit_index<=0;shift<=10'h3ff;tx<=1; end
    else if (!busy) begin
        tx<=1;
        if (valid) begin
            shift<={1'b1,data,1'b0};
            busy<=1; timer<=TICKS_PER_BIT-1;bit_index<=0;tx<=0;
        end
    end else if (timer!=0) timer<=timer-1'b1;
    else begin
        if (bit_index==4'd9) begin busy<=0;tx<=1; end
        else begin
            bit_index<=bit_index+1'b1;
            tx<=shift[bit_index+1'b1];
            timer<=TICKS_PER_BIT-1;
        end
    end
end
endmodule
