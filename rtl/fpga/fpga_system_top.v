`timescale 1ns/1ps

// 板卡无关的最小 PC <-> FPGA <-> PC 实验顶层。
// clk50_in 必须为 50 MHz；UART 921600 8N1；外部 Flash 为现有 QSPI 接口。
// 板卡 PLL、IO pin/电压约束以及 Flash 实际引脚必须在选定开发板后补齐。
module fpga_system_top #(
    // Legacy Flash mode stays available. DE10 board top selects USE_SDRAM=1.
    // BOOT_UART_BAUD differs only in accelerated simulation; board defaults match.
    parameter UART_BAUD=921600,
    parameter USE_SDRAM=0,
    parameter BOOT_UART_BAUD=UART_BAUD
) (
    output [12:0] DRAM_ADDR,output [1:0] DRAM_BA,
    output DRAM_CAS_N,DRAM_RAS_N,DRAM_WE_N,DRAM_CS_N,DRAM_CKE,DRAM_CLK,
    output DRAM_LDQM,DRAM_UDQM,inout [15:0] DRAM_DQ,
    output model_loaded,output sdram_error,
    input clk50_in, input ext_reset_n, input pll_locked,
    input uart_rx_pin, output uart_tx_pin,
    output flash_csn, output flash_sclk,
    inout flash_mosi, inout flash_miso, inout flash_wp, inout flash_hold,
    output [3:0] led, output [31:0] debug_status,
    output [2:0] rx_frame_level,
    output [31:0] received_frames,encoded_frames,sent_frames,
    output [31:0] last_service_cycles,worst_service_cycles,
    output [2:0] max_fifo_occupied,output realtime_fault
);
wire clk,rst_n;
clock_reset_ctrl u_reset (
    .clk50_in(clk50_in),.ext_reset_n(ext_reset_n),
    .pll_locked(pll_locked),.clk50(clk),.rst_n(rst_n)
);

wire rx_byte_valid,rx_framing_error;
wire audio_rx_valid,audio_rx_error,boot_rx_valid,boot_rx_error;
wire [7:0] audio_rx_byte,boot_rx_byte;
wire [7:0] rx_byte;
assign rx_byte_valid=(USE_SDRAM && !model_loaded)?boot_rx_valid:audio_rx_valid;
assign rx_framing_error=(USE_SDRAM && !model_loaded)?boot_rx_error:audio_rx_error;
assign rx_byte=(USE_SDRAM && !model_loaded)?boot_rx_byte:audio_rx_byte;
uart_rx #(.BAUD(BOOT_UART_BAUD)) u_boot_uart_rx (.clk(clk),.rst_n(rst_n),.rx(uart_rx_pin),
    .valid(boot_rx_valid),.data(boot_rx_byte),.framing_error(boot_rx_error));
uart_rx #(.BAUD(UART_BAUD)) u_uart_rx (.clk(clk),.rst_n(rst_n),.rx(uart_rx_pin),
                   .valid(audio_rx_valid),.data(audio_rx_byte),
                   .framing_error(audio_rx_error));
wire rx_stream_valid,rx_stream_ready,rx_overflow;
wire [7:0] rx_stream_data;
stream_byte_fifo #(.DEPTH(1024),.ADDR_WIDTH(10),.DROP_ON_FULL(1)) u_rx_fifo (
    .clk(clk),.rst_n(rst_n),.in_valid(rx_byte_valid),.in_ready(),
    .in_data(rx_byte),.out_valid(rx_stream_valid),
    .out_ready(rx_stream_ready),.out_data(rx_stream_data),
    .level(),.overflow(rx_overflow)
);
wire tx_stream_valid,tx_stream_ready,tx_overflow;
wire [7:0] tx_stream_data;
wire uart_tx_valid,uart_tx_ready;
wire [7:0] uart_tx_data;
stream_byte_fifo #(.DEPTH(64),.ADDR_WIDTH(6)) u_tx_fifo (
    .clk(clk),.rst_n(rst_n),.in_valid(tx_stream_valid),
    .in_ready(tx_stream_ready),.in_data(tx_stream_data),
    .out_valid(uart_tx_valid),.out_ready(uart_tx_ready),
    .out_data(uart_tx_data),.level(),.overflow(tx_overflow)
);
uart_tx #(.BAUD(UART_BAUD)) u_uart_tx (.clk(clk),.rst_n(rst_n),.valid(uart_tx_valid),
                   .ready(uart_tx_ready),.data(uart_tx_data),.tx(uart_tx_pin));

wire frame_valid,frame_ready,sample_valid,sample_ready;
wire [31:0] host_frame_id;
wire [15:0] sample_data;
wire packet_sent,packet_error;
wire reserve_valid,reserve_ready,pcm_write,pcm_commit,pcm_abort;
wire [31:0] reserve_id;
wire [8:0] pcm_write_index;
wire [15:0] pcm_write_data;
wire slot_released,frame_committed,queue_error;
wire credit_valid,credit_ready,credit_refresh;
wire [31:0] credit_total;
wire reject_valid,reject_ready;
wire [31:0] reject_id;
wire [7:0] reject_reason;
wire dma_valid,dma_ready,dma_last;
wire [127:0] dma_data;
wire [15:0] dma_keep;
wire packet_rx_ready,model_rx_ready;
assign rx_stream_ready=(USE_SDRAM && !model_loaded)?model_rx_ready:packet_rx_ready;
wire [2:0] sdram_rd_valid,sdram_rd_ready,sdram_rsp_valid,sdram_rsp_ready;
wire [77:0] sdram_rd_addr;
wire [255:0] sdram_read_data;
wire memory_initialized,model_loader_error;
wire [15:0] model_blocks_written;
generate if(USE_SDRAM)begin : g_sdram
    wire boot_valid,boot_accept,boot_ack,boot_ack_ready;
    wire [25:0] boot_addr;
    wire [255:0] boot_data;
    wire mem_valid,mem_ready,mem_write,mem_rsp_valid,mem_rsp_ready,controller_error;
    wire [25:0] mem_addr;
    wire [255:0] mem_wdata,mem_rdata;
    uart_sdram_model_loader u_model_loader (
        .clk(clk),.rst_n(rst_n),.rx_valid(rx_stream_valid),.rx_ready(model_rx_ready),.rx_data(rx_stream_data),
        .sdram_initialized(memory_initialized),.write_valid(boot_valid),.write_ready(boot_accept),
        .write_addr(boot_addr),.write_data(boot_data),.write_rsp_valid(boot_ack),.write_rsp_ready(boot_ack_ready),
        .model_loaded(model_loaded),.error(model_loader_error),.blocks_written(model_blocks_written)
    );
    sdram_arbiter u_arbiter (
        .clk(clk),.rst_n(rst_n),.model_loaded(model_loaded),
        .boot_valid(boot_valid),.boot_ready(boot_accept),.boot_addr(boot_addr),.boot_data(boot_data),
        .boot_rsp_valid(boot_ack),.boot_rsp_ready(boot_ack_ready),
        .rd_valid(sdram_rd_valid),.rd_ready(sdram_rd_ready),.rd_addr(sdram_rd_addr),
        .rsp_valid(sdram_rsp_valid),.rsp_ready(sdram_rsp_ready),.rsp_data(sdram_read_data),
        .req_valid(mem_valid),.req_ready(mem_ready),.req_write(mem_write),.req_addr(mem_addr),.req_data(mem_wdata),
        .mem_rsp_valid(mem_rsp_valid),.mem_rsp_ready(mem_rsp_ready),.mem_rsp_data(mem_rdata),
        .owner(),.outstanding()
    );
    sdram_controller_burst u_controller (
        .clk(clk),.rst_n(rst_n),.req_valid(mem_valid),.req_ready(mem_ready),.req_write(mem_write),
        .req_addr(mem_addr),.req_data(mem_wdata),.rsp_valid(mem_rsp_valid),.rsp_ready(mem_rsp_ready),.rsp_data(mem_rdata),
        .initialized(memory_initialized),.error(controller_error),.busy(),.refresh_count(),
        .dram_addr(DRAM_ADDR),.dram_bank(DRAM_BA),.dram_cas_n(DRAM_CAS_N),.dram_ras_n(DRAM_RAS_N),
        .dram_we_n(DRAM_WE_N),.dram_cs_n(DRAM_CS_N),.dram_cke(DRAM_CKE),.dram_clk(DRAM_CLK),
        .dram_ldqm(DRAM_LDQM),.dram_udqm(DRAM_UDQM),.dram_dq(DRAM_DQ)
    );
    assign sdram_error=controller_error || model_loader_error;
end else begin : g_no_sdram
    assign model_loaded=0;assign model_rx_ready=0;assign memory_initialized=0;
    assign sdram_error=0;assign model_loader_error=0;assign model_blocks_written=0;
    assign sdram_rd_ready=0;assign sdram_rsp_valid=0;assign sdram_read_data=0;
    assign DRAM_ADDR=0;assign DRAM_BA=0;assign DRAM_DQ=16'bz;
    assign {DRAM_CAS_N,DRAM_RAS_N,DRAM_WE_N,DRAM_CS_N}=4'hf;
    assign DRAM_CKE=0;assign DRAM_CLK=0;assign DRAM_LDQM=1;assign DRAM_UDQM=1;
end endgenerate
uart_packet_ctrl u_packets (
    .clk(clk),.rst_n(rst_n),.rx_valid(rx_stream_valid && (!USE_SDRAM || model_loaded)),
    .rx_ready(packet_rx_ready),.rx_data(rx_stream_data),
    .reserve_valid(reserve_valid),.reserve_ready(reserve_ready),.reserve_id(reserve_id),
    .write_valid(pcm_write),.write_index(pcm_write_index),.write_data(pcm_write_data),
    .commit(pcm_commit),.abort_frame(pcm_abort),
    .reject_valid(reject_valid),.reject_ready(reject_ready),
    .reject_id(reject_id),.reject_reason(reject_reason),.credit_refresh(credit_refresh),.packet_error(packet_error)
);
// 独立PCM队列接收下一帧，不访问编码中的Activation SRAM。
pcm_frame_fifo u_pcm_queue (
    .clk(clk),.rst_n(rst_n),.reserve_valid(reserve_valid),.reserve_ready(reserve_ready),.reserve_id(reserve_id),
    .write_valid(pcm_write),.write_index(pcm_write_index),.write_data(pcm_write_data),
    .commit(pcm_commit),.abort_frame(pcm_abort),
    .frame_valid(frame_valid),.frame_ready(frame_ready),.frame_id(host_frame_id),
    .sample_valid(sample_valid),.sample_ready(sample_ready),.sample_data(sample_data),
    .slot_released(slot_released),.frame_committed(frame_committed),
    .occupied(rx_frame_level),.error(queue_error)
);

wire boot_ready,params_ready,front_start,front_done,front_busy;
wire sample_enable,encoder_start,encoder_start_ready;
wire frame_busy,frame_error,encoder_busy,encoder_done,encoder_error,codec_done;
wire [31:0] completed_frames;
wire [31:0] active_frame_id;
credit_flow_ctrl u_credit (
    .clk(clk),.rst_n(rst_n),.link_ready(boot_ready && params_ready && encoder_start_ready),
    .slot_released(slot_released),.refresh(credit_refresh),.credit_valid(credit_valid),
    .credit_ready(credit_ready),.grant_total(credit_total)
);
uart_result_serializer u_serializer (
    .clk(clk),.rst_n(rst_n),.result_valid(dma_valid),.result_ready(dma_ready),.result_record(dma_data),
    .credit_valid(credit_valid),.credit_ready(credit_ready),.credit_total(credit_total),
    .reject_valid(reject_valid),.reject_ready(reject_ready),.reject_id(reject_id),.reject_reason(reject_reason),
    .tx_valid(tx_stream_valid),.tx_ready(tx_stream_ready),.tx_data(tx_stream_data),.result_sent(packet_sent)
);
audio_frame_controller u_frames (
    .clk(clk),.rst_n(rst_n),.boot_ready(boot_ready),.params_ready(params_ready),
    .frame_valid(frame_valid),.frame_ready(frame_ready),.frame_id(host_frame_id),
    .pcm_frontend_start(front_start),.pcm_frontend_done(front_done),
    .sample_enable(sample_enable),.encoder_start_ready(encoder_start_ready),
    .encoder_start(encoder_start),.encoder_done(codec_done),
    .encoder_error(encoder_error),
    .busy(frame_busy),.error(frame_error),.completed_frames(completed_frames),.active_frame_id(active_frame_id)
);
status_perf_counter u_perf (
    .clk(clk),.rst_n(rst_n),.frame_committed(frame_committed),
    .frame_taken(frame_valid && frame_ready),.encode_done(codec_done),.result_sent(packet_sent),
    .fifo_occupied(rx_frame_level),.received_frames(received_frames),.encoded_frames(encoded_frames),.sent_frames(sent_frames),
    .last_service_cycles(last_service_cycles),.worst_service_cycles(worst_service_cycles),
    .max_fifo_occupied(max_fifo_occupied),.realtime_fault(realtime_fault)
);

wire act_wr_valid,act_wr_ready;
wire [31:0] act_wr_addr,act_buffer_base;
wire [63:0] act_wr_data;
wire [7:0] act_wr_strb;
wire pcm_ready;
wire [31:0] pcm_multiplier;
wire [5:0] pcm_shift;
pcm16_input_frontend u_pcm_frontend (
    .clk(clk),.rst_n(rst_n),.start(front_start),
    .cfg_output_base(act_buffer_base),.cfg_sample_count(16'd320),
    .cfg_multiplier(pcm_multiplier),.cfg_shift(pcm_shift),.cfg_zero_point(8'sd0),
    .busy(front_busy),.done(front_done),
    .pcm_valid(sample_valid && sample_enable),
    .pcm_ready(pcm_ready),.pcm_data(sample_data),
    .wr_valid(act_wr_valid),.wr_ready(act_wr_ready),
    .wr_addr(act_wr_addr),.wr_data(act_wr_data),.wr_strb(act_wr_strb)
);
assign sample_ready=sample_enable && pcm_ready;

wire boot_param_write;
wire [12:0] boot_param_block;
wire [255:0] boot_param_data;
wire [119:0] residual_scale_params;
wire [5:0] physical_layer,param_rd_layer,param_rd_group;
wire param_req_valid,param_req_ready,param_rsp_valid,param_rsp_ready;
wire [511:0] param_bias;
wire [255:0] param_mult;
wire [63:0] param_shift,param_zero_point;
parameter_controller #(.USE_SDRAM(USE_SDRAM)) u_parameters (
    .sdram_param_valid(sdram_rd_valid[1]),.sdram_param_ready(sdram_rd_ready[1]),.sdram_param_addr(sdram_rd_addr[26+:26]),
    .sdram_param_rsp_valid(sdram_rsp_valid[1]),.sdram_param_rsp_ready(sdram_rsp_ready[1]),.sdram_param_data(sdram_read_data),
    .clk(clk),.rst_n(rst_n),.boot_write(boot_param_write),
    .boot_block(boot_param_block),.boot_data(boot_param_data),
    .boot_done(boot_ready),.configured(params_ready),
    .pcm_multiplier(pcm_multiplier),.pcm_shift(pcm_shift),
    .physical_layer(physical_layer),.residual_scale_params(residual_scale_params),
    .param_req_valid(param_req_valid),.param_req_ready(param_req_ready),
    .param_layer(param_rd_layer),.param_output_group(param_rd_group),
    .param_rsp_valid(param_rsp_valid),.param_rsp_ready(param_rsp_ready),
    .param_bias_data(param_bias),.param_mult_data(param_mult),
    .param_shift_data(param_shift),.param_zero_point_data(param_zero_point)
);

soundstream_encoder_rvq_w8a16_top #(
    .USE_SDRAM(USE_SDRAM),
    .CLOCK_HZ(50000000),.FLASH_SPI_DIVIDER(16'd1),
    .USE_GLOBAL_WEIGHT_HIERARCHY(1),.FAST_SIM_WEIGHT_CACHE(0),
    .GLOBAL_MODEL_BLOCKS(6912),.BOOT_AUX_BLOCKS(1536),
    .BOOT_FLASH_BASE(24'h010000),.RESIDUAL_SCALE_ALIGN_ENABLE(1)
) u_codec (
    .external_model_ready(model_loaded && !sdram_error),
    .sdram_weight_valid(sdram_rd_valid[0]),.sdram_weight_ready(sdram_rd_ready[0]),.sdram_weight_addr(sdram_rd_addr[0+:26]),
    .sdram_weight_rsp_valid(sdram_rsp_valid[0]),.sdram_weight_rsp_ready(sdram_rsp_ready[0]),.sdram_weight_data(sdram_read_data),
    .sdram_rvq_valid(sdram_rd_valid[2]),.sdram_rvq_ready(sdram_rd_ready[2]),.sdram_rvq_addr(sdram_rd_addr[52+:26]),
    .sdram_rvq_rsp_valid(sdram_rsp_valid[2]),.sdram_rvq_rsp_ready(sdram_rsp_ready[2]),.sdram_rvq_data(sdram_read_data),
    .clk(clk),.rst_n(rst_n),.start(encoder_start),
    .start_ready(encoder_start_ready),.busy(encoder_busy),
    .encoder_done(encoder_done),.done(codec_done),.error(encoder_error),
    .boot_ready(boot_ready),.boot_param_write(boot_param_write),
    .boot_param_block(boot_param_block),.boot_param_data(boot_param_data),
    .boot_aux_write(),.boot_aux_index(),.boot_aux_data(),
    .encoded_valid(),.encoded_indices(),.quantized_vector(),
    .dma_valid(dma_valid),.dma_ready(dma_ready),.dma_data(dma_data),
    .dma_keep(dma_keep),.dma_last(dma_last),
    .output_level(),.output_full(),.output_almost_full(),.output_stall_seen(),
    .input_wr_valid(act_wr_valid),.input_wr_ready(act_wr_ready),
    .input_wr_addr(act_wr_addr),.input_wr_data(act_wr_data),
    .input_wr_strb(act_wr_strb),.input_buffer_select(),
    .input_buffer_base(act_buffer_base),
    .layer_prepare_valid(),.layer_prepare_ready(params_ready),
    .residual_scale_params(residual_scale_params),
    .physical_layer(physical_layer),.logical_layer(),
    // 当前 layer ROM 未启用 ELU；未来启用时必须从模型镜像配置 LUT。
    .elu_lut_cfg_valid(1'b0),.elu_lut_cfg_ready(),
    .elu_lut_cfg_addr(7'd0),.elu_lut_cfg_wdata(8'd0),
    .param_rd_req_valid(param_req_valid),.param_rd_req_ready(param_req_ready),
    .param_rd_layer(param_rd_layer),.param_rd_output_group(param_rd_group),
    .param_rd_rsp_valid(param_rsp_valid),.param_rd_rsp_ready(param_rsp_ready),
    .param_bias_data(param_bias),.param_mult_data(param_mult),
    .param_shift_data(param_shift),.param_zero_point_data(param_zero_point),
    .result_rd_req_valid(1'b0),.result_rd_req_ready(),
    .result_rd_addr0(32'd0),.result_rd_addr1(32'd0),
    .result_rd_addr2(32'd0),.result_rd_addr3(32'd0),
    .result_rd_mask(4'd0),.result_rd_rsp_valid(),
    .result_rd_rsp_ready(1'b1),.result_rd_data(),
    .result_buffer_select(),.result_buffer_base(),
    .layer_write_fire(),.layer_write_addr(),.layer_write_data(),.layer_write_strb(),
    .perf_engine_start(),.perf_engine_done(),.perf_weight_sram_read_fire(),
    .perf_weight_prefetch_fire(),.perf_weight_prefetch_done(),
    .perf_weight_prefetch_base(),.perf_weight_prefetch_blocks(),
    .flash_csn(flash_csn),.flash_sclk(flash_sclk),
    .flash_mosi(flash_mosi),.flash_miso(flash_miso),
    .flash_wp(flash_wp),.flash_hold(flash_hold),
    .octal_cmd_valid(),.octal_cmd_ready(1'b0),
    .octal_cmd_flash_base(),.octal_cmd_byte_count(),
    .octal_phy_clk(clk),.octal_phy_rst_n(rst_n),
    .octal_rx_valid(1'b0),.octal_rx_ready(),
    .octal_rx_data(16'd0),.octal_rx_last(1'b0),.octal_rx_error(1'b0)
);

status_debug_regs u_status (
    .clk(clk),.rst_n(rst_n),.boot_ready(boot_ready),
    .params_ready(params_ready),.frame_busy(frame_busy),
    .encoder_busy(encoder_busy),.encoder_error(encoder_error || frame_error || queue_error || sdram_error),
    .packet_error(packet_error || rx_framing_error),
    .rx_overflow(rx_overflow),.tx_overflow(tx_overflow),
    .completed_frames(completed_frames),.led(led),.debug_status(debug_status)
);
endmodule
