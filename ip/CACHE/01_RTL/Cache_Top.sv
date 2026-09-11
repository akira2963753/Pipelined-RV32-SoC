/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    Cache_Top.sv
* Project:      RISC-V CPU Cache
* Module:       Cache_Top
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

`timescale 1ns/1ps

import AXI4_PKG::*;

module Cache_Top #(
    parameter int DATA_W = 32,
    parameter int ADDR_W = 32,
    parameter int ID_W = 4,
    parameter int SET = 64,
    parameter int BLOCK_WORD_SIZE = 8
) (
    input logic ACLK,
    input logic ARESETn,

    input logic I_CPU_REQ_VALID,
    output logic I_CPU_REQ_READY,
    input logic [ADDR_W-1:0] I_CPU_REQ_ADDR,
    output logic I_CPU_RSP_VALID,
    input logic I_CPU_RSP_READY,
    output logic [DATA_W-1:0] I_CPU_RSP_DATA,
    output logic I_CPU_RSP_ERROR,
    input logic I_INVALIDATE_VALID,
    output logic I_INVALIDATE_READY,

    output logic [ID_W-1:0] I_AR_ID,
    output logic [ADDR_W-1:0] I_AR_ADDR,
    output logic [7:0] I_AR_LEN,
    output logic [2:0] I_AR_SIZE,
    output logic [1:0] I_AR_BURST,
    output logic I_AR_LOCK,
    output logic [3:0] I_AR_CACHE,
    output logic [2:0] I_AR_PROT,
    output logic [3:0] I_AR_QOS,
    output logic I_AR_VALID,
    input logic I_AR_READY,
    input logic [ID_W-1:0] I_R_ID,
    input logic [DATA_W-1:0] I_R_DATA,
    input resp_type I_R_RESP,
    input logic I_R_LAST,
    input logic I_R_VALID,
    output logic I_R_READY,

    input logic D_CPU_REQ_VALID,
    output logic D_CPU_REQ_READY,
    input logic [ADDR_W-1:0] D_CPU_REQ_ADDR,
    input logic D_CPU_REQ_WRITE,
    input logic [DATA_W-1:0] D_CPU_REQ_WDATA,
    input logic [DATA_W/8-1:0] D_CPU_REQ_WSTRB,
    output logic D_CPU_RSP_VALID,
    input logic D_CPU_RSP_READY,
    output logic [DATA_W-1:0] D_CPU_RSP_DATA,
    output logic D_CPU_RSP_ERROR,
    input logic D_INVALIDATE_VALID,
    output logic D_INVALIDATE_READY,

    output logic [ID_W-1:0] D_AW_ID,
    output logic [ADDR_W-1:0] D_AW_ADDR,
    output logic [7:0] D_AW_LEN,
    output logic [2:0] D_AW_SIZE,
    output logic [1:0] D_AW_BURST,
    output logic D_AW_LOCK,
    output logic [3:0] D_AW_CACHE,
    output logic [2:0] D_AW_PROT,
    output logic [3:0] D_AW_QOS,
    output logic D_AW_VALID,
    input logic D_AW_READY,
    output logic [DATA_W-1:0] D_W_DATA,
    output logic [DATA_W/8-1:0] D_W_STRB,
    output logic D_W_LAST,
    output logic D_W_VALID,
    input logic D_W_READY,
    input logic [ID_W-1:0] D_B_ID,
    input resp_type D_B_RESP,
    input logic D_B_VALID,
    output logic D_B_READY,
    output logic [ID_W-1:0] D_AR_ID,
    output logic [ADDR_W-1:0] D_AR_ADDR,
    output logic [7:0] D_AR_LEN,
    output logic [2:0] D_AR_SIZE,
    output logic [1:0] D_AR_BURST,
    output logic D_AR_LOCK,
    output logic [3:0] D_AR_CACHE,
    output logic [2:0] D_AR_PROT,
    output logic [3:0] D_AR_QOS,
    output logic D_AR_VALID,
    input logic D_AR_READY,
    input logic [ID_W-1:0] D_R_ID,
    input logic [DATA_W-1:0] D_R_DATA,
    input resp_type D_R_RESP,
    input logic D_R_LAST,
    input logic D_R_VALID,
    output logic D_R_READY
);

    //=============================================================
    //                      Instruction Cache
    //=============================================================
    I_Cache #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .ID_W(ID_W),
        .SET(SET),
        .BLOCK_WORD_SIZE(BLOCK_WORD_SIZE)
    ) u_i_cache (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .CPU_REQ_VALID(I_CPU_REQ_VALID),
        .CPU_REQ_READY(I_CPU_REQ_READY),
        .CPU_REQ_ADDR(I_CPU_REQ_ADDR),
        .CPU_RSP_VALID(I_CPU_RSP_VALID),
        .CPU_RSP_READY(I_CPU_RSP_READY),
        .CPU_RSP_DATA(I_CPU_RSP_DATA),
        .CPU_RSP_ERROR(I_CPU_RSP_ERROR),
        .INVALIDATE_VALID(I_INVALIDATE_VALID),
        .INVALIDATE_READY(I_INVALIDATE_READY),
        .AR_ID(I_AR_ID),
        .AR_ADDR(I_AR_ADDR),
        .AR_LEN(I_AR_LEN),
        .AR_SIZE(I_AR_SIZE),
        .AR_BURST(I_AR_BURST),
        .AR_LOCK(I_AR_LOCK),
        .AR_CACHE(I_AR_CACHE),
        .AR_PROT(I_AR_PROT),
        .AR_QOS(I_AR_QOS),
        .AR_VALID(I_AR_VALID),
        .AR_READY(I_AR_READY),
        .R_ID(I_R_ID),
        .R_DATA(I_R_DATA),
        .R_RESP(I_R_RESP),
        .R_LAST(I_R_LAST),
        .R_VALID(I_R_VALID),
        .R_READY(I_R_READY)
    );

    //=============================================================
    //                          Data Cache
    //=============================================================
    D_Cache #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .ID_W(ID_W),
        .SET(SET),
        .BLOCK_WORD_SIZE(BLOCK_WORD_SIZE)
    ) u_d_cache (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .CPU_REQ_VALID(D_CPU_REQ_VALID),
        .CPU_REQ_READY(D_CPU_REQ_READY),
        .CPU_REQ_ADDR(D_CPU_REQ_ADDR),
        .CPU_REQ_WRITE(D_CPU_REQ_WRITE),
        .CPU_REQ_WDATA(D_CPU_REQ_WDATA),
        .CPU_REQ_WSTRB(D_CPU_REQ_WSTRB),
        .CPU_RSP_VALID(D_CPU_RSP_VALID),
        .CPU_RSP_READY(D_CPU_RSP_READY),
        .CPU_RSP_DATA(D_CPU_RSP_DATA),
        .CPU_RSP_ERROR(D_CPU_RSP_ERROR),
        .INVALIDATE_VALID(D_INVALIDATE_VALID),
        .INVALIDATE_READY(D_INVALIDATE_READY),
        .AW_ID(D_AW_ID),
        .AW_ADDR(D_AW_ADDR),
        .AW_LEN(D_AW_LEN),
        .AW_SIZE(D_AW_SIZE),
        .AW_BURST(D_AW_BURST),
        .AW_LOCK(D_AW_LOCK),
        .AW_CACHE(D_AW_CACHE),
        .AW_PROT(D_AW_PROT),
        .AW_QOS(D_AW_QOS),
        .AW_VALID(D_AW_VALID),
        .AW_READY(D_AW_READY),
        .W_DATA(D_W_DATA),
        .W_STRB(D_W_STRB),
        .W_LAST(D_W_LAST),
        .W_VALID(D_W_VALID),
        .W_READY(D_W_READY),
        .B_ID(D_B_ID),
        .B_RESP(D_B_RESP),
        .B_VALID(D_B_VALID),
        .B_READY(D_B_READY),
        .AR_ID(D_AR_ID),
        .AR_ADDR(D_AR_ADDR),
        .AR_LEN(D_AR_LEN),
        .AR_SIZE(D_AR_SIZE),
        .AR_BURST(D_AR_BURST),
        .AR_LOCK(D_AR_LOCK),
        .AR_CACHE(D_AR_CACHE),
        .AR_PROT(D_AR_PROT),
        .AR_QOS(D_AR_QOS),
        .AR_VALID(D_AR_VALID),
        .AR_READY(D_AR_READY),
        .R_ID(D_R_ID),
        .R_DATA(D_R_DATA),
        .R_RESP(D_R_RESP),
        .R_LAST(D_R_LAST),
        .R_VALID(D_R_VALID),
        .R_READY(D_R_READY)
    );

endmodule
