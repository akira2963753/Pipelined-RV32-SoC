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
*   Self-checking D-Cache stimulus for AXI4 read bursts, write-through stores,
*   byte strobes, no-write-allocate behavior, LRU, and reset invalidation.
******************************************************************************/

`timescale 1ns/1ps

import AXI4_PKG::*;

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
    output logic CPU_WR_EN,
    output logic [DATA_W-1:0] CPU_WR_DATA,
    output logic [DATA_W/8-1:0] CPU_WR_STRB,
    input logic BUSY,
    input logic AW_VALID,
    input logic AW_READY,
    input logic W_VALID,
    input logic W_READY,
    input logic B_VALID,
    input logic B_READY,
    input resp_type B_RESP,
    input logic AR_VALID,
    input logic AR_READY,
    input logic R_VALID,
    input logic R_READY,
    input resp_type R_RESP
);

    localparam int CYCLE = 10;

    typedef enum int {
        PHASE_READ,
        PHASE_WRITE_HIT,
        PHASE_WRITE_MISS,
        PHASE_REPLACEMENT,
        PHASE_RESET,
        DONE
    } phase_t;

    phase_t verification_phase;
    logic [DATA_W-1:0] golden_mem [0:BRAM_DEPTH-1];
    integer aw_transaction_count;
    integer w_beat_count;
    integer b_response_count;
    integer ar_transaction_count;
    integer r_beat_count;
    integer response_error_count;
    integer error_count;
    integer mem_idx;

    initial begin
        ACLK = 1'b0;
        forever #(CYCLE / 2) ACLK = ~ACLK;
    end

    always_ff @(posedge ACLK) begin
        if(!ARESETn) begin
            aw_transaction_count <= 0;
            w_beat_count <= 0;
            b_response_count <= 0;
            ar_transaction_count <= 0;
            r_beat_count <= 0;
            response_error_count <= 0;
        end else begin
            if(AW_VALID && AW_READY)
                aw_transaction_count <= aw_transaction_count + 1;

            if(W_VALID && W_READY) w_beat_count <= w_beat_count + 1;

            if(B_VALID && B_READY) begin
                b_response_count <= b_response_count + 1;

                if(B_RESP != AXI_OKAY)
                    response_error_count <= response_error_count + 1;
            end

            if(AR_VALID && AR_READY)
                ar_transaction_count <= ar_transaction_count + 1;

            if(R_VALID && R_READY) begin
                r_beat_count <= r_beat_count + 1;

                if(R_RESP != AXI_OKAY)
                    response_error_count <= response_error_count + 1;
            end
        end
    end

    function automatic logic [DATA_W-1:0] merge_strobe(
        input logic [DATA_W-1:0] original_data,
        input logic [DATA_W-1:0] write_data,
        input logic [DATA_W/8-1:0] write_strobe
    );
        logic [DATA_W-1:0] merged_data;
        begin
            merged_data = original_data;

            for(int byte_pos = 0; byte_pos < DATA_W / 8;
                byte_pos = byte_pos + 1) begin
                if(write_strobe[byte_pos])
                    merged_data[byte_pos*8 +: 8] =
                        write_data[byte_pos*8 +: 8];
            end

            merge_strobe = merged_data;
        end
    endfunction

    task automatic apply_reset;
        begin
            ARESETn = 1'b1;
            CPU_REQ = 1'b0;
            CPU_REQ_ADDR = '0;
            CPU_WR_EN = 1'b0;
            CPU_WR_DATA = '0;
            CPU_WR_STRB = '0;
            repeat(2) @(negedge ACLK);
            ARESETn = 1'b0;
            repeat(3) @(negedge ACLK);
            ARESETn = 1'b1;
            @(negedge ACLK);
        end
    endtask

    task automatic check_delta(
        input integer actual,
        input integer expected,
        input string counter_name,
        input string test_name
    );
        begin
            if(actual != expected) begin
                $error("[%s] expected %0d %s, got %0d",
                       test_name, expected, counter_name, actual);
                error_count = error_count + 1;
            end
        end
    endtask

    task automatic read_check(
        input logic [ADDR_W-1:0] address,
        input integer expected_ar_transactions,
        input integer expected_r_beats,
        input string test_name
    );
        integer aw_before;
        integer w_before;
        integer b_before;
        integer ar_before;
        integer r_before;
        integer timeout_count;
        logic [DATA_W-1:0] expected_data;
        begin
            aw_before = aw_transaction_count;
            w_before = w_beat_count;
            b_before = b_response_count;
            ar_before = ar_transaction_count;
            r_before = r_beat_count;
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
                $error("[%s] read timeout at address %08h", test_name, address);
                error_count = error_count + 1;
            end else if(CPU_REQ_DATA !== expected_data) begin
                $error("[%s] address %08h: expected %08h, got %08h",
                       test_name, address, expected_data, CPU_REQ_DATA);
                error_count = error_count + 1;
            end

            CPU_REQ = 1'b0;
            @(negedge ACLK);

            check_delta(aw_transaction_count - aw_before, 0,
                        "AW transaction(s)", test_name);
            check_delta(w_beat_count - w_before, 0,
                        "W beat(s)", test_name);
            check_delta(b_response_count - b_before, 0,
                        "B response(s)", test_name);
            check_delta(ar_transaction_count - ar_before,
                        expected_ar_transactions,
                        "AR transaction(s)", test_name);
            check_delta(r_beat_count - r_before, expected_r_beats,
                        "R beat(s)", test_name);
        end
    endtask

    task automatic write_check(
        input logic [ADDR_W-1:0] address,
        input logic [DATA_W-1:0] write_data,
        input logic [DATA_W/8-1:0] write_strobe,
        input string test_name
    );
        integer aw_before;
        integer w_before;
        integer b_before;
        integer ar_before;
        integer r_before;
        integer timeout_count;
        begin
            aw_before = aw_transaction_count;
            w_before = w_beat_count;
            b_before = b_response_count;
            ar_before = ar_transaction_count;
            r_before = r_beat_count;

            @(negedge ACLK);
            CPU_WR_EN = 1'b1;
            CPU_REQ_ADDR = address;
            CPU_WR_DATA = write_data;
            CPU_WR_STRB = write_strobe;
            timeout_count = 0;

            while(!BUSY && (timeout_count < 20)) begin
                @(negedge ACLK);
                timeout_count = timeout_count + 1;
            end

            if(timeout_count >= 20) begin
                $error("[%s] write request was not accepted", test_name);
                error_count = error_count + 1;
            end

            CPU_WR_EN = 1'b0;
            CPU_WR_DATA = '0;
            CPU_WR_STRB = '0;
            timeout_count = 0;

            while(BUSY && (timeout_count < 100)) begin
                @(negedge ACLK);
                timeout_count = timeout_count + 1;
            end

            if(timeout_count >= 100) begin
                $error("[%s] write response timeout", test_name);
                error_count = error_count + 1;
            end

            @(negedge ACLK);
            golden_mem[address[ADDR_W-1:2]] = merge_strobe(
                golden_mem[address[ADDR_W-1:2]], write_data, write_strobe
            );

            check_delta(aw_transaction_count - aw_before, 1,
                        "AW transaction(s)", test_name);
            check_delta(w_beat_count - w_before, 1,
                        "W beat(s)", test_name);
            check_delta(b_response_count - b_before, 1,
                        "B response(s)", test_name);
            check_delta(ar_transaction_count - ar_before, 0,
                        "AR transaction(s)", test_name);
            check_delta(r_beat_count - r_before, 0,
                        "R beat(s)", test_name);
        end
    endtask

    initial begin
        ARESETn = 1'b1;
        CPU_REQ = 1'b0;
        CPU_REQ_ADDR = '0;
        CPU_WR_EN = 1'b0;
        CPU_WR_DATA = '0;
        CPU_WR_STRB = '0;
        verification_phase = PHASE_READ;
        error_count = 0;

        for(mem_idx = 0; mem_idx < BRAM_DEPTH; mem_idx = mem_idx + 1)
            golden_mem[mem_idx] = 32'hD000_0000 ^ mem_idx;

        apply_reset();

        verification_phase = PHASE_READ;
        read_check(32'h0000_0000, 1, 8, "cold read miss");
        read_check(32'h0000_0004, 0, 0, "same-line read hit");
        read_check(32'h0000_001C, 0, 0, "last-word read hit");
        $display("Phase read burst and hit tests passed.");

        verification_phase = PHASE_WRITE_HIT;
        write_check(32'h0000_0004, 32'hDEAD_BEEF, 4'b1111,
                    "full write hit");
        read_check(32'h0000_0004, 0, 0, "read after full write hit");
        write_check(32'h0000_0004, 32'hAABB_CCDD, 4'b0101,
                    "partial write hit");
        read_check(32'h0000_0004, 0, 0, "read after partial write hit");
        $display("Phase write hit and byte-strobe tests passed.");

        verification_phase = PHASE_WRITE_MISS;
        write_check(32'h0000_0120, 32'h1122_3344, 4'b1111,
                    "write miss no allocate");
        read_check(32'h0000_0120, 1, 8,
                   "read after no-write-allocate miss");
        read_check(32'h0000_0124, 0, 0, "allocated line read hit");
        $display("Phase no-write-allocate tests passed.");

        verification_phase = PHASE_REPLACEMENT;
        apply_reset();
        read_check(32'h0000_0000, 1, 8, "replacement way zero fill");
        read_check(32'h0000_0800, 1, 8, "replacement way one fill");
        read_check(32'h0000_0000, 0, 0, "replacement LRU touch");
        read_check(32'h0000_1000, 1, 8, "replacement third tag fill");
        read_check(32'h0000_0800, 1, 8, "replacement evicted refetch");
        $display("Phase LRU replacement tests passed.");

        verification_phase = PHASE_RESET;
        apply_reset();
        read_check(32'h0000_0000, 1, 8, "reset invalidation");
        write_check(32'h0000_0000, 32'hCAFE_BABE, 4'b1111,
                    "post-reset write coverage");
        read_check(32'h0000_0000, 0, 0, "post-reset write hit check");
        $display("Phase reset invalidation test passed.");

        if(response_error_count != 0) begin
            $error("Observed %0d AXI error response(s)", response_error_count);
            error_count = error_count + response_error_count;
        end

        verification_phase = DONE;

        if(error_count == 0) begin
            $display("============================================================");
            $display("D-CACHE AXI4 VERIFICATION PASS");
            $display("Read, write, strobe, policy, LRU, and reset tests passed.");
            $display("============================================================");
        end else begin
            $fatal(1, "D-CACHE AXI4 VERIFICATION FAIL: %0d error(s)",
                   error_count);
        end

        repeat(5) @(negedge ACLK);
        $finish;
    end

endmodule
