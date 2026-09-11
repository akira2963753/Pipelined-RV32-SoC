/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    PATTERN.sv
* Project:      RISC-V CPU Cache
* Module:       PATTERN
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         Vivado 2025.1
*
* Description:
*   Self-checking I-Cache stimulus. Tests cold misses, line hits,
*   set replacement, LRU behavior, and reset invalidation.
******************************************************************************/

`timescale 1ns/1ps

module PATTERN #(
    parameter int DATA_W = 32,
    parameter int ADDR_W = 32,
    parameter int BRAM_DEPTH = 4096
) (
    output logic ACLK,
    output logic ARESETn,
    output logic CPU_REQ,
    output logic [ADDR_W-1:0] CPU_REQ_ADDR,
    input logic CPU_REQ_VALID,
    input logic [DATA_W-1:0] CPU_REQ_DATA,
    input logic BUSY,
    input logic AR_VALID,
    input logic AR_READY,
    input logic R_VALID,
    input logic R_READY,
    input logic R_LAST
);

    localparam int CYCLE = 10;
    localparam int MEM_FILE_WORDS = 1296;
    localparam string MEM_FILE =
        "C:/Users/harry/Desktop/Project/risc-v/CACHE/I-CACHE/Mem_Data/test_data.mem";

    logic [DATA_W-1:0] golden_mem [0:BRAM_DEPTH-1];
    integer ar_transaction_count;
    integer r_beat_count;
    integer error_count;
    integer mem_idx;

    initial begin
        ACLK = 1'b0;
        forever #(CYCLE / 2) ACLK = ~ACLK;
    end

    always @(negedge ACLK) begin
        if(!ARESETn) begin
            ar_transaction_count = 0;
            r_beat_count = 0;
        end
        else begin
            if(AR_VALID && AR_READY)
                ar_transaction_count = ar_transaction_count + 1;

            if(R_VALID && R_READY)
                r_beat_count = r_beat_count + 1;
        end
    end

    task automatic apply_reset;
        begin
            ARESETn = 1'b1;
            CPU_REQ = 1'b0;
            CPU_REQ_ADDR = '0;
            repeat(2) @(negedge ACLK);
            ARESETn = 1'b0;
            repeat(3) @(negedge ACLK);
            ARESETn = 1'b1;
            @(negedge ACLK);
        end
    endtask

    task automatic fetch_check(
        input logic [ADDR_W-1:0] address,
        input integer expected_ar_transactions,
        input integer expected_r_beats,
        input string test_name
    );
        integer ar_count_before;
        integer beat_count_before;
        integer timeout_count;
        logic [DATA_W-1:0] expected_data;
        begin
            ar_count_before = ar_transaction_count;
            beat_count_before = r_beat_count;
            expected_data = golden_mem[address[ADDR_W-1:2]];

            @(negedge ACLK);
            CPU_REQ = 1'b1;
            CPU_REQ_ADDR = address;
            timeout_count = 0;

            while(!CPU_REQ_VALID && (timeout_count < 200)) begin
                @(negedge ACLK);
                timeout_count = timeout_count + 1;
            end

            if(timeout_count >= 200) begin
                $error("[%s] timeout at address %08h", test_name, address);
                error_count = error_count + 1;
            end
            else if(CPU_REQ_DATA !== expected_data) begin
                $error("[%s] address %08h: expected %08h, got %08h",
                       test_name, address, expected_data, CPU_REQ_DATA);
                error_count = error_count + 1;
            end

            CPU_REQ = 1'b0;
            @(negedge ACLK);

            if((ar_transaction_count - ar_count_before) !=
               expected_ar_transactions) begin
                $error("[%s] expected %0d AR transaction(s), got %0d",
                       test_name, expected_ar_transactions,
                       ar_transaction_count - ar_count_before);
                error_count = error_count + 1;
            end

            if((r_beat_count - beat_count_before) != expected_r_beats) begin
                $error("[%s] expected %0d R beat(s), got %0d",
                       test_name, expected_r_beats,
                       r_beat_count - beat_count_before);
                error_count = error_count + 1;
            end
        end
    endtask

    initial begin
        ARESETn = 1'b1;
        CPU_REQ = 1'b0;
        CPU_REQ_ADDR = '0;
        error_count = 0;

        for(mem_idx = 0; mem_idx < BRAM_DEPTH; mem_idx = mem_idx + 1)
            golden_mem[mem_idx] = 32'hA500_0000 ^ mem_idx;

        $readmemh(MEM_FILE, golden_mem, 0, MEM_FILE_WORDS - 1);

        apply_reset();

        fetch_check(32'h0000_0000, 1, 8, "cold miss");
        fetch_check(32'h0000_0004, 0, 0, "same-line hit word 1");
        fetch_check(32'h0000_001C, 0, 0, "same-line hit word 7");

        fetch_check(32'h0000_0020, 1, 8, "next-line miss");
        fetch_check(32'h0000_0040, 1, 8, "third-line miss");
        fetch_check(32'h0000_006C, 1, 8, "offset miss");
        fetch_check(32'h0000_004C, 0, 0, "line revisit hit");

        fetch_check(32'h0000_0800, 1, 8, "second way fill");
        fetch_check(32'h0000_0000, 0, 0, "LRU touch way zero");
        fetch_check(32'h0000_1000, 1, 8, "LRU replacement");
        fetch_check(32'h0000_0800, 1, 8, "evicted line refetch");

        apply_reset();
        fetch_check(32'h0000_0000, 1, 8, "reset invalidation");

        if(error_count == 0) begin
            $display("============================================================");
            $display("I-CACHE AXI4 VERIFICATION PASS");
            $display("All data, burst, hit, replacement, and reset tests passed.");
            $display("============================================================");
        end
        else begin
            $fatal(1, "I-CACHE AXI4 VERIFICATION FAIL: %0d error(s)",
                   error_count);
        end

        repeat(5) @(negedge ACLK);
        $finish;
    end

endmodule
