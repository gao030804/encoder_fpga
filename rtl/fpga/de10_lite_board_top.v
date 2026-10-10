`timescale 1ns/1ps
// Arduino D0: USB-UART TX -> FPGA RX; D1: FPGA TX -> USB-UART RX.
// KEY[0] resets the session. UART model/audio baud defaults to 921600 8N1.
module de10_lite_board_top (
    input MAX10_CLK1_50,input [1:0] KEY,
    input UART_RX,output UART_TX,output [9:0] LEDR,
    output [12:0] DRAM_ADDR,output [1:0] DRAM_BA,
    output DRAM_CAS_N,DRAM_RAS_N,DRAM_WE_N,DRAM_CS_N,DRAM_CKE,DRAM_CLK,
    output DRAM_LDQM,DRAM_UDQM,inout [15:0] DRAM_DQ
);
wire [3:0] status_led;
wire model_loaded,sdram_error;
fpga_system_top #(.USE_SDRAM(1)) u_system (
    .clk50_in(MAX10_CLK1_50),.ext_reset_n(KEY[0]),.pll_locked(1'b1),
    .uart_rx_pin(UART_RX),.uart_tx_pin(UART_TX),
    .DRAM_ADDR(DRAM_ADDR),.DRAM_BA(DRAM_BA),.DRAM_CAS_N(DRAM_CAS_N),.DRAM_RAS_N(DRAM_RAS_N),
    .DRAM_WE_N(DRAM_WE_N),.DRAM_CS_N(DRAM_CS_N),.DRAM_CKE(DRAM_CKE),.DRAM_CLK(DRAM_CLK),
    .DRAM_LDQM(DRAM_LDQM),.DRAM_UDQM(DRAM_UDQM),.DRAM_DQ(DRAM_DQ),
    .model_loaded(model_loaded),.sdram_error(sdram_error),.led(status_led)
);
assign LEDR={4'd0,sdram_error,model_loaded,status_led};
endmodule
