/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    PATTERN.sv
* Project:      RISC-V CPU Cache
* Module:       PATTERN
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

`timescale 1ns/1ps

import AXI4_PKG::*;

module PATTERN #(
    parameter int DATA_W = 32,
    parameter int ADDR_W = 32,
    parameter int ID_W = 4,
    parameter int MEMORY_WORDS = 16384,
    parameter int BLOCK_WORD_SIZE = 8
) (
    output logic ACLK,
    output logic ARESETn,

    output logic I_CPU_REQ_VALID,
    input logic I_CPU_REQ_READY,
    output logic [ADDR_W-1:0] I_CPU_REQ_ADDR,
    input logic I_CPU_RSP_VALID,
    output logic I_CPU_RSP_READY,
    input logic [DATA_W-1:0] I_CPU_RSP_DATA,
    input logic I_CPU_RSP_ERROR,
    output logic I_INVALIDATE_VALID,
    input logic I_INVALIDATE_READY,

    input logic [ID_W-1:0] I_AR_ID,
    input logic [ADDR_W-1:0] I_AR_ADDR,
    input logic [7:0] I_AR_LEN,
    input logic [2:0] I_AR_SIZE,
    input logic [1:0] I_AR_BURST,
    input logic I_AR_LOCK,
    input logic [3:0] I_AR_CACHE,
    input logic [2:0] I_AR_PROT,
    input logic [3:0] I_AR_QOS,
    input logic I_AR_VALID,
    output logic I_AR_READY,
    output logic [ID_W-1:0] I_R_ID,
    output logic [DATA_W-1:0] I_R_DATA,
    output resp_type I_R_RESP,
    output logic I_R_LAST,
    output logic I_R_VALID,
    input logic I_R_READY,

    output logic D_CPU_REQ_VALID,
    input logic D_CPU_REQ_READY,
    output logic [ADDR_W-1:0] D_CPU_REQ_ADDR,
    output logic D_CPU_REQ_WRITE,
    output logic [DATA_W-1:0] D_CPU_REQ_WDATA,
    output logic [DATA_W/8-1:0] D_CPU_REQ_WSTRB,
    input logic D_CPU_RSP_VALID,
    output logic D_CPU_RSP_READY,
    input logic [DATA_W-1:0] D_CPU_RSP_DATA,
    input logic D_CPU_RSP_ERROR,
    output logic D_INVALIDATE_VALID,
    input logic D_INVALIDATE_READY,

    input logic [ID_W-1:0] D_AW_ID,
    input logic [ADDR_W-1:0] D_AW_ADDR,
    input logic [7:0] D_AW_LEN,
    input logic [2:0] D_AW_SIZE,
    input logic [1:0] D_AW_BURST,
    input logic D_AW_LOCK,
    input logic [3:0] D_AW_CACHE,
    input logic [2:0] D_AW_PROT,
    input logic [3:0] D_AW_QOS,
    input logic D_AW_VALID,
    output logic D_AW_READY,
    input logic [DATA_W-1:0] D_W_DATA,
    input logic [DATA_W/8-1:0] D_W_STRB,
    input logic D_W_LAST,
    input logic D_W_VALID,
    output logic D_W_READY,
    output logic [ID_W-1:0] D_B_ID,
    output resp_type D_B_RESP,
    output logic D_B_VALID,
    input logic D_B_READY,
    input logic [ID_W-1:0] D_AR_ID,
    input logic [ADDR_W-1:0] D_AR_ADDR,
    input logic [7:0] D_AR_LEN,
    input logic [2:0] D_AR_SIZE,
    input logic [1:0] D_AR_BURST,
    input logic D_AR_LOCK,
    input logic [3:0] D_AR_CACHE,
    input logic [2:0] D_AR_PROT,
    input logic [3:0] D_AR_QOS,
    input logic D_AR_VALID,
    output logic D_AR_READY,
    output logic [ID_W-1:0] D_R_ID,
    output logic [DATA_W-1:0] D_R_DATA,
    output resp_type D_R_RESP,
    output logic D_R_LAST,
    output logic D_R_VALID,
    input logic D_R_READY
);

    localparam CLK_PERIOD = 10;
    localparam TIMEOUT = 2000000;
    localparam int STRB_W = DATA_W / 8;
    localparam int BYTE_LSB = $clog2(STRB_W);
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;
    localparam logic [7:0] AXI_LINE_LEN = BLOCK_WORD_SIZE - 1;
    localparam logic [2:0] AXI_WORD_SIZE = BYTE_LSB;

    typedef enum int {
        I_CACHE_TEST,
        D_CACHE_TEST,
        DONE
    } phase_t;

    phase_t veri_phase;
    logic [DATA_W-1:0] memory [0:MEMORY_WORDS-1];
    int cycle_count;
    int i_ar_count, i_r_count;
    int d_aw_count, d_w_count, d_b_count, d_ar_count, d_r_count;
    logic inject_i_read_error;
    logic inject_d_read_error;
    logic inject_d_write_error;

    logic i_read_active;
    logic [ID_W-1:0] i_read_id;
    logic [ADDR_W-1:0] i_read_addr;
    logic [7:0] i_read_len;
    logic [7:0] i_read_beat;
    logic i_read_error;
    int i_read_delay;

    logic d_read_active;
    logic [ID_W-1:0] d_read_id;
    logic [ADDR_W-1:0] d_read_addr;
    logic [7:0] d_read_len;
    logic [7:0] d_read_beat;
    logic d_read_error;
    int d_read_delay;

    logic d_aw_captured;
    logic d_w_captured;
    logic [ID_W-1:0] d_write_id;
    logic [ADDR_W-1:0] d_write_addr;
    logic [DATA_W-1:0] d_write_data;
    logic [STRB_W-1:0] d_write_strb;
    logic d_write_error;

    //=============================================================
    //                        Clock & Reset
    //=============================================================
    initial ACLK = 1'b0;
    always #(CLK_PERIOD / 2.0) ACLK = ~ACLK;

    initial begin : CYCLE_COUNTER
        cycle_count = 0;
        forever begin
            @(negedge ACLK);
            cycle_count++;
        end
    end

    task automatic drive_reset();
        I_CPU_REQ_VALID = 1'b0;
        I_CPU_REQ_ADDR = '0;
        I_CPU_RSP_READY = 1'b1;
        I_INVALIDATE_VALID = 1'b0;
        D_CPU_REQ_VALID = 1'b0;
        D_CPU_REQ_ADDR = '0;
        D_CPU_REQ_WRITE = 1'b0;
        D_CPU_REQ_WDATA = '0;
        D_CPU_REQ_WSTRB = '0;
        D_CPU_RSP_READY = 1'b1;
        D_INVALIDATE_VALID = 1'b0;

        ARESETn = 1'b1;
        force ACLK = 1'b0;
        #20 ARESETn = 1'b0;
        #20 ARESETn = 1'b1;
        release ACLK;
        @(negedge ACLK);
    endtask

    //=============================================================
    //                     AXI Read Slave Models
    //=============================================================
    initial begin : I_READ_BFM
        I_AR_READY = 1'b0;
        I_R_ID = '0;
        I_R_DATA = '0;
        I_R_RESP = AXI_OKAY;
        I_R_LAST = 1'b0;
        I_R_VALID = 1'b0;
        i_read_active = 1'b0;
        i_read_id = '0;
        i_read_addr = '0;
        i_read_len = '0;
        i_read_beat = '0;
        i_read_error = 1'b0;
        i_read_delay = 0;
        i_ar_count = 0;
        i_r_count = 0;

        forever begin
            @(negedge ACLK);

            if(I_R_VALID && I_R_READY) begin
                I_R_VALID = 1'b0;
                I_R_LAST = 1'b0;
                i_r_count++;

                if(i_read_beat == i_read_len) i_read_active = 1'b0;
                else i_read_beat++;
            end

            if(I_AR_VALID && I_AR_READY) begin
                i_read_active = 1'b1;
                i_read_id = I_AR_ID;
                i_read_addr = I_AR_ADDR;
                i_read_len = I_AR_LEN;
                i_read_beat = '0;
                i_read_error = inject_i_read_error;
                inject_i_read_error = 1'b0;
                i_read_delay = 1;
                i_ar_count++;
            end

            if(!I_R_VALID && i_read_active) begin
                if(i_read_delay == 0) begin
                    I_R_ID = i_read_id;
                    I_R_DATA = memory[int'(i_read_addr >> BYTE_LSB) +
                                      int'(i_read_beat)];
                    I_R_RESP = (i_read_error)? AXI_SLVERR : AXI_OKAY;
                    I_R_LAST = i_read_beat == i_read_len;
                    I_R_VALID = 1'b1;
                end
                else i_read_delay--;
            end

            I_AR_READY = !i_read_active && !I_R_VALID &&
                         ((cycle_count % 3) != 0);
        end
    end

    initial begin : D_READ_BFM
        D_AR_READY = 1'b0;
        D_R_ID = '0;
        D_R_DATA = '0;
        D_R_RESP = AXI_OKAY;
        D_R_LAST = 1'b0;
        D_R_VALID = 1'b0;
        d_read_active = 1'b0;
        d_read_id = '0;
        d_read_addr = '0;
        d_read_len = '0;
        d_read_beat = '0;
        d_read_error = 1'b0;
        d_read_delay = 0;
        d_ar_count = 0;
        d_r_count = 0;

        forever begin
            @(negedge ACLK);

            if(D_R_VALID && D_R_READY) begin
                D_R_VALID = 1'b0;
                D_R_LAST = 1'b0;
                d_r_count++;

                if(d_read_beat == d_read_len) d_read_active = 1'b0;
                else d_read_beat++;
            end

            if(D_AR_VALID && D_AR_READY) begin
                d_read_active = 1'b1;
                d_read_id = D_AR_ID;
                d_read_addr = D_AR_ADDR;
                d_read_len = D_AR_LEN;
                d_read_beat = '0;
                d_read_error = inject_d_read_error;
                inject_d_read_error = 1'b0;
                d_read_delay = 2;
                d_ar_count++;
            end

            if(!D_R_VALID && d_read_active) begin
                if(d_read_delay == 0) begin
                    D_R_ID = d_read_id;
                    D_R_DATA = memory[int'(d_read_addr >> BYTE_LSB) +
                                      int'(d_read_beat)];
                    D_R_RESP = (d_read_error)? AXI_SLVERR : AXI_OKAY;
                    D_R_LAST = d_read_beat == d_read_len;
                    D_R_VALID = 1'b1;
                end
                else d_read_delay--;
            end

            D_AR_READY = !d_read_active && !D_R_VALID &&
                         ((cycle_count % 4) != 0);
        end
    end

    //=============================================================
    //                     AXI Write Slave Model
    //=============================================================
    initial begin : D_WRITE_BFM
        D_AW_READY = 1'b0;
        D_W_READY = 1'b0;
        D_B_ID = '0;
        D_B_RESP = AXI_OKAY;
        D_B_VALID = 1'b0;
        d_aw_captured = 1'b0;
        d_w_captured = 1'b0;
        d_write_id = '0;
        d_write_addr = '0;
        d_write_data = '0;
        d_write_strb = '0;
        d_write_error = 1'b0;
        d_aw_count = 0;
        d_w_count = 0;
        d_b_count = 0;

        forever begin
            @(negedge ACLK);

            if(D_B_VALID && D_B_READY) begin
                D_B_VALID = 1'b0;
                d_aw_captured = 1'b0;
                d_w_captured = 1'b0;
                d_b_count++;
            end

            if(D_AW_VALID && D_AW_READY) begin
                d_aw_captured = 1'b1;
                d_write_id = D_AW_ID;
                d_write_addr = D_AW_ADDR;
                d_write_error = inject_d_write_error;
                inject_d_write_error = 1'b0;
                d_aw_count++;
            end

            if(D_W_VALID && D_W_READY) begin
                d_w_captured = 1'b1;
                d_write_data = D_W_DATA;
                d_write_strb = D_W_STRB;
                d_w_count++;
            end

            if(d_aw_captured && d_w_captured && !D_B_VALID) begin
                if(!d_write_error) begin
                    for(int byte_idx = 0; byte_idx < STRB_W; byte_idx++) begin
                        if(d_write_strb[byte_idx]) memory[d_write_addr >> BYTE_LSB][byte_idx*8 +: 8] = d_write_data[byte_idx*8 +: 8];
                    end
                end

                D_B_ID = d_write_id;
                D_B_RESP = (d_write_error)? AXI_SLVERR : AXI_OKAY;
                D_B_VALID = 1'b1;
            end

            D_AW_READY = !d_aw_captured && !D_B_VALID &&
                         ((cycle_count % 3) != 1);
            D_W_READY = d_aw_captured && !d_w_captured && !D_B_VALID &&
                        ((cycle_count % 2) == 0);
        end
    end

    //=============================================================
    //                       Request Helpers
    //=============================================================
    task automatic i_fetch_check(
        input logic [ADDR_W-1:0] address,
        input logic [DATA_W-1:0] expected_data,
        input logic expected_error,
        input int expected_ar,
        input int response_stall_cycles
    );
        int ar_before;
        int r_before;
        int wait_cycles;
        logic [DATA_W-1:0] held_data;
        logic held_error;

        ar_before = i_ar_count;
        r_before = i_r_count;
        I_CPU_RSP_READY = response_stall_cycles == 0;
        I_CPU_REQ_ADDR = address;
        I_CPU_REQ_VALID = 1'b1;
        wait_cycles = 0;

        do begin
            @(negedge ACLK);
            wait_cycles++;
            if(wait_cycles > 200) $fatal(1, "[ERROR]: I-Cache request timeout");
        end while(!(I_CPU_REQ_VALID && I_CPU_REQ_READY));

        I_CPU_REQ_VALID = 1'b0;
        wait_cycles = 0;

        while(!I_CPU_RSP_VALID) begin
            @(negedge ACLK);
            wait_cycles++;
            if(wait_cycles > 500) $fatal(1, "[ERROR]: I-Cache response timeout");
        end

        if(I_CPU_RSP_ERROR !== expected_error) $fatal(1, "[ERROR]: I-Cache response error mismatch at %08h", address);
        if(!expected_error && (I_CPU_RSP_DATA !== expected_data)) $fatal(1, "[ERROR]: I-Cache data mismatch at %08h", address);

        held_data = I_CPU_RSP_DATA;
        held_error = I_CPU_RSP_ERROR;
        repeat(response_stall_cycles) begin
            @(negedge ACLK);
            if(!I_CPU_RSP_VALID || (I_CPU_RSP_DATA !== held_data) ||
               (I_CPU_RSP_ERROR !== held_error))
                $fatal(1, "[ERROR]: I-Cache response changed under backpressure");
        end

        I_CPU_RSP_READY = 1'b1;
        @(negedge ACLK);

        if((i_ar_count - ar_before) != expected_ar) $fatal(1, "[ERROR]: I-Cache AR count mismatch at %08h", address);
        if((i_r_count - r_before) != (expected_ar * BLOCK_WORD_SIZE)) $fatal(1, "[ERROR]: I-Cache R beat count mismatch at %08h", address);
    endtask

    task automatic d_request_check(
        input logic [ADDR_W-1:0] address,
        input logic write_request,
        input logic [DATA_W-1:0] write_data_value,
        input logic [STRB_W-1:0] write_strobe,
        input logic [DATA_W-1:0] expected_data,
        input logic expected_error,
        input int expected_ar,
        input int expected_aw
    );
        int ar_before;
        int r_before;
        int aw_before;
        int w_before;
        int b_before;
        int wait_cycles;

        ar_before = d_ar_count;
        r_before = d_r_count;
        aw_before = d_aw_count;
        w_before = d_w_count;
        b_before = d_b_count;
        D_CPU_REQ_ADDR = address;
        D_CPU_REQ_WRITE = write_request;
        D_CPU_REQ_WDATA = write_data_value;
        D_CPU_REQ_WSTRB = write_strobe;
        D_CPU_REQ_VALID = 1'b1;
        wait_cycles = 0;

        do begin
            @(negedge ACLK);
            wait_cycles++;
            if(wait_cycles > 200) $fatal(1, "[ERROR]: D-Cache request timeout");
        end while(!(D_CPU_REQ_VALID && D_CPU_REQ_READY));

        D_CPU_REQ_VALID = 1'b0;
        wait_cycles = 0;

        while(!D_CPU_RSP_VALID) begin
            @(negedge ACLK);
            wait_cycles++;
            if(wait_cycles > 500) $fatal(1, "[ERROR]: D-Cache response timeout");
        end

        if(D_CPU_RSP_ERROR !== expected_error) $fatal(1, "[ERROR]: D-Cache response error mismatch at %08h", address);
        if(!write_request && !expected_error && (D_CPU_RSP_DATA !== expected_data)) $fatal(1, "[ERROR]: D-Cache data mismatch at %08h", address);

        @(negedge ACLK);

        if((d_ar_count - ar_before) != expected_ar) $fatal(1, "[ERROR]: D-Cache AR count mismatch at %08h", address);
        if((d_aw_count - aw_before) != expected_aw) $fatal(1, "[ERROR]: D-Cache AW count mismatch at %08h", address);
        if((d_r_count - r_before) != (expected_ar * BLOCK_WORD_SIZE)) $fatal(1, "[ERROR]: D-Cache R beat count mismatch at %08h", address);
        if((d_w_count - w_before) != expected_aw) $fatal(1, "[ERROR]: D-Cache W beat count mismatch at %08h", address);
        if((d_b_count - b_before) != expected_aw) $fatal(1, "[ERROR]: D-Cache B response count mismatch at %08h", address);
    endtask

    task automatic invalidate_i_cache();
        I_INVALIDATE_VALID = 1'b1;
        do @(negedge ACLK); while(!I_INVALIDATE_READY);
        I_INVALIDATE_VALID = 1'b0;
        @(negedge ACLK);
    endtask

    task automatic invalidate_d_cache();
        D_INVALIDATE_VALID = 1'b1;
        do @(negedge ACLK); while(!D_INVALIDATE_READY);
        D_INVALIDATE_VALID = 1'b0;
        @(negedge ACLK);
    endtask

    task automatic d_response_backpressure_check(
        input logic [ADDR_W-1:0] address,
        input logic [DATA_W-1:0] expected_data
    );
        logic [DATA_W-1:0] held_data;
        logic held_error;
        int wait_cycles;

        D_CPU_RSP_READY = 1'b0;
        D_CPU_REQ_ADDR = address;
        D_CPU_REQ_WRITE = 1'b0;
        D_CPU_REQ_WDATA = '0;
        D_CPU_REQ_WSTRB = '0;
        D_CPU_REQ_VALID = 1'b1;

        do @(negedge ACLK); while(!(D_CPU_REQ_VALID && D_CPU_REQ_READY));
        D_CPU_REQ_VALID = 1'b0;
        wait_cycles = 0;

        while(!D_CPU_RSP_VALID) begin
            @(negedge ACLK);
            wait_cycles++;
            if(wait_cycles > 100) $fatal(1, "[ERROR]: D-Cache stalled response timeout");
        end

        held_data = D_CPU_RSP_DATA;
        held_error = D_CPU_RSP_ERROR;
        if(held_error || (held_data !== expected_data)) $fatal(1, "[ERROR]: D-Cache stalled response mismatch");

        repeat(3) begin
            @(negedge ACLK);
            if(!D_CPU_RSP_VALID || (D_CPU_RSP_DATA !== held_data) ||
               (D_CPU_RSP_ERROR !== held_error))
                $fatal(1, "[ERROR]: D-Cache response changed under backpressure");
        end

        D_CPU_RSP_READY = 1'b1;
        @(negedge ACLK);
    endtask

    task automatic i_back_to_back_hits();
        logic [ADDR_W-1:0] addresses [0:3];
        int accepted;
        int received;
        int last_accept_cycle;
        int wait_cycles;

        addresses[0] = 32'h0000_0000;
        addresses[1] = 32'h0000_0004;
        addresses[2] = 32'h0000_0008;
        addresses[3] = 32'h0000_000C;
        accepted = 0;
        received = 0;
        last_accept_cycle = -1;
        wait_cycles = 0;
        I_CPU_RSP_READY = 1'b1;
        I_CPU_REQ_ADDR = addresses[0];
        I_CPU_REQ_VALID = 1'b1;

        while(received < 4) begin
            @(negedge ACLK);
            wait_cycles++;
            if(wait_cycles > 30) $fatal(1, "[ERROR]: I-Cache hit throughput timeout");

            if(I_CPU_REQ_VALID && I_CPU_REQ_READY) begin
                if((accepted > 0) && (cycle_count != last_accept_cycle + 1)) $fatal(1, "[ERROR]: I-Cache did not accept consecutive hits");

                last_accept_cycle = cycle_count;
                accepted++;

                if(accepted < 4) I_CPU_REQ_ADDR = addresses[accepted];
                else I_CPU_REQ_VALID = 1'b0;
            end

            if(I_CPU_RSP_VALID && I_CPU_RSP_READY) begin
                if(I_CPU_RSP_ERROR ||
                   (I_CPU_RSP_DATA !== memory[addresses[received] >> BYTE_LSB]))
                    $fatal(1, "[ERROR]: I-Cache back-to-back response mismatch");
                received++;
            end
        end
    endtask

    task end_task();
        $display("============================================");
        $display("  [SUCCESS] ALL PATTERN & ASSERTION PASS !  ");
        $display("============================================");
    endtask

    //=============================================================
    //                       Timing Watchdog
    //=============================================================
    initial begin
        #(TIMEOUT);
        $fatal(1, "[TIMEOUT]: Simulation time exceeded watchdog limit.");
    end

    //=============================================================
    //                          Main Flow
    //=============================================================
    initial begin : MAIN_FLOW
        ARESETn = 1'b1;
        inject_i_read_error = 1'b0;
        inject_d_read_error = 1'b0;
        inject_d_write_error = 1'b0;
        veri_phase = I_CACHE_TEST;

        for(int word_idx = 0; word_idx < MEMORY_WORDS; word_idx++) memory[word_idx] = 32'hA500_0000 ^ {word_idx[31:0]};

        drive_reset();

        i_fetch_check(32'h0000_0000, memory[0], 1'b0, 1, 0);
        i_fetch_check(32'h0000_0004, memory[1], 1'b0, 0, 3);
        i_back_to_back_hits();
        i_fetch_check(32'h0000_0800, memory[32'h0800 >> BYTE_LSB], 1'b0, 1, 0);
        i_fetch_check(32'h0000_0000, memory[0], 1'b0, 0, 0);
        i_fetch_check(32'h0000_1000, memory[32'h1000 >> BYTE_LSB], 1'b0, 1, 0);
        i_fetch_check(32'h0000_0800, memory[32'h0800 >> BYTE_LSB], 1'b0, 1, 0);
        invalidate_i_cache();
        i_fetch_check(32'h0000_0000, memory[0], 1'b0, 1, 0);
        inject_i_read_error = 1'b1;
        i_fetch_check(32'h0000_1800, '0, 1'b1, 1, 0);
        i_fetch_check(32'h0000_1800, memory[32'h1800 >> BYTE_LSB], 1'b0, 1, 0);
        $display("[PASS]: I-Cache ready-valid, throughput, LRU, invalidate, and error tests.");

        veri_phase = D_CACHE_TEST;
        d_request_check(32'h0000_2000, 1'b0, '0, '0,
                        memory[32'h2000 >> BYTE_LSB], 1'b0, 1, 0);
        d_request_check(32'h0000_2004, 1'b0, '0, '0,
                        memory[32'h2004 >> BYTE_LSB], 1'b0, 0, 0);
        d_request_check(32'h0000_2004, 1'b1, 32'hDEAD_BEEF, 4'b1111,
                        '0, 1'b0, 0, 1);
        d_request_check(32'h0000_2004, 1'b0, '0, '0,
                        32'hDEAD_BEEF, 1'b0, 0, 0);
        d_request_check(32'h0000_2004, 1'b1, 32'hAABB_CCDD, 4'b0101,
                        '0, 1'b0, 0, 1);
        d_request_check(32'h0000_2004, 1'b0, '0, '0,
                        32'hDEBB_BEDD, 1'b0, 0, 0);
        d_response_backpressure_check(32'h0000_2004, 32'hDEBB_BEDD);
        d_request_check(32'h0000_3000, 1'b1, 32'h1122_3344, 4'b1111,
                        '0, 1'b0, 0, 1);
        d_request_check(32'h0000_3000, 1'b0, '0, '0,
                        32'h1122_3344, 1'b0, 1, 0);
        inject_d_write_error = 1'b1;
        d_request_check(32'h0000_2000, 1'b1, 32'hCAFE_BABE, 4'b1111,
                        '0, 1'b1, 0, 1);
        d_request_check(32'h0000_2000, 1'b0, '0, '0,
                        memory[32'h2000 >> BYTE_LSB], 1'b0, 0, 0);
        inject_d_read_error = 1'b1;
        d_request_check(32'h0000_4000, 1'b0, '0, '0, '0, 1'b1, 1, 0);
        d_request_check(32'h0000_4000, 1'b0, '0, '0,
                        memory[32'h4000 >> BYTE_LSB], 1'b0, 1, 0);
        invalidate_d_cache();
        d_request_check(32'h0000_2000, 1'b0, '0, '0,
                        memory[32'h2000 >> BYTE_LSB], 1'b0, 1, 0);
        $display("[PASS]: D-Cache read, write-through, strobe, policy, invalidate, and error tests.");

        veri_phase = DONE;
        repeat(5) @(negedge ACLK);
        end_task();
        $finish;
    end

    //=============================================================
    //                 SystemVerilog Assertion
    //=============================================================
    `ifdef SVA
        I_CPU_RSP_STABLE: assert property(
            @(posedge ACLK) disable iff(!ARESETn)
            I_CPU_RSP_VALID && !I_CPU_RSP_READY |=>
            I_CPU_RSP_VALID && $stable({I_CPU_RSP_DATA, I_CPU_RSP_ERROR})
        )
        else $fatal(1, "[ERROR]: I-Cache response changed while stalled");

        D_CPU_RSP_STABLE: assert property(
            @(posedge ACLK) disable iff(!ARESETn)
            D_CPU_RSP_VALID && !D_CPU_RSP_READY |=>
            D_CPU_RSP_VALID && $stable({D_CPU_RSP_DATA, D_CPU_RSP_ERROR})
        )
        else $fatal(1, "[ERROR]: D-Cache response changed while stalled");

        I_AR_STABLE: assert property(
            @(posedge ACLK) disable iff(!ARESETn)
            I_AR_VALID && !I_AR_READY |=> $stable({I_AR_ID, I_AR_ADDR, I_AR_LEN,
            I_AR_SIZE, I_AR_BURST, I_AR_LOCK, I_AR_CACHE, I_AR_PROT, I_AR_QOS})
        )
        else $fatal(1, "[ERROR]: I-Cache AR payload changed while stalled");

        D_AW_STABLE: assert property(
            @(posedge ACLK) disable iff(!ARESETn)
            D_AW_VALID && !D_AW_READY |=> $stable({D_AW_ID, D_AW_ADDR, D_AW_LEN,
            D_AW_SIZE, D_AW_BURST, D_AW_LOCK, D_AW_CACHE, D_AW_PROT, D_AW_QOS})
        )
        else $fatal(1, "[ERROR]: D-Cache AW payload changed while stalled");

        D_W_STABLE: assert property(
            @(posedge ACLK) disable iff(!ARESETn)
            D_W_VALID && !D_W_READY |=> $stable({D_W_DATA, D_W_STRB, D_W_LAST})
        )
        else $fatal(1, "[ERROR]: D-Cache W payload changed while stalled");

        D_AR_STABLE: assert property(
            @(posedge ACLK) disable iff(!ARESETn)
            D_AR_VALID && !D_AR_READY |=> $stable({D_AR_ID, D_AR_ADDR, D_AR_LEN,
            D_AR_SIZE, D_AR_BURST, D_AR_LOCK, D_AR_CACHE, D_AR_PROT, D_AR_QOS})
        )
        else $fatal(1, "[ERROR]: D-Cache AR payload changed while stalled");

        I_AR_ATTRIBUTES: assert property(
            @(posedge ACLK) disable iff(!ARESETn)
            I_AR_VALID |-> (I_AR_LEN == AXI_LINE_LEN) &&
            (I_AR_SIZE == AXI_WORD_SIZE) && (I_AR_BURST == AXI_BURST_INCR) &&
            (I_AR_PROT == 3'b100)
        )
        else $fatal(1, "[ERROR]: I-Cache AR attributes are invalid");

        D_AR_ATTRIBUTES: assert property(
            @(posedge ACLK) disable iff(!ARESETn)
            D_AR_VALID |-> (D_AR_LEN == AXI_LINE_LEN) &&
            (D_AR_SIZE == AXI_WORD_SIZE) && (D_AR_BURST == AXI_BURST_INCR)
        )
        else $fatal(1, "[ERROR]: D-Cache AR attributes are invalid");

        D_AW_ATTRIBUTES: assert property(
            @(posedge ACLK) disable iff(!ARESETn)
            D_AW_VALID |-> (D_AW_LEN == 8'd0) &&
            (D_AW_SIZE == AXI_WORD_SIZE) && (D_AW_BURST == AXI_BURST_INCR)
        )
        else $fatal(1, "[ERROR]: D-Cache AW attributes are invalid");

        RESET_VALID_LOW: assert property(
            @(posedge ACLK)
            !ARESETn |-> (!I_CPU_RSP_VALID && !I_AR_VALID && !I_R_READY &&
            !D_CPU_RSP_VALID && !D_AW_VALID && !D_W_VALID && !D_B_READY &&
            !D_AR_VALID && !D_R_READY)
        )
        else $fatal(1, "[ERROR]: Cache VALID or READY output asserted during reset");
    `endif

endmodule
