// 上电参数缓存：接收实际Flash Boot数据流中Global偏移0x28000起的块。
// 64KiB单端口OpenTitan SRAM；上电只写、计算只读，无文件初始化。
// 每次读取112Byte参数记录，允许记录跨越256-bit边界。
// 逻辑2048x256由4组深度bank组成，每组2个512x128宏；跨组读延迟仍为一拍。
// req_addr为Global字节地址；响应按低地址在低位排列，反压时保持。
module flash_boot_parameter_store (
    input clk, input rst_n,
    input boot_write, input [12:0] boot_block, input [255:0] boot_data,
    input boot_done,
    input req_valid, output req_ready, input [31:0] req_addr,
    output reg rsp_valid, input rsp_ready, output reg [895:0] rsp_data
);
localparam IDLE=0, ISSUE=1, WAIT_DATA=2, RESPONSE=3;
reg [1:0] state;
reg [31:0] address_q;
reg [10:0] block_q;
integer byte_lane, destination;
wire write_en = boot_write && boot_block >= 13'd5120 && boot_block < 13'd7168;
wire [10:0] write_addr = boot_block - 13'd5120;
wire [255:0] read_data;
wire read_valid;
assign req_ready = boot_done && state == IDLE;
opentitan_sram_1p_adapter #(.WIDTH(256), .DEPTH(2048), .DATA_BITS_PER_MASK(8)) u_sram (
    .clk_i(clk), .rst_ni(rst_n), .req_i(write_en || state == ISSUE),
    .write_i(write_en), .addr_i(write_en ? write_addr : block_q),
    .wdata_i(boot_data), .wmask_i(32'hffffffff),
    .rdata_o(read_data), .rvalid_o(read_valid)
);
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE; rsp_valid <= 0; rsp_data <= 0;
        address_q <= 0; block_q <= 0;
    end else begin
        case (state)
            IDLE: if (req_valid && req_ready) begin
                address_q <= req_addr - 32'h28000;
                block_q <= (req_addr - 32'h28000) >> 5;
                rsp_data <= 0;
                state <= ISSUE;
            end
            ISSUE: state <= WAIT_DATA;
            WAIT_DATA: if (read_valid) begin
                for (byte_lane=0; byte_lane<32; byte_lane=byte_lane+1) begin
                    destination = block_q*32 + byte_lane - address_q;
                    if (destination >= 0 && destination < 112)
                        rsp_data[8*destination +: 8] <= read_data[8*byte_lane +: 8];
                end
                if ((block_q*32+32) >= address_q+112) begin
                    rsp_valid <= 1; state <= RESPONSE;
                end else begin
                    block_q <= block_q+1'b1; state <= ISSUE;
                end
            end
            RESPONSE: if (rsp_valid && rsp_ready) begin
                rsp_valid <= 0; state <= IDLE;
            end
        endcase
    end
end
endmodule
