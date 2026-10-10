`timescale 1ns/1ps

// 8N1 UART 接收；50 MHz / 921600 baud 时取整为 54 clk/bit（约 0.47% 偏差）。
// 输入先经两个寄存器同步，start 位中心确认，随后在每个位中心采样。
module uart_rx #(
    parameter CLK_HZ=50000000, parameter BAUD=921600,
    parameter TICKS_PER_BIT=(CLK_HZ+BAUD/2)/BAUD
) (
    input clk, input rst_n, input rx,
    output reg valid, output reg [7:0] data, output reg framing_error
);
localparam S_IDLE=2'd0,S_START=2'd1,S_DATA=2'd2,S_STOP=2'd3;
reg [1:0] state;
reg rx_meta,rx_sync;
reg [15:0] timer;
reg [2:0] bit_index;
reg [7:0] shift;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_meta<=1;rx_sync<=1;state<=S_IDLE;timer<=0;
        bit_index<=0;shift<=0;valid<=0;data<=0;framing_error<=0;
    end else begin
        rx_meta<=rx;rx_sync<=rx_meta;
        valid<=0;framing_error<=0;
        case (state)
            S_IDLE: if (!rx_sync) begin timer<=TICKS_PER_BIT/2;state<=S_START; end
            S_START: if (timer!=0) timer<=timer-1'b1;
                     else if (!rx_sync) begin timer<=TICKS_PER_BIT-1;bit_index<=0;state<=S_DATA; end
                     else state<=S_IDLE;
            S_DATA: if (timer!=0) timer<=timer-1'b1;
                    else begin
                        shift[bit_index]<=rx_sync;
                        timer<=TICKS_PER_BIT-1;
                        if (bit_index==3'd7) state<=S_STOP;
                        else bit_index<=bit_index+1'b1;
                    end
            S_STOP: if (timer!=0) timer<=timer-1'b1;
                    else begin
                        if (rx_sync) begin data<=shift;valid<=1; end
                        else framing_error<=1;
                        state<=S_IDLE;
                    end
            default: state<=S_IDLE;
        endcase
    end
end
endmodule
