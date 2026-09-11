/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    AXI4_PKG.sv
* Project:      RISC-V CPU AXI4 Bus
* Module:       AXI4_PKG
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         Vivado 2025.1
*
******************************************************************************/

`timescale 1ns/1ps

package AXI4_PKG;

    typedef enum bit [7:0] {PHASE1, PHASE2, PHASE3, PHASE4, PHASE5, PHASE6} phase_type;

    typedef enum logic [1:0] {
        AXI_OKAY,
        AXI_EXOKAY,
        AXI_SLVERR,
        AXI_DECERR
    } resp_type;

endpackage
