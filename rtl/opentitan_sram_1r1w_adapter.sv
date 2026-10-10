//=============================================================================
// OpenTitan prim_ram_1r1w adapter
// Port A只写，Port B只读，读请求后一个周期rvalid_o有效。
//=============================================================================
module opentitan_sram_1r1w_adapter #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 128,
    parameter int DATA_BITS_PER_MASK = 8,
    parameter MEM_INIT_FILE = "",
    localparam int ADDR_WIDTH = $clog2(DEPTH),
    localparam int MASK_WIDTH = WIDTH / DATA_BITS_PER_MASK
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic                  wr_req_i,
    input  logic [ADDR_WIDTH-1:0] wr_addr_i,
    input  logic [WIDTH-1:0]      wr_data_i,
    input  logic [MASK_WIDTH-1:0] wr_mask_i,
    input  logic                  rd_req_i,
    input  logic [ADDR_WIDTH-1:0] rd_addr_i,
    output logic [WIDTH-1:0]      rd_data_o,
    output logic                  rd_valid_o
);

logic [WIDTH-1:0] bit_wmask;
`ifndef FPGA_TARGET
prim_ram_1r1w_pkg::ram_1r1w_cfg_rsp_t unused_cfg_rsp;
`endif

for (genvar lane = 0; lane < MASK_WIDTH; lane++) begin : gen_mask_expand
    assign bit_wmask[lane*DATA_BITS_PER_MASK +: DATA_BITS_PER_MASK] =
        {DATA_BITS_PER_MASK{wr_mask_i[lane]}};
end

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
        rd_valid_o <= 1'b0;
    else
        rd_valid_o <= rd_req_i;
end

`ifdef FPGA_TARGET
fpga_sram_1r1w #(
    .WIDTH(WIDTH), .DEPTH(DEPTH), .DATA_BITS_PER_MASK(DATA_BITS_PER_MASK),
    .ADDR_WIDTH(ADDR_WIDTH)
) u_ram (
    .clk(clk_i), .wr_req(wr_req_i), .wr_addr(wr_addr_i),
    .wr_data(wr_data_i), .wr_mask(bit_wmask),
    .rd_req(rd_req_i), .rd_addr(rd_addr_i), .rd_data(rd_data_o)
);
`else
prim_ram_1r1w #(
    .Width           (WIDTH),
    .Depth           (DEPTH),
    .DataBitsPerMask (DATA_BITS_PER_MASK),
    .MemInitFile     (MEM_INIT_FILE)
) u_ram (
    .clk_a_i   (clk_i),
    .clk_b_i   (clk_i),
    .rst_a_ni  (rst_ni),
    .rst_b_ni  (rst_ni),
    .a_req_i   (wr_req_i),
    .a_addr_i  (wr_addr_i),
    .a_wdata_i (wr_data_i),
    .a_wmask_i (bit_wmask),
    .b_req_i   (rd_req_i),
    .b_addr_i  (rd_addr_i),
    .b_rdata_o (rd_data_o),
    .cfg_i     (prim_ram_1r1w_pkg::RAM_1R1W_CFG_REQ_DEFAULT),
    .cfg_o     (unused_cfg_rsp)
);
`endif

endmodule
