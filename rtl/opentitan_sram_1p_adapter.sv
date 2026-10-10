//=============================================================================
// OpenTitan prim_ram_1p adapter
// - 将按组写掩码扩展为OpenTitan要求的逐bit写掩码
// - 补充同步读响应rvalid_o
//=============================================================================
module opentitan_sram_1p_adapter #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 128,
    parameter int DATA_BITS_PER_MASK = 8,
    parameter MEM_INIT_FILE = "",
    // 每个行为级宏最多512行、128bit；256bit逻辑字由两宏同拍读写。
    parameter int MACRO_DEPTH = 512,
    parameter int MACRO_WIDTH = 128,
    localparam int ADDR_WIDTH = $clog2(DEPTH),
    localparam int MASK_WIDTH = WIDTH / DATA_BITS_PER_MASK
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic                  req_i,
    input  logic                  write_i,
    input  logic [ADDR_WIDTH-1:0] addr_i,
    input  logic [WIDTH-1:0]      wdata_i,
    input  logic [MASK_WIDTH-1:0] wmask_i,
    output logic [WIDTH-1:0]      rdata_o,
    output logic                  rvalid_o
);

logic [WIDTH-1:0] bit_wmask;
localparam int ROWS = (DEPTH < MACRO_DEPTH) ? DEPTH : MACRO_DEPTH;
localparam int COLS = (WIDTH < MACRO_WIDTH) ? WIDTH : MACRO_WIDTH;
localparam int BANKS = (DEPTH + ROWS - 1) / ROWS;
localparam int SLICES = WIDTH / COLS;
localparam int ROW_AW = (ROWS > 1) ? $clog2(ROWS) : 1;
localparam int BANK_AW = (BANKS > 1) ? $clog2(BANKS) : 1;
wire [BANK_AW-1:0] bank_select = addr_i / ROWS;
wire [ROW_AW-1:0] row_address = addr_i % ROWS;
wire [WIDTH-1:0] bank_data [0:BANKS-1];
reg [BANK_AW-1:0] read_bank_q;

// 响应必须使用上一拍读请求的bank，不能使用当前请求地址。
// 写周期/空闲周期保持选择，保持原有SRAM输出保持语义。
always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) read_bank_q <= '0;
    else if (req_i && !write_i) read_bank_q <= bank_select;
end
assign rdata_o = bank_data[read_bank_q];

// 初始化文件必须预先按宏拆分；当前Boot路径通过端口写入，不使用此参数。
// synthesis translate_off
initial begin
    if (WIDTH % COLS != 0 || COLS % DATA_BITS_PER_MASK != 0)
        $fatal(1, "SRAM width/mask cannot be split into macros");
    if (MEM_INIT_FILE != "" && (BANKS != 1 || SLICES != 1))
        $fatal(1, "Banked SRAM must be initialized through write ports");
end
// synthesis translate_on

for (genvar lane = 0; lane < MASK_WIDTH; lane++) begin : gen_mask_expand
    assign bit_wmask[lane*DATA_BITS_PER_MASK +: DATA_BITS_PER_MASK] =
        {DATA_BITS_PER_MASK{wmask_i[lane]}};
end

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
        rvalid_o <= 1'b0;
    else
        rvalid_o <= req_i && !write_i;
end

// gen_depth选择行分段，gen_width选择低/高128bit。
// 只使能被选中的行分段；同组位宽切片共享地址和读写控制。
for (genvar bank = 0; bank < BANKS; bank++) begin : gen_depth
for (genvar slice = 0; slice < SLICES; slice++) begin : gen_width
`ifdef FPGA_TARGET
fpga_sram_1p #(
    .WIDTH(COLS), .DEPTH(ROWS), .DATA_BITS_PER_MASK(DATA_BITS_PER_MASK),
    .ADDR_WIDTH(ROW_AW)
) u_ram (
    .clk(clk_i), .req(req_i && (bank_select == bank) && (addr_i < DEPTH)),
    .write(write_i), .addr(row_address),
    .wdata(wdata_i[slice*COLS +: COLS]),
    .wmask(bit_wmask[slice*COLS +: COLS]),
    .rdata(bank_data[bank][slice*COLS +: COLS])
);
`else
prim_ram_1p_pkg::ram_1p_cfg_rsp_t unused_cfg_rsp;
prim_ram_1p #(
    .Width           (COLS),
    .Depth           (ROWS),
    .DataBitsPerMask (DATA_BITS_PER_MASK),
    .MemInitFile     (MEM_INIT_FILE)
) u_ram (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .req_i   (req_i && (bank_select == bank) && (addr_i < DEPTH)),
    .write_i (write_i),
    .addr_i  (row_address),
    .wdata_i (wdata_i[slice*COLS +: COLS]),
    .wmask_i (bit_wmask[slice*COLS +: COLS]),
    .rdata_o (bank_data[bank][slice*COLS +: COLS]),
    .cfg_i   (prim_ram_1p_pkg::RAM_1P_CFG_REQ_DEFAULT),
    .cfg_o   (unused_cfg_rsp)
);
`endif
end
end

endmodule
