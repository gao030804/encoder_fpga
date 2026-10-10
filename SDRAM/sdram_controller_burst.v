`timescale 1ns/1ps
// DE10-Lite 32Mx16 geometry from sdram_controllder_de2.v.
// New bounded transaction interface: aligned 32 bytes = two BL8 transfers.
// Commands/DQ change at clk rising edge; SDRAM samples the inverted clock.
// One clock domain, CL3. No unbuffered DQ backpressure or row-crossing burst.
module sdram_controller_burst #(
    parameter INIT_CYCLES=10000, parameter REFRESH_CYCLES=350,
    parameter TRCD=2, parameter TRP=2, parameter TRFC=5, parameter TWR=2
) (
    input clk,input rst_n,
    input req_valid,output req_ready,input req_write,
    input [25:0] req_addr,input [255:0] req_data,
    output reg rsp_valid,input rsp_ready,output reg [255:0] rsp_data,
    output reg initialized,output reg error,output busy,
    output reg [31:0] refresh_count,
    output [12:0] dram_addr,output [1:0] dram_bank,
    output dram_cas_n,dram_ras_n,dram_we_n,dram_cs_n,dram_cke,dram_clk,
    output dram_ldqm,dram_udqm,inout [15:0] dram_dq
);
localparam POWER=0,IPRE=1,IREF=2,IMODE=3,IDLE=4,ACT=5,RW=6,
           RWAIT=7,RDATA=8,WDATA=9,RECOVERY=10,PRE=11,RESP=12,
           REFRESH=13,DELAY=14;
reg [3:0] state,after_delay;
reg [31:0] timer,refresh_timer;
reg [3:0] init_refresh;
reg [24:0] word_addr;
reg [255:0] write_data;
reg write_q,second;
reg [2:0] beat;
reg [12:0] address;
reg [1:0] bank;
reg [2:0] command;
reg dq_enable;
reg [15:0] dq_data;
assign dram_addr=address;assign dram_bank=bank;
assign {dram_ras_n,dram_cas_n,dram_we_n}=command;
assign dram_cs_n=!rst_n;assign dram_cke=rst_n;assign dram_clk=~clk;
assign dram_ldqm=0;assign dram_udqm=0;
assign dram_dq=dq_enable ? dq_data : 16'bz;
assign req_ready=initialized && state==IDLE && refresh_timer<REFRESH_CYCLES;
assign busy=state!=IDLE;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state<=POWER;after_delay<=IDLE;timer<=INIT_CYCLES;
        initialized<=0;error<=0;refresh_count<=0;refresh_timer<=0;
        rsp_valid<=0;rsp_data<=0;word_addr<=0;write_data<=0;
        write_q<=0;second<=0;beat<=0;init_refresh<=0;
        address<=0;bank<=0;command<=3'b111;dq_enable<=0;dq_data<=0;
    end else begin
        command<=3'b111;dq_enable<=0;
        if(initialized && refresh_timer<REFRESH_CYCLES) refresh_timer<=refresh_timer+1;
        case(state)
        POWER: if(timer==0) state<=IPRE; else timer<=timer-1;
        IPRE: begin
            command<=3'b010;address<=13'h400;bank<=0;
            timer<=TRP-1;after_delay<=IREF;state<=DELAY;
        end
        IREF: begin
            command<=3'b001;init_refresh<=init_refresh+1;
            timer<=TRFC-1;after_delay<=(init_refresh==7)?IMODE:IREF;state<=DELAY;
        end
        IMODE: begin
            command<=3'b000;address<=13'h033;bank<=0; // BL8 sequential CL3
            timer<=2;after_delay<=IDLE;state<=DELAY;
            initialized<=1;refresh_timer<=0;
        end
        IDLE: begin
            if(refresh_timer>=REFRESH_CYCLES) state<=REFRESH;
            else if(req_valid && req_ready) begin
                if(req_addr[4:0]!=0) begin error<=1;end
                else begin
                    word_addr<=req_addr[25:1];write_data<=req_data;
                    write_q<=req_write;second<=0;state<=ACT;
                end
            end
        end
        ACT: begin
            command<=3'b011;address<=word_addr[22:10];bank<=word_addr[24:23];
            timer<=TRCD-1;after_delay<=RW;state<=DELAY;
        end
        RW: begin
            command<=write_q ? 3'b100 : 3'b101;
            address<={3'b000,word_addr[9:0]}+(second?13'd8:13'd0);
            bank<=word_addr[24:23];beat<=0;
            if(write_q) begin
                dq_enable<=1;dq_data<=write_data[second*128+:16];
                beat<=1;state<=WDATA;
            end else begin timer<=2;state<=RWAIT;end
        end
        RWAIT: if(timer==1) begin timer<=0;state<=RDATA;end else timer<=timer-1;
        RDATA: begin
            rsp_data[(second*8+beat)*16+:16]<=dram_dq;
            if(beat==7) begin
                if(second) state<=PRE;else begin second<=1;state<=RW;end
            end else beat<=beat+1;
        end
        WDATA: begin
            dq_enable<=1;dq_data<=write_data[(second*8+beat)*16+:16];
            if(beat==7) begin
                if(second) begin timer<=TWR;state<=RECOVERY;end
                else begin second<=1;state<=RW;end
            end else beat<=beat+1;
        end
        RECOVERY: if(timer==0) state<=PRE;else timer<=timer-1;
        PRE: begin
            command<=3'b010;address<=13'h400;
            timer<=TRP-1;after_delay<=RESP;state<=DELAY;
        end
        RESP: begin
            rsp_valid<=1;
            if(rsp_valid && rsp_ready) begin rsp_valid<=0;state<=IDLE;end
        end
        REFRESH: begin
            command<=3'b001;refresh_count<=refresh_count+1;refresh_timer<=0;
            timer<=TRFC-1;after_delay<=IDLE;state<=DELAY;
        end
        DELAY: if(timer==0) state<=after_delay;else timer<=timer-1;
        default: begin error<=1;state<=POWER;timer<=INIT_CYCLES;initialized<=0;end
        endcase
    end
end
endmodule
