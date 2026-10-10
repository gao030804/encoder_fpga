`timescale 1ns/1ps

// FPGA_TARGET 下使用的同步 RAM 模板。无复位存储阵列、同步读、按字节写掩码；
// 读使能后的数据在时钟沿更新，外围 OpenTitan 适配器继续产生一周期 rvalid。
// 具体映射为 BRAM、M20K 或寄存器由目标 FPGA 综合器决定，不假定 ASIC 宏存在。
module fpga_sram_1p #(
    parameter WIDTH = 128,
    parameter DEPTH = 512,
    parameter DATA_BITS_PER_MASK = 8,
    parameter ADDR_WIDTH = 9
) (
    input clk,
    input req,
    input write,
    input [ADDR_WIDTH-1:0] addr,
    input [WIDTH-1:0] wdata,
    input [WIDTH-1:0] wmask,
    output reg [WIDTH-1:0] rdata
);
reg [WIDTH-1:0] mem [0:DEPTH-1];
integer lane;
always @(posedge clk) begin
    if (req && addr < DEPTH) begin
        if (write) begin
            for (lane=0; lane<WIDTH/DATA_BITS_PER_MASK; lane=lane+1)
                if (&wmask[lane*DATA_BITS_PER_MASK +: DATA_BITS_PER_MASK])
                    mem[addr][lane*DATA_BITS_PER_MASK +: DATA_BITS_PER_MASK] <=
                        wdata[lane*DATA_BITS_PER_MASK +: DATA_BITS_PER_MASK];
        end else begin
            rdata <= mem[addr];
        end
    end
end
endmodule

// 真正的一写一读：同一周期可访问不同地址。相同地址读写的返回值依赖
// FPGA 原语，系统控制器必须避免依赖其结果。
module fpga_sram_1r1w #(
    parameter WIDTH = 40,
    parameter DEPTH = 320,
    parameter DATA_BITS_PER_MASK = 40,
    parameter ADDR_WIDTH = 9
) (
    input clk,
    input wr_req,
    input [ADDR_WIDTH-1:0] wr_addr,
    input [WIDTH-1:0] wr_data,
    input [WIDTH-1:0] wr_mask,
    input rd_req,
    input [ADDR_WIDTH-1:0] rd_addr,
    output reg [WIDTH-1:0] rd_data
);
reg [WIDTH-1:0] mem [0:DEPTH-1];
integer lane;
always @(posedge clk) begin
    if (wr_req && wr_addr < DEPTH)
        for (lane=0; lane<WIDTH/DATA_BITS_PER_MASK; lane=lane+1)
            if (&wr_mask[lane*DATA_BITS_PER_MASK +: DATA_BITS_PER_MASK])
                mem[wr_addr][lane*DATA_BITS_PER_MASK +: DATA_BITS_PER_MASK] <=
                    wr_data[lane*DATA_BITS_PER_MASK +: DATA_BITS_PER_MASK];
    if (rd_req && rd_addr < DEPTH)
        rd_data <= mem[rd_addr];
end
endmodule
