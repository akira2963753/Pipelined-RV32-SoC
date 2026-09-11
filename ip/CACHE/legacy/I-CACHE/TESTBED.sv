/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    TESTBED.sv
* Project:      RISC-V CPU Cache
* Module:       TESTBED
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         Vivado 2025.1
*
* Description:
*   I-Cache integration testbench with the project AXI4 bus, a synchronous
*   behavioral BRAM model, protocol assertions, and self-checking stimulus.
******************************************************************************/

`timescale 1ns/1ps

import AXI4_PKG::*;

module TESTBED;

    localparam int DATA_W = 32;
    localparam int ADDR_W = 32;
    localparam int ID_W = 4;
    localparam int BRAM_DEPTH = 4096;
    localparam int BRAM_ADDR_W = $clog2(BRAM_DEPTH);
    localparam int MEM_FILE_WORDS = 1296;
    localparam string MEM_FILE =
        "C:/Users/harry/Desktop/Project/risc-v/CACHE/I-CACHE/Mem_Data/test_data.mem";

    logic ACLK;
    logic ARESETn;

    logic CPU_REQ;
    logic [ADDR_W-1:0] CPU_REQ_ADDR;
    logic CPU_REQ_VALID;
    logic [DATA_W-1:0] CPU_REQ_DATA;
    logic BUSY;

    logic [ID_W-1:0] AW_ID;
    logic [ADDR_W-1:0] AW_ADDR;
    logic [7:0] AW_LEN;
    logic [2:0] AW_SIZE;
    logic [1:0] AW_BURST;
    logic AW_LOCK;
    logic [3:0] AW_CACHE;
    logic [2:0] AW_PROT;
    logic [3:0] AW_QOS;
    logic AW_VALID;
    logic AW_READY;

    logic [DATA_W-1:0] W_DATA;
    logic [DATA_W/8-1:0] W_STRB;
    logic W_LAST;
    logic W_VALID;
    logic W_READY;

    logic [ID_W-1:0] B_ID;
    resp_type B_RESP;
    logic B_VALID;
    logic B_READY;

    logic [ID_W-1:0] AR_ID;
    logic [ADDR_W-1:0] AR_ADDR;
    logic [7:0] AR_LEN;
    logic [2:0] AR_SIZE;
    logic [1:0] AR_BURST;
    logic AR_LOCK;
    logic [3:0] AR_CACHE;
    logic [2:0] AR_PROT;
    logic [3:0] AR_QOS;
    logic AR_VALID;
    logic AR_READY;

    logic [ID_W-1:0] R_ID;
    logic [DATA_W-1:0] R_DATA;
    resp_type R_RESP;
    logic R_LAST;
    logic R_VALID;
    logic R_READY;

    logic BRAM_EN;
    logic [DATA_W/8-1:0] BRAM_WE;
    logic [BRAM_ADDR_W-1:0] BRAM_ADDR;
    logic [DATA_W-1:0] BRAM_DIN;
    logic [DATA_W-1:0] BRAM_DOUT;
    logic [DATA_W-1:0] bram [0:BRAM_DEPTH-1];

    integer mem_idx;
    integer byte_idx;

    assign AW_ID = '0;
    assign AW_ADDR = '0;
    assign AW_LEN = '0;
    assign AW_SIZE = '0;
    assign AW_BURST = '0;
    assign AW_LOCK = 1'b0;
    assign AW_CACHE = '0;
    assign AW_PROT = '0;
    assign AW_QOS = '0;
    assign AW_VALID = 1'b0;

    assign W_DATA = '0;
    assign W_STRB = '0;
    assign W_LAST = 1'b0;
    assign W_VALID = 1'b0;
    assign B_READY = 1'b0;

    initial begin
        for(mem_idx = 0; mem_idx < BRAM_DEPTH; mem_idx = mem_idx + 1)
            bram[mem_idx] = 32'hA500_0000 ^ mem_idx;

        $readmemh(MEM_FILE, bram, 0, MEM_FILE_WORDS - 1);
    end

    always @(posedge ACLK) begin
        if(BRAM_EN) begin
            if(|BRAM_WE) begin
                for(byte_idx = 0; byte_idx < DATA_W / 8;
                    byte_idx = byte_idx + 1) begin
                    if(BRAM_WE[byte_idx])
                        bram[BRAM_ADDR][byte_idx*8 +: 8] <=
                            BRAM_DIN[byte_idx*8 +: 8];
                end
            end
            else begin
                BRAM_DOUT <= bram[BRAM_ADDR];
            end
        end
    end

    I_Cache #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .ID_W(ID_W),
        .WAY(2),
        .SET(64),
        .BLOCK_WORD_SIZE(8)
    ) u_i_cache (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .CPU_REQ(CPU_REQ),
        .CPU_REQ_ADDR(CPU_REQ_ADDR),
        .CPU_REQ_VALID(CPU_REQ_VALID),
        .CPU_REQ_DATA(CPU_REQ_DATA),
        .BUSY(BUSY),
        .AR_ID(AR_ID),
        .AR_ADDR(AR_ADDR),
        .AR_LEN(AR_LEN),
        .AR_SIZE(AR_SIZE),
        .AR_BURST(AR_BURST),
        .AR_LOCK(AR_LOCK),
        .AR_CACHE(AR_CACHE),
        .AR_PROT(AR_PROT),
        .AR_QOS(AR_QOS),
        .AR_VALID(AR_VALID),
        .AR_READY(AR_READY),
        .R_ID(R_ID),
        .R_DATA(R_DATA),
        .R_RESP(R_RESP),
        .R_LAST(R_LAST),
        .R_VALID(R_VALID),
        .R_READY(R_READY)
    );

    AXI4_Bus #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .ID_W(ID_W),
        .BRAM_DEPTH(BRAM_DEPTH),
        .BRAM_ADDR_W(BRAM_ADDR_W)
    ) u_axi4_bus (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .AW_ID(AW_ID),
        .AW_ADDR(AW_ADDR),
        .AW_LEN(AW_LEN),
        .AW_SIZE(AW_SIZE),
        .AW_BURST(AW_BURST),
        .AW_LOCK(AW_LOCK),
        .AW_CACHE(AW_CACHE),
        .AW_PROT(AW_PROT),
        .AW_QOS(AW_QOS),
        .AW_VALID(AW_VALID),
        .AW_READY(AW_READY),
        .W_DATA(W_DATA),
        .W_STRB(W_STRB),
        .W_LAST(W_LAST),
        .W_VALID(W_VALID),
        .W_READY(W_READY),
        .B_ID(B_ID),
        .B_RESP(B_RESP),
        .B_VALID(B_VALID),
        .B_READY(B_READY),
        .AR_ID(AR_ID),
        .AR_ADDR(AR_ADDR),
        .AR_LEN(AR_LEN),
        .AR_SIZE(AR_SIZE),
        .AR_BURST(AR_BURST),
        .AR_LOCK(AR_LOCK),
        .AR_CACHE(AR_CACHE),
        .AR_PROT(AR_PROT),
        .AR_QOS(AR_QOS),
        .AR_VALID(AR_VALID),
        .AR_READY(AR_READY),
        .R_ID(R_ID),
        .R_DATA(R_DATA),
        .R_RESP(R_RESP),
        .R_LAST(R_LAST),
        .R_VALID(R_VALID),
        .R_READY(R_READY),
        .BRAM_EN(BRAM_EN),
        .BRAM_WE(BRAM_WE),
        .BRAM_ADDR(BRAM_ADDR),
        .BRAM_DIN(BRAM_DIN),
        .BRAM_DOUT(BRAM_DOUT)
    );

    CHECKER #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .ID_W(ID_W),
        .BRAM_DEPTH(BRAM_DEPTH)
    ) u_checker (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .AW_ID(AW_ID),
        .AW_ADDR(AW_ADDR),
        .AW_LEN(AW_LEN),
        .AW_SIZE(AW_SIZE),
        .AW_BURST(AW_BURST),
        .AW_LOCK(AW_LOCK),
        .AW_CACHE(AW_CACHE),
        .AW_PROT(AW_PROT),
        .AW_QOS(AW_QOS),
        .AW_VALID(AW_VALID),
        .AW_READY(AW_READY),
        .W_DATA(W_DATA),
        .W_STRB(W_STRB),
        .W_LAST(W_LAST),
        .W_VALID(W_VALID),
        .W_READY(W_READY),
        .B_ID(B_ID),
        .B_RESP(B_RESP),
        .B_VALID(B_VALID),
        .B_READY(B_READY),
        .AR_ID(AR_ID),
        .AR_ADDR(AR_ADDR),
        .AR_LEN(AR_LEN),
        .AR_SIZE(AR_SIZE),
        .AR_BURST(AR_BURST),
        .AR_LOCK(AR_LOCK),
        .AR_CACHE(AR_CACHE),
        .AR_PROT(AR_PROT),
        .AR_QOS(AR_QOS),
        .AR_VALID(AR_VALID),
        .AR_READY(AR_READY),
        .R_ID(R_ID),
        .R_DATA(R_DATA),
        .R_RESP(R_RESP),
        .R_LAST(R_LAST),
        .R_VALID(R_VALID),
        .R_READY(R_READY)
    );

    PATTERN #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .BRAM_DEPTH(BRAM_DEPTH)
    ) u_pattern (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .CPU_REQ(CPU_REQ),
        .CPU_REQ_ADDR(CPU_REQ_ADDR),
        .CPU_REQ_VALID(CPU_REQ_VALID),
        .CPU_REQ_DATA(CPU_REQ_DATA),
        .BUSY(BUSY),
        .AR_VALID(AR_VALID),
        .AR_READY(AR_READY),
        .R_VALID(R_VALID),
        .R_READY(R_READY),
        .R_LAST(R_LAST)
    );

endmodule
