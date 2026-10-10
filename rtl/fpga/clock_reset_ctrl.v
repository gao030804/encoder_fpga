`timescale 1ns/1ps

// 板卡无关时钟/复位边界：输入必须已经是 50 MHz。
// 若开发板晶振不是 50 MHz，应在此模块外实例化厂商 PLL，并把 locked 接入。
module clock_reset_ctrl #(
    parameter RESET_HOLD_CYCLES=32
) (
    input clk50_in, input ext_reset_n, input pll_locked,
    output clk50, output rst_n
);
assign clk50=clk50_in;
reg [15:0] hold_count;
reg reset_released;
reg reset_sync;
always @(posedge clk50_in or negedge ext_reset_n) begin
    if (!ext_reset_n) begin
        hold_count<=0;reset_released<=0;reset_sync<=0;
    end else if (!pll_locked) begin
        hold_count<=0;reset_released<=0;reset_sync<=0;
    end else begin
        if (hold_count<RESET_HOLD_CYCLES) hold_count<=hold_count+1'b1;
        else reset_released<=1'b1;
        reset_sync<=reset_released;
    end
end
assign rst_n=reset_sync;
endmodule
