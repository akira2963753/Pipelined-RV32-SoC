/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    TESTBED.sv
* Project:      RISC-V CPU Cache
* Module:       TESTBED
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

`timescale 1ns/1ps

import AXI4_PKG::*;

module TESTBED();

    localparam int DATA_W = 32;
    localparam int ADDR_W = 32;
    localparam int ID_W = 4;
    localparam int SET = 64;
    localparam int BLOCK_WORD_SIZE = 8;
    localparam int MEMORY_WORDS = 16384;

    //=============================================================
    //                   Sim Mode & SDF Annotate
    //=============================================================
    `ifdef GATE
        initial begin
            $display("======================================");
            $display("  [INFO] GATE-LEVEL SIMULATION START  ");
            $display("======================================");
            $sdf_annotate("../02_SYN/Netlist/Cache_Top.sdf", u_dut, , ,"maximum");
        end
    `else
        initial begin
            $display("======================================");
            $display("  [INFO] BEHAVIORAL SIMULATION START  ");
            $display("======================================");
        end
    `endif

    //=============================================================
    //                          FSDB Dump
    //=============================================================
    `ifdef FSDB
        initial begin
            $fsdbDumpfile("TESTBED.fsdb");
            $fsdbDumpvars(0, TESTBED, "+mda");
        end
    `endif

    //=============================================================
    //                      Design & Pattern
    //=============================================================
    logic ACLK, ARESETn;

    logic I_CPU_REQ_VALID, I_CPU_REQ_READY;
    logic [ADDR_W-1:0] I_CPU_REQ_ADDR;
    logic I_CPU_RSP_VALID, I_CPU_RSP_READY;
    logic [DATA_W-1:0] I_CPU_RSP_DATA;
    logic I_CPU_RSP_ERROR;
    logic I_INVALIDATE_VALID, I_INVALIDATE_READY;
    logic [ID_W-1:0] I_AR_ID;
    logic [ADDR_W-1:0] I_AR_ADDR;
    logic [7:0] I_AR_LEN;
    logic [2:0] I_AR_SIZE;
    logic [1:0] I_AR_BURST;
    logic I_AR_LOCK;
    logic [3:0] I_AR_CACHE;
    logic [2:0] I_AR_PROT;
    logic [3:0] I_AR_QOS;
    logic I_AR_VALID, I_AR_READY;
    logic [ID_W-1:0] I_R_ID;
    logic [DATA_W-1:0] I_R_DATA;
    resp_type I_R_RESP;
    logic I_R_LAST, I_R_VALID, I_R_READY;

    logic D_CPU_REQ_VALID, D_CPU_REQ_READY;
    logic [ADDR_W-1:0] D_CPU_REQ_ADDR;
    logic D_CPU_REQ_WRITE;
    logic [DATA_W-1:0] D_CPU_REQ_WDATA;
    logic [DATA_W/8-1:0] D_CPU_REQ_WSTRB;
    logic D_CPU_RSP_VALID, D_CPU_RSP_READY;
    logic [DATA_W-1:0] D_CPU_RSP_DATA;
    logic D_CPU_RSP_ERROR;
    logic D_INVALIDATE_VALID, D_INVALIDATE_READY;
    logic [ID_W-1:0] D_AW_ID;
    logic [ADDR_W-1:0] D_AW_ADDR;
    logic [7:0] D_AW_LEN;
    logic [2:0] D_AW_SIZE;
    logic [1:0] D_AW_BURST;
    logic D_AW_LOCK;
    logic [3:0] D_AW_CACHE;
    logic [2:0] D_AW_PROT;
    logic [3:0] D_AW_QOS;
    logic D_AW_VALID, D_AW_READY;
    logic [DATA_W-1:0] D_W_DATA;
    logic [DATA_W/8-1:0] D_W_STRB;
    logic D_W_LAST, D_W_VALID, D_W_READY;
    logic [ID_W-1:0] D_B_ID;
    resp_type D_B_RESP;
    logic D_B_VALID, D_B_READY;
    logic [ID_W-1:0] D_AR_ID;
    logic [ADDR_W-1:0] D_AR_ADDR;
    logic [7:0] D_AR_LEN;
    logic [2:0] D_AR_SIZE;
    logic [1:0] D_AR_BURST;
    logic D_AR_LOCK;
    logic [3:0] D_AR_CACHE;
    logic [2:0] D_AR_PROT;
    logic [3:0] D_AR_QOS;
    logic D_AR_VALID, D_AR_READY;
    logic [ID_W-1:0] D_R_ID;
    logic [DATA_W-1:0] D_R_DATA;
    resp_type D_R_RESP;
    logic D_R_LAST, D_R_VALID, D_R_READY;

    PATTERN #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .ID_W(ID_W),
        .MEMORY_WORDS(MEMORY_WORDS),
        .BLOCK_WORD_SIZE(BLOCK_WORD_SIZE)
    ) u_pattern (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .I_CPU_REQ_VALID(I_CPU_REQ_VALID),
        .I_CPU_REQ_READY(I_CPU_REQ_READY),
        .I_CPU_REQ_ADDR(I_CPU_REQ_ADDR),
        .I_CPU_RSP_VALID(I_CPU_RSP_VALID),
        .I_CPU_RSP_READY(I_CPU_RSP_READY),
        .I_CPU_RSP_DATA(I_CPU_RSP_DATA),
        .I_CPU_RSP_ERROR(I_CPU_RSP_ERROR),
        .I_INVALIDATE_VALID(I_INVALIDATE_VALID),
        .I_INVALIDATE_READY(I_INVALIDATE_READY),
        .I_AR_ID(I_AR_ID),
        .I_AR_ADDR(I_AR_ADDR),
        .I_AR_LEN(I_AR_LEN),
        .I_AR_SIZE(I_AR_SIZE),
        .I_AR_BURST(I_AR_BURST),
        .I_AR_LOCK(I_AR_LOCK),
        .I_AR_CACHE(I_AR_CACHE),
        .I_AR_PROT(I_AR_PROT),
        .I_AR_QOS(I_AR_QOS),
        .I_AR_VALID(I_AR_VALID),
        .I_AR_READY(I_AR_READY),
        .I_R_ID(I_R_ID),
        .I_R_DATA(I_R_DATA),
        .I_R_RESP(I_R_RESP),
        .I_R_LAST(I_R_LAST),
        .I_R_VALID(I_R_VALID),
        .I_R_READY(I_R_READY),
        .D_CPU_REQ_VALID(D_CPU_REQ_VALID),
        .D_CPU_REQ_READY(D_CPU_REQ_READY),
        .D_CPU_REQ_ADDR(D_CPU_REQ_ADDR),
        .D_CPU_REQ_WRITE(D_CPU_REQ_WRITE),
        .D_CPU_REQ_WDATA(D_CPU_REQ_WDATA),
        .D_CPU_REQ_WSTRB(D_CPU_REQ_WSTRB),
        .D_CPU_RSP_VALID(D_CPU_RSP_VALID),
        .D_CPU_RSP_READY(D_CPU_RSP_READY),
        .D_CPU_RSP_DATA(D_CPU_RSP_DATA),
        .D_CPU_RSP_ERROR(D_CPU_RSP_ERROR),
        .D_INVALIDATE_VALID(D_INVALIDATE_VALID),
        .D_INVALIDATE_READY(D_INVALIDATE_READY),
        .D_AW_ID(D_AW_ID),
        .D_AW_ADDR(D_AW_ADDR),
        .D_AW_LEN(D_AW_LEN),
        .D_AW_SIZE(D_AW_SIZE),
        .D_AW_BURST(D_AW_BURST),
        .D_AW_LOCK(D_AW_LOCK),
        .D_AW_CACHE(D_AW_CACHE),
        .D_AW_PROT(D_AW_PROT),
        .D_AW_QOS(D_AW_QOS),
        .D_AW_VALID(D_AW_VALID),
        .D_AW_READY(D_AW_READY),
        .D_W_DATA(D_W_DATA),
        .D_W_STRB(D_W_STRB),
        .D_W_LAST(D_W_LAST),
        .D_W_VALID(D_W_VALID),
        .D_W_READY(D_W_READY),
        .D_B_ID(D_B_ID),
        .D_B_RESP(D_B_RESP),
        .D_B_VALID(D_B_VALID),
        .D_B_READY(D_B_READY),
        .D_AR_ID(D_AR_ID),
        .D_AR_ADDR(D_AR_ADDR),
        .D_AR_LEN(D_AR_LEN),
        .D_AR_SIZE(D_AR_SIZE),
        .D_AR_BURST(D_AR_BURST),
        .D_AR_LOCK(D_AR_LOCK),
        .D_AR_CACHE(D_AR_CACHE),
        .D_AR_PROT(D_AR_PROT),
        .D_AR_QOS(D_AR_QOS),
        .D_AR_VALID(D_AR_VALID),
        .D_AR_READY(D_AR_READY),
        .D_R_ID(D_R_ID),
        .D_R_DATA(D_R_DATA),
        .D_R_RESP(D_R_RESP),
        .D_R_LAST(D_R_LAST),
        .D_R_VALID(D_R_VALID),
        .D_R_READY(D_R_READY)
    );

    Cache_Top #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .ID_W(ID_W),
        .SET(SET),
        .BLOCK_WORD_SIZE(BLOCK_WORD_SIZE)
    ) u_dut (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .I_CPU_REQ_VALID(I_CPU_REQ_VALID),
        .I_CPU_REQ_READY(I_CPU_REQ_READY),
        .I_CPU_REQ_ADDR(I_CPU_REQ_ADDR),
        .I_CPU_RSP_VALID(I_CPU_RSP_VALID),
        .I_CPU_RSP_READY(I_CPU_RSP_READY),
        .I_CPU_RSP_DATA(I_CPU_RSP_DATA),
        .I_CPU_RSP_ERROR(I_CPU_RSP_ERROR),
        .I_INVALIDATE_VALID(I_INVALIDATE_VALID),
        .I_INVALIDATE_READY(I_INVALIDATE_READY),
        .I_AR_ID(I_AR_ID),
        .I_AR_ADDR(I_AR_ADDR),
        .I_AR_LEN(I_AR_LEN),
        .I_AR_SIZE(I_AR_SIZE),
        .I_AR_BURST(I_AR_BURST),
        .I_AR_LOCK(I_AR_LOCK),
        .I_AR_CACHE(I_AR_CACHE),
        .I_AR_PROT(I_AR_PROT),
        .I_AR_QOS(I_AR_QOS),
        .I_AR_VALID(I_AR_VALID),
        .I_AR_READY(I_AR_READY),
        .I_R_ID(I_R_ID),
        .I_R_DATA(I_R_DATA),
        .I_R_RESP(I_R_RESP),
        .I_R_LAST(I_R_LAST),
        .I_R_VALID(I_R_VALID),
        .I_R_READY(I_R_READY),
        .D_CPU_REQ_VALID(D_CPU_REQ_VALID),
        .D_CPU_REQ_READY(D_CPU_REQ_READY),
        .D_CPU_REQ_ADDR(D_CPU_REQ_ADDR),
        .D_CPU_REQ_WRITE(D_CPU_REQ_WRITE),
        .D_CPU_REQ_WDATA(D_CPU_REQ_WDATA),
        .D_CPU_REQ_WSTRB(D_CPU_REQ_WSTRB),
        .D_CPU_RSP_VALID(D_CPU_RSP_VALID),
        .D_CPU_RSP_READY(D_CPU_RSP_READY),
        .D_CPU_RSP_DATA(D_CPU_RSP_DATA),
        .D_CPU_RSP_ERROR(D_CPU_RSP_ERROR),
        .D_INVALIDATE_VALID(D_INVALIDATE_VALID),
        .D_INVALIDATE_READY(D_INVALIDATE_READY),
        .D_AW_ID(D_AW_ID),
        .D_AW_ADDR(D_AW_ADDR),
        .D_AW_LEN(D_AW_LEN),
        .D_AW_SIZE(D_AW_SIZE),
        .D_AW_BURST(D_AW_BURST),
        .D_AW_LOCK(D_AW_LOCK),
        .D_AW_CACHE(D_AW_CACHE),
        .D_AW_PROT(D_AW_PROT),
        .D_AW_QOS(D_AW_QOS),
        .D_AW_VALID(D_AW_VALID),
        .D_AW_READY(D_AW_READY),
        .D_W_DATA(D_W_DATA),
        .D_W_STRB(D_W_STRB),
        .D_W_LAST(D_W_LAST),
        .D_W_VALID(D_W_VALID),
        .D_W_READY(D_W_READY),
        .D_B_ID(D_B_ID),
        .D_B_RESP(D_B_RESP),
        .D_B_VALID(D_B_VALID),
        .D_B_READY(D_B_READY),
        .D_AR_ID(D_AR_ID),
        .D_AR_ADDR(D_AR_ADDR),
        .D_AR_LEN(D_AR_LEN),
        .D_AR_SIZE(D_AR_SIZE),
        .D_AR_BURST(D_AR_BURST),
        .D_AR_LOCK(D_AR_LOCK),
        .D_AR_CACHE(D_AR_CACHE),
        .D_AR_PROT(D_AR_PROT),
        .D_AR_QOS(D_AR_QOS),
        .D_AR_VALID(D_AR_VALID),
        .D_AR_READY(D_AR_READY),
        .D_R_ID(D_R_ID),
        .D_R_DATA(D_R_DATA),
        .D_R_RESP(D_R_RESP),
        .D_R_LAST(D_R_LAST),
        .D_R_VALID(D_R_VALID),
        .D_R_READY(D_R_READY)
    );

endmodule
