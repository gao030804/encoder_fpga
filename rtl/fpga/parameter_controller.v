`timescale 1ns/1ps

// Flash Boot 镜像的 0x28000..0x35fff 参数区：上电写 RAM，随后读出
// Residual/PCM 全局配置，并按 physical_layer/output_group 返回 112B 参数组。
// 层起始偏移来自当前 encoder_manifest 的固定版本；换模型必须同时重生成此表。
module parameter_controller (
    input clk, input rst_n,
    input boot_write, input [12:0] boot_block, input [255:0] boot_data,
    input boot_done,
    output reg configured,
    output reg [31:0] pcm_multiplier,
    output reg [5:0] pcm_shift,
    input [5:0] physical_layer,
    output [119:0] residual_scale_params,
    input param_req_valid, output param_req_ready,
    input [5:0] param_layer, input [5:0] param_output_group,
    output param_rsp_valid, input param_rsp_ready,
    output [511:0] param_bias_data,
    output [255:0] param_mult_data,
    output [63:0] param_shift_data,
    output [63:0] param_zero_point_data
);
localparam S_BOOT=3'd0, S_RES_REQ=3'd1, S_RES_WAIT=3'd2,
           S_PCM_REQ=3'd3, S_PCM_WAIT=3'd4, S_READY=3'd5;
reg [2:0] state;
reg [6:0] residual_index;
reg [119:0] residual_regs [0:63];
wire store_req_ready, store_rsp_valid;
wire [895:0] store_rsp_data;
wire store_req_valid = (state==S_RES_REQ || state==S_PCM_REQ) ? 1'b1 :
                       (state==S_READY && param_req_valid);
wire [31:0] store_req_addr = (state==S_RES_REQ) ?
    (32'h00035000 + {21'd0,residual_index,4'b0000}) :
    (state==S_PCM_REQ) ? 32'h00035400 :
    (layer_base(param_layer) + param_output_group*32'd112);
wire store_rsp_ready = (state==S_RES_WAIT || state==S_PCM_WAIT) ? 1'b1 :
                       (state==S_READY && param_rsp_ready);
assign param_req_ready = (state==S_READY) && store_req_ready;
assign param_rsp_valid = (state==S_READY) && store_rsp_valid;
assign param_bias_data = store_rsp_data[511:0];
assign param_mult_data = store_rsp_data[767:512];
assign param_shift_data = store_rsp_data[831:768];
assign param_zero_point_data = store_rsp_data[895:832];
assign residual_scale_params = residual_regs[physical_layer];

flash_boot_parameter_store u_store (
    .clk(clk), .rst_n(rst_n), .boot_write(boot_write),
    .boot_block(boot_block), .boot_data(boot_data), .boot_done(boot_done),
    .req_valid(store_req_valid), .req_ready(store_req_ready),
    .req_addr(store_req_addr), .rsp_valid(store_rsp_valid),
    .rsp_ready(store_rsp_ready), .rsp_data(store_rsp_data)
);

integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_BOOT;
        configured <= 1'b0;
        residual_index <= 0;
        pcm_multiplier <= 0;
        pcm_shift <= 0;
        for (i=0;i<64;i=i+1) residual_regs[i] <= 0;
    end else begin
        case (state)
            S_BOOT: if (boot_done) state <= S_RES_REQ;
            S_RES_REQ: if (store_req_ready) state <= S_RES_WAIT;
            S_RES_WAIT: if (store_rsp_valid) begin
                residual_regs[residual_index[5:0]] <= store_rsp_data[119:0];
                if (residual_index==7'd63) state <= S_PCM_REQ;
                else begin
                    residual_index <= residual_index+1'b1;
                    state <= S_RES_REQ;
                end
            end
            S_PCM_REQ: if (store_req_ready) state <= S_PCM_WAIT;
            S_PCM_WAIT: if (store_rsp_valid) begin
                pcm_multiplier <= store_rsp_data[31:0];
                pcm_shift <= store_rsp_data[37:32];
                configured <= 1'b1;
                state <= S_READY;
            end
            default: state <= S_READY;
        endcase
    end
end

function [31:0] layer_base;
    input [5:0] layer;
    begin
        case (layer)
            6'd0: layer_base=32'h00028000;
            6'd1: layer_base=32'h000280e0;
            6'd2: layer_base=32'h000281c0;
            6'd3: layer_base=32'h000282a0;
            6'd4: layer_base=32'h00028380;
            6'd5: layer_base=32'h00028460;
            6'd6: layer_base=32'h00028540;
            6'd7: layer_base=32'h00028620;
            6'd8: layer_base=32'h000287e0;
            6'd9: layer_base=32'h000289a0;
            6'd10: layer_base=32'h00028a10;
            6'd11: layer_base=32'h00028bd0;
            6'd12: layer_base=32'h00028c40;
            6'd13: layer_base=32'h00028e00;
            6'd14: layer_base=32'h00028fc0;
            6'd15: layer_base=32'h00029030;
            6'd16: layer_base=32'h000291f0;
            6'd17: layer_base=32'h00029260;
            6'd18: layer_base=32'h00029420;
            6'd19: layer_base=32'h000295e0;
            6'd20: layer_base=32'h00029650;
            6'd21: layer_base=32'h00029810;
            6'd22: layer_base=32'h00029880;
            6'd23: layer_base=32'h00029a40;
            6'd24: layer_base=32'h00029c00;
            6'd25: layer_base=32'h00029ce0;
            6'd26: layer_base=32'h0002a060;
            6'd27: layer_base=32'h0002a3e0;
            6'd28: layer_base=32'h0002a4c0;
            6'd29: layer_base=32'h0002a840;
            6'd30: layer_base=32'h0002a920;
            6'd31: layer_base=32'h0002aca0;
            6'd32: layer_base=32'h0002b020;
            6'd33: layer_base=32'h0002b100;
            6'd34: layer_base=32'h0002b480;
            6'd35: layer_base=32'h0002b560;
            6'd36: layer_base=32'h0002b8e0;
            6'd37: layer_base=32'h0002bc60;
            6'd38: layer_base=32'h0002bd40;
            6'd39: layer_base=32'h0002c0c0;
            6'd40: layer_base=32'h0002c1a0;
            6'd41: layer_base=32'h0002c520;
            6'd42: layer_base=32'h0002c8a0;
            6'd43: layer_base=32'h0002ca60;
            6'd44: layer_base=32'h0002d160;
            6'd45: layer_base=32'h0002d860;
            6'd46: layer_base=32'h0002da20;
            6'd47: layer_base=32'h0002e120;
            6'd48: layer_base=32'h0002e2e0;
            6'd49: layer_base=32'h0002e9e0;
            6'd50: layer_base=32'h0002f0e0;
            6'd51: layer_base=32'h0002f2a0;
            6'd52: layer_base=32'h0002f9a0;
            6'd53: layer_base=32'h0002fb60;
            6'd54: layer_base=32'h00030260;
            6'd55: layer_base=32'h00030960;
            6'd56: layer_base=32'h00030b20;
            6'd57: layer_base=32'h00031220;
            6'd58: layer_base=32'h000313e0;
            6'd59: layer_base=32'h00031ae0;
            6'd60: layer_base=32'h000321e0;
            6'd61: layer_base=32'h00032560;
            6'd62: layer_base=32'h00033360;
            default: layer_base=32'h00028000;
        endcase
    end
endfunction
endmodule
