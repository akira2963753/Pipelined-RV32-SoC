/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    PATTERN2.sv
* Project:      RISC-V CPU AXI4 Bus
* Module:       PATTERN2
* Author:       Marco <harry2963753@gmail.com>
*
* Description:
*   Class-based non-UVM AXI4 verification environment for learning.
*   Components: driver, input/output monitor, reference model,
*               scoreboard, functional coverage, assertions.
*
*   Usage:
*     Replace PATTERN with PATTERN2 in TESTBED.sv to run this environment.
*     This file is self-contained and does not modify existing PATTERN.sv.
*
******************************************************************************/

`timescale 1ns/1ps

import AXI4_PKG::*;

`define CLK_PERIOD 10.0
`define HS_TIMEOUT 1000

module PATTERN2 #(
    parameter int DATA_W = 32,
    parameter int ADDR_W = 32,
    parameter int ID_W = 4,
    parameter int BRAM_DEPTH = 256
)(
    output logic ACLK,
    output logic ARESETn,

    // ============================================================================
    //                      Write Address Channel Ports (AW)
    // ============================================================================
    output logic [ID_W-1:0] AW_ID,
    output logic [ADDR_W-1:0] AW_ADDR,
    output logic [7:0] AW_LEN,
    output logic [2:0] AW_SIZE,
    output logic [1:0] AW_BURST,
    output logic AW_LOCK,
    output logic [3:0] AW_CACHE,
    output logic [2:0] AW_PROT,
    output logic [3:0] AW_QOS,
    output logic AW_VALID,
    input logic AW_READY,

    // ============================================================================
    //                          Write Data Channel Ports (W)
    // ============================================================================
    output logic [DATA_W-1:0] W_DATA,
    output logic [DATA_W/8-1:0] W_STRB,
    output logic W_LAST,
    output logic W_VALID,
    input logic W_READY,

    // ============================================================================
    //                         Write Response Channel Ports (B)
    // ============================================================================
    input logic [ID_W-1:0] B_ID,
    input resp_type B_RESP,
    input logic B_VALID,
    output logic B_READY,

    // ============================================================================
    //                          Read Address Channel Ports (AR)
    // ============================================================================
    output logic [ID_W-1:0] AR_ID,
    output logic [ADDR_W-1:0] AR_ADDR,
    output logic [7:0] AR_LEN,
    output logic [2:0] AR_SIZE,
    output logic [1:0] AR_BURST,
    output logic AR_LOCK,
    output logic [3:0] AR_CACHE,
    output logic [2:0] AR_PROT,
    output logic [3:0] AR_QOS,
    output logic AR_VALID,
    input logic AR_READY,

    // ============================================================================
    //                           Read Data Channel Ports (R)
    // ============================================================================
    input logic [ID_W-1:0] R_ID,
    input logic [DATA_W-1:0] R_DATA,
    input resp_type R_RESP,
    input logic R_LAST,
    input logic R_VALID,
    output logic R_READY
);

    localparam int STRB_W = DATA_W / 8;
    localparam int BYTE_OFFSET_W = $clog2(STRB_W);
    localparam logic [1:0] AXI_BURST_FIXED = 2'b00;
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;
    localparam logic [1:0] AXI_BURST_WRAP = 2'b10;
    localparam logic [ADDR_W:0] MEMORY_BYTES = BRAM_DEPTH * STRB_W;

    typedef enum int {
        ADDR_CLASS_LOW,
        ADDR_CLASS_MID,
        ADDR_CLASS_HIGH,
        ADDR_CLASS_BOUNDARY,
        ADDR_CLASS_OOB
    } addr_class_e;

    typedef enum int {
        STRB_CLASS_FULL,
        STRB_CLASS_ZERO,
        STRB_CLASS_PARTIAL
    } strb_class_e;

    // ============================================================================
    //                           Transaction Classes
    // ============================================================================

    class axi_write_transaction;
        string name;
        rand bit [ID_W-1:0] id;
        rand bit [ADDR_W-1:0] addr;
        rand bit [7:0] len;
        rand bit [2:0] size;
        rand bit [1:0] burst;
        rand bit lock;
        rand bit [3:0] cache;
        rand bit [2:0] prot;
        rand bit [3:0] qos;

        // 使用 Dynamic Array 做宣告，因為一筆 Burst 會有多種數量的 beats
        rand bit [DATA_W-1:0] data[];
        rand bit [STRB_W-1:0] strb[];

        constraint c_supported {
            len inside {[0:15]};
            size == BYTE_OFFSET_W;
            burst == AXI_BURST_INCR;
            lock == 1'b0;
            cache == 4'b0000;
            prot == 3'b000;
            qos == 4'b0000;
        }

        constraint c_aligned_address {
            addr[BYTE_OFFSET_W-1:0] == '0;
        }

        // 確保整個 Burst 都在 BRAM 的範圍內
        constraint c_address_range {
            addr <= (BRAM_DEPTH * STRB_W) - ((len + 1) << size);
        }

        // 定義 Dyanmic Array 是取決於 length
        constraint c_payload_size {
            data.size() == len + 1;
            strb.size() == len + 1;
        }

        // 必須先決定好 len 才能夠決定 addr
        constraint c_solve_order {
            solve len before addr;
        }

        function new(input string name = "axi_write_transaction");
            this.name = name;
        endfunction

        function int unsigned get_beat_count();
            return len + 1;
        endfunction

        function bit [ADDR_W-1:0] get_beat_address(input int unsigned beat_index);
            return addr + (beat_index << size);
        endfunction

        function axi_write_transaction copy();
            axi_write_transaction txn;
            txn = new(name);
            txn.id = id;
            txn.addr = addr;
            txn.len = len;
            txn.size = size;
            txn.burst = burst;
            txn.lock = lock;
            txn.cache = cache;
            txn.prot = prot;
            txn.qos = qos;
            txn.data = new[len + 1];
            txn.strb = new[len + 1];
            foreach (data[beat_index]) begin
                txn.data[beat_index] = data[beat_index];
                txn.strb[beat_index] = strb[beat_index];
            end
            return txn;
        endfunction

        function void print();
            $display("================================================================");
            $display("[%s] id=%0h addr=%08h len=%0d beats=%0d size=%0d burst=%0b",
                name, id, addr, len, get_beat_count(), size, burst);
            $display("================================================================");
            foreach (data[beat_index]) begin
                $display("beat_idx=%0d addr=%08h data=%08h strb=%0h last=%0b",
                    beat_index,
                    get_beat_address(beat_index),
                    data[beat_index],
                    strb[beat_index],
                    beat_index == len
                );
            end
            $display("================================================================");
        endfunction
    endclass

    class axi_read_request;
        string name;
        bit [ID_W-1:0] id;
        bit [ADDR_W-1:0] addr;
        bit [7:0] len;
        bit [2:0] size;
        bit [1:0] burst;
        bit lock;
        bit [3:0] cache;
        bit [2:0] prot;
        bit [3:0] qos;

        function new(input string name = "axi_read_request");
            this.name = name;
        endfunction

        function int unsigned get_beat_count();
            return len + 1;
        endfunction

        function bit [ADDR_W-1:0] get_beat_address(input int unsigned beat_index);
            return addr + (beat_index << size);
        endfunction

        function void copy_from_write(input axi_write_transaction wr);
            name = wr.name;
            id = wr.id;
            addr = wr.addr;
            len = wr.len;
            size = wr.size;
            burst = wr.burst;
            lock = wr.lock;
            cache = wr.cache;
            prot = wr.prot;
            qos = wr.qos;
        endfunction

        function void print();
            $display("================================================================");
            $display("[%s] READ id=%0h addr=%08h len=%0d beats=%0d size=%0d burst=%0b",
                name, id, addr, len, get_beat_count(), size, burst);
            $display("================================================================");
        endfunction
    endclass

    class axi_b_response;
        string tag;
        bit [ID_W-1:0] id;
        resp_type resp;

        function new(input string tag = "B");
            this.tag = tag;
        endfunction
    endclass

    class axi_r_beat;
        string tag;
        bit [ID_W-1:0] id;
        bit [ADDR_W-1:0] addr;
        bit [DATA_W-1:0] data;
        resp_type resp;
        bit last;
        int unsigned beat_index;

        function new(input string tag = "R");
            this.tag = tag;
        endfunction
    endclass

    // ============================================================================
    //                         Driver Control Structs
    // ============================================================================

    class axi_driver_ctrl;
        int unsigned aw_delay_cycles;
        int unsigned w_gap_cycles;
        int unsigned ar_delay_cycles;
        int unsigned b_ready_delay;
        int unsigned r_ready_delay;
        bit w_before_aw;
        bit random_b_stall;
        bit random_r_stall;

        function new();
            aw_delay_cycles = 0;
            w_gap_cycles = 0;
            ar_delay_cycles = 0;
            b_ready_delay = 0;
            r_ready_delay = 0;
            w_before_aw = 1'b0;
            random_b_stall = 1'b0;
            random_r_stall = 1'b0;
        endfunction
    endclass

    // ============================================================================
    //                              AXI Driver
    // ============================================================================

    class axi_driver;
        int unsigned aw_stall_cycles;
        int unsigned w_stall_cycles;
        int unsigned b_stall_cycles;
        int unsigned ar_stall_cycles;
        int unsigned r_stall_cycles;

        function new();
            aw_stall_cycles = 0;
            w_stall_cycles = 0;
            b_stall_cycles = 0;
            ar_stall_cycles = 0;
            r_stall_cycles = 0;
        endfunction

        task automatic init_outputs();
            AW_ID = '0;
            AW_ADDR = '0;
            AW_LEN = '0;
            AW_SIZE = BYTE_OFFSET_W;
            AW_BURST = AXI_BURST_INCR;
            AW_LOCK = 1'b0;
            AW_CACHE = '0;
            AW_PROT = '0;
            AW_QOS = '0;
            AW_VALID = 1'b0;

            W_DATA = '0;
            W_STRB = '0;
            W_LAST = 1'b0;
            W_VALID = 1'b0;

            B_READY = 1'b0;

            AR_ID = '0;
            AR_ADDR = '0;
            AR_LEN = '0;
            AR_SIZE = BYTE_OFFSET_W;
            AR_BURST = AXI_BURST_INCR;
            AR_LOCK = 1'b0;
            AR_CACHE = '0;
            AR_PROT = '0;
            AR_QOS = '0;
            AR_VALID = 1'b0;

            R_READY = 1'b0;
        endtask

        task automatic handshake_aw(input axi_write_transaction txn, input int unsigned pre_delay = 0);
            int cycles;

            repeat(pre_delay) @(negedge ACLK);
            @(negedge ACLK);
            cycles = 0;
            AW_ID = txn.id;
            AW_ADDR = txn.addr;
            AW_LEN = txn.len;
            AW_SIZE = txn.size;
            AW_BURST = txn.burst;
            AW_LOCK = txn.lock;
            AW_CACHE = txn.cache;
            AW_PROT = txn.prot;
            AW_QOS = txn.qos;
            AW_VALID = 1'b1;

            while (!AW_READY) begin
                @(negedge ACLK);
                cycles = cycles + 1;
                aw_stall_cycles = aw_stall_cycles + 1;
                CHECK_DRV_AW_HS: assert (cycles < `HS_TIMEOUT)
                else $fatal(1, "[DRV ERROR]: AW handshake timeout");
            end

            @(negedge ACLK);
            AW_VALID = 1'b0;
        endtask

        task automatic handshake_w(input axi_write_transaction txn);
            int cycles;

            for (int beat = 0; beat < txn.get_beat_count(); beat++) begin
                cycles = 0;
                W_DATA = txn.data[beat];
                W_STRB = txn.strb[beat];
                W_LAST = (beat == txn.len);
                W_VALID = 1'b1;

                while (!W_READY) begin
                    @(negedge ACLK);
                    cycles = cycles + 1;
                    w_stall_cycles = w_stall_cycles + 1;
                    CHECK_DRV_W_HS: assert (cycles < `HS_TIMEOUT)
                    else $fatal(1, "[DRV ERROR]: W handshake timeout, beat=%0d", beat);
                end

                @(negedge ACLK);
            end

            W_DATA = '0;
            W_STRB = '0;
            W_LAST = 1'b0;
            W_VALID = 1'b0;
        endtask

        task automatic handshake_ar(input axi_read_request rd, input int unsigned pre_delay = 0);
            int cycles;

            repeat(pre_delay) @(negedge ACLK);
            @(negedge ACLK);
            cycles = 0;
            AR_ID = rd.id;
            AR_ADDR = rd.addr;
            AR_LEN = rd.len;
            AR_SIZE = rd.size;
            AR_BURST = rd.burst;
            AR_LOCK = rd.lock;
            AR_CACHE = rd.cache;
            AR_PROT = rd.prot;
            AR_QOS = rd.qos;
            AR_VALID = 1'b1;

            while (!AR_READY) begin
                @(negedge ACLK);
                cycles = cycles + 1;
                ar_stall_cycles = ar_stall_cycles + 1;
                CHECK_DRV_AR_HS: assert (cycles < `HS_TIMEOUT)
                else $fatal(1, "[DRV ERROR]: AR handshake timeout");
            end

            @(negedge ACLK);
            AR_VALID = 1'b0;
        endtask

        task automatic accept_b(
            input axi_driver_ctrl ctrl,
            output int unsigned observed_b_stall
        );
            int cycles;
            int unsigned stall_target;

            observed_b_stall = 0;
            B_READY = 1'b0;
            repeat(ctrl.b_ready_delay) @(negedge ACLK);

            if (ctrl.random_b_stall) begin
                stall_target = $urandom_range(5, 1);
                repeat(stall_target) begin
                    @(negedge ACLK);
                    observed_b_stall = observed_b_stall + 1;
                    b_stall_cycles = b_stall_cycles + 1;
                end
            end

            B_READY = 1'b1;
            cycles = 0;
            while (!B_VALID) begin
                @(negedge ACLK);
                cycles = cycles + 1;
                CHECK_DRV_B_HS: assert (cycles < `HS_TIMEOUT)
                else $fatal(1, "[DRV ERROR]: B handshake timeout");
            end

            @(posedge ACLK);
            B_READY = 1'b0;
        endtask

        task automatic accept_r(
            input int unsigned beat_count,
            input axi_driver_ctrl ctrl,
            output int unsigned observed_r_stall
        );
            int cycles;
            int unsigned stall_target;

            observed_r_stall = 0;
            R_READY = 1'b0;
            repeat(ctrl.r_ready_delay) @(negedge ACLK);

            for (int beat = 0; beat < beat_count; beat++) begin
                if (ctrl.random_r_stall) begin
                    stall_target = $urandom_range(4, 0);
                    repeat(stall_target) begin
                        @(negedge ACLK);
                        observed_r_stall = observed_r_stall + 1;
                        r_stall_cycles = r_stall_cycles + 1;
                    end
                end

                R_READY = 1'b1;
                cycles = 0;
                while (!R_VALID) begin
                    @(negedge ACLK);
                    cycles = cycles + 1;
                    CHECK_DRV_R_HS: assert (cycles < `HS_TIMEOUT)
                    else $fatal(1, "[DRV ERROR]: R handshake timeout, beat=%0d", beat);
                end

                @(posedge ACLK);
                R_READY = 1'b0;
            end
        endtask

        task automatic drive_write(
            input axi_write_transaction txn,
            input axi_driver_ctrl ctrl
        );
            int unsigned dummy_stall;

            if (ctrl.w_before_aw) begin
                fork
                    handshake_w(txn);
                    begin
                        repeat($urandom_range(8, 0)) @(negedge ACLK);
                        handshake_aw(txn, ctrl.aw_delay_cycles);
                    end
                join
            end
            else begin
                handshake_aw(txn, ctrl.aw_delay_cycles);
                repeat(ctrl.w_gap_cycles) @(negedge ACLK);
                handshake_w(txn);
            end

            accept_b(ctrl, dummy_stall);
        endtask

        task automatic drive_read(
            input axi_read_request rd,
            input axi_driver_ctrl ctrl
        );
            int unsigned dummy_stall;

            handshake_ar(rd, ctrl.ar_delay_cycles);
            accept_r(rd.get_beat_count(), ctrl, dummy_stall);
        endtask

        task automatic drive_write_read(
            input axi_write_transaction wr,
            input axi_read_request rd,
            input axi_driver_ctrl w_ctrl,
            input axi_driver_ctrl r_ctrl
        );
            drive_write(wr, w_ctrl);
            drive_read(rd, r_ctrl);
        endtask
    endclass

    // ============================================================================
    //                           Input Monitor
    // ============================================================================

    class axi_input_monitor;
        mailbox #(axi_write_transaction) wr_complete_mb;
        mailbox #(axi_read_request) rd_req_mb;

        axi_write_transaction pending_wr;
        bit wr_collect_active;
        int unsigned wr_beat_count;

        function new(
            mailbox #(axi_write_transaction) wr_complete_mb,
            mailbox #(axi_read_request) rd_req_mb
        );
            this.wr_complete_mb = wr_complete_mb;
            this.rd_req_mb = rd_req_mb;
            wr_collect_active = 1'b0;
            wr_beat_count = 0;
        endfunction

        task automatic run();
            forever begin
                @(posedge ACLK);
                if (!ARESETn) begin
                    wr_collect_active = 1'b0;
                    wr_beat_count = 0;
                    pending_wr = null;
                    continue;
                end

                if (AW_VALID && AW_READY) capture_aw();
                if (W_VALID && W_READY) capture_w();
                if (AR_VALID && AR_READY) capture_ar();
            end
        endtask

        function void capture_aw();
            pending_wr = new("mon_observed_write");
            pending_wr.id = AW_ID;
            pending_wr.addr = AW_ADDR;
            pending_wr.len = AW_LEN;
            pending_wr.size = AW_SIZE;
            pending_wr.burst = AW_BURST;
            pending_wr.lock = AW_LOCK;
            pending_wr.cache = AW_CACHE;
            pending_wr.prot = AW_PROT;
            pending_wr.qos = AW_QOS;
            pending_wr.data = new[pending_wr.len + 1];
            pending_wr.strb = new[pending_wr.len + 1];
            wr_collect_active = 1'b1;
            wr_beat_count = 0;
        endfunction

        function void capture_w();
            if (!wr_collect_active || pending_wr == null) begin
                $fatal(1, "[INMON ERROR]: W handshake without active AW collection");
            end

            pending_wr.data[wr_beat_count] = W_DATA;
            pending_wr.strb[wr_beat_count] = W_STRB;
            wr_beat_count = wr_beat_count + 1;

            if (W_LAST) begin
                if (wr_beat_count != pending_wr.get_beat_count()) begin
                    $fatal(1, "[INMON ERROR]: W beat count mismatch. expect=%0d get=%0d",
                        pending_wr.get_beat_count(), wr_beat_count);
                end
                wr_complete_mb.put(pending_wr.copy());
                wr_collect_active = 1'b0;
                wr_beat_count = 0;
                pending_wr = null;
            end
        endfunction

        function void capture_ar();
            axi_read_request rd;

            rd = new("mon_observed_read");
            rd.id = AR_ID;
            rd.addr = AR_ADDR;
            rd.len = AR_LEN;
            rd.size = AR_SIZE;
            rd.burst = AR_BURST;
            rd.lock = AR_LOCK;
            rd.cache = AR_CACHE;
            rd.prot = AR_PROT;
            rd.qos = AR_QOS;
            rd_req_mb.put(rd);
        endfunction
    endclass

    // ============================================================================
    //                          Output Monitor
    // ============================================================================

    class axi_output_monitor;
        mailbox #(axi_b_response) act_b_mb;
        mailbox #(axi_r_beat) act_r_mb;
        int unsigned r_beat_index;

        function new(
            mailbox #(axi_b_response) act_b_mb,
            mailbox #(axi_r_beat) act_r_mb
        );
            this.act_b_mb = act_b_mb;
            this.act_r_mb = act_r_mb;
            r_beat_index = 0;
        endfunction

        task automatic run();
            forever begin
                @(posedge ACLK);
                if (!ARESETn) begin
                    r_beat_index = 0;
                    continue;
                end

                if (B_VALID && B_READY) capture_b();
                if (R_VALID && R_READY) capture_r();
            end
        endtask

        function void capture_b();
            axi_b_response b;

            b = new("act_b");
            b.id = B_ID;
            b.resp = B_RESP;
            act_b_mb.put(b);
        endfunction

        function void capture_r();
            axi_r_beat r;

            r = new("act_r");
            r.id = R_ID;
            r.resp = R_RESP;
            r.data = R_DATA;
            r.last = R_LAST;
            r.beat_index = r_beat_index;
            r.addr = '0;
            act_r_mb.put(r);
            r_beat_index = r_beat_index + 1;

            if (R_LAST) r_beat_index = 0;
        endfunction
    endclass

    // ============================================================================
    //                           Reference Model
    // ============================================================================

    class axi_ref_model;
        bit [DATA_W-1:0] mem [0:BRAM_DEPTH-1];
        mailbox #(axi_write_transaction) wr_complete_mb;
        mailbox #(axi_read_request) rd_req_mb;
        mailbox #(axi_b_response) exp_b_mb;
        mailbox #(axi_r_beat) exp_r_mb;

        function new(
            mailbox #(axi_write_transaction) wr_complete_mb,
            mailbox #(axi_read_request) rd_req_mb,
            mailbox #(axi_b_response) exp_b_mb,
            mailbox #(axi_r_beat) exp_r_mb
        );
            this.wr_complete_mb = wr_complete_mb;
            this.rd_req_mb = rd_req_mb;
            this.exp_b_mb = exp_b_mb;
            this.exp_r_mb = exp_r_mb;
            reset_mem();
        endfunction

        function void reset_mem();
            foreach (mem[word_idx]) mem[word_idx] = '0;
        endfunction

        function automatic resp_type request_response(
            input bit [ADDR_W-1:0] address,
            input bit [7:0] length,
            input bit [2:0] size,
            input bit [1:0] burst
        );
            logic [ADDR_W:0] transfer_bytes;
            logic [12:0] boundary_sum;

            transfer_bytes = ({1'b0, length} + 1'b1) << size;
            boundary_sum = {1'b0, address[11:0]} + transfer_bytes[12:0];

            if (burst != AXI_BURST_INCR) return AXI_SLVERR;
            if (size != BYTE_OFFSET_W) return AXI_SLVERR;
            if (address[BYTE_OFFSET_W-1:0] != '0) return AXI_SLVERR;
            if (boundary_sum > 13'd4096) return AXI_SLVERR;
            return AXI_OKAY;
        endfunction

        function automatic resp_type beat_response(
            input resp_type request_resp,
            input bit [ADDR_W-1:0] address
        );
            if (request_resp != AXI_OKAY) return request_resp;
            if ({1'b0, address} >= MEMORY_BYTES) return AXI_DECERR;
            return AXI_OKAY;
        endfunction

        function automatic resp_type merge_response(
            input resp_type accumulated,
            input resp_type current
        );
            if ((accumulated == AXI_DECERR) || (current == AXI_DECERR)) return AXI_DECERR;
            if ((accumulated == AXI_SLVERR) || (current == AXI_SLVERR)) return AXI_SLVERR;
            return AXI_OKAY;
        endfunction

        function void mem_write(
            input bit [ADDR_W-1:0] addr,
            input bit [DATA_W-1:0] data,
            input bit [STRB_W-1:0] strb
        );
            int unsigned word_idx;

            word_idx = addr >> BYTE_OFFSET_W;
            if (word_idx >= BRAM_DEPTH) return;

            for (int byte_idx = 0; byte_idx < STRB_W; byte_idx++) begin
                if (strb[byte_idx]) begin
                    mem[word_idx][byte_idx*8 +: 8] = data[byte_idx*8 +: 8];
                end
            end
        endfunction

        function bit [DATA_W-1:0] mem_read(input bit [ADDR_W-1:0] addr);
            int unsigned word_idx;

            word_idx = addr >> BYTE_OFFSET_W;
            if (word_idx >= BRAM_DEPTH) return '0;
            return mem[word_idx];
        endfunction

        task automatic run();
            fork
                forever process_write();
                forever process_read();
            join_none
        endtask

        function resp_type predict_write_response(input axi_write_transaction wr);
            resp_type req_resp;
            resp_type beat_resp;
            resp_type acc_resp;

            req_resp = request_response(wr.addr, wr.len, wr.size, wr.burst);
            acc_resp = req_resp;

            for (int beat = 0; beat < wr.get_beat_count(); beat++) begin
                beat_resp = beat_response(req_resp, wr.get_beat_address(beat));
                acc_resp = merge_response(acc_resp, beat_resp);
            end

            return acc_resp;
        endfunction

        task automatic process_write();
            axi_write_transaction wr;
            axi_b_response exp_b;
            resp_type req_resp;
            resp_type beat_resp;
            resp_type acc_resp;

            forever begin
                wr_complete_mb.get(wr);
                req_resp = request_response(wr.addr, wr.len, wr.size, wr.burst);
                acc_resp = req_resp;

                for (int beat = 0; beat < wr.get_beat_count(); beat++) begin
                    beat_resp = beat_response(req_resp, wr.get_beat_address(beat));
                    acc_resp = merge_response(acc_resp, beat_resp);

                    if (beat_resp == AXI_OKAY) begin
                        mem_write(
                            wr.get_beat_address(beat),
                            wr.data[beat],
                            wr.strb[beat]
                        );
                    end
                end

                exp_b = new("exp_b");
                exp_b.id = wr.id;
                exp_b.resp = acc_resp;
                exp_b_mb.put(exp_b);
            end
        endtask

        task automatic process_read();
            axi_read_request rd;
            axi_r_beat exp_r;
            resp_type req_resp;
            resp_type beat_resp;

            forever begin
                rd_req_mb.get(rd);
                req_resp = request_response(rd.addr, rd.len, rd.size, rd.burst);

                for (int beat = 0; beat < rd.get_beat_count(); beat++) begin
                    beat_resp = beat_response(req_resp, rd.get_beat_address(beat));
                    exp_r = new("exp_r");
                    exp_r.id = rd.id;
                    exp_r.addr = rd.get_beat_address(beat);
                    exp_r.resp = beat_resp;
                    exp_r.beat_index = beat;
                    exp_r.last = (beat == rd.len);
                    exp_r.data = (beat_resp == AXI_OKAY) ? mem_read(exp_r.addr) : '0;
                    exp_r_mb.put(exp_r);
                end
            end
        endtask
    endclass

    // ============================================================================
    //                              Scoreboard
    // ============================================================================

    class axi_scoreboard;
        mailbox #(axi_b_response) exp_b_mb;
        mailbox #(axi_r_beat) exp_r_mb;
        mailbox #(axi_b_response) act_b_mb;
        mailbox #(axi_r_beat) act_r_mb;

        int unsigned pass_b_count;
        int unsigned pass_r_count;
        int unsigned fail_b_count;
        int unsigned fail_r_count;

        function new(
            mailbox #(axi_b_response) exp_b_mb,
            mailbox #(axi_r_beat) exp_r_mb,
            mailbox #(axi_b_response) act_b_mb,
            mailbox #(axi_r_beat) act_r_mb
        );
            this.exp_b_mb = exp_b_mb;
            this.exp_r_mb = exp_r_mb;
            this.act_b_mb = act_b_mb;
            this.act_r_mb = act_r_mb;
            pass_b_count = 0;
            pass_r_count = 0;
            fail_b_count = 0;
            fail_r_count = 0;
        endfunction

        task automatic run();
            fork
                forever compare_b();
                forever compare_r();
            join_none
        endtask

        function void compare_b_pair(input axi_b_response exp, input axi_b_response act);
            if ((exp.id == act.id) && (exp.resp == act.resp)) begin
                pass_b_count = pass_b_count + 1;
                $display("[SB PASS] B id=%0h resp=%0h", act.id, act.resp);
            end
            else begin
                fail_b_count = fail_b_count + 1;
                $fatal(1,
                    "[SB FAIL] B mismatch. exp_id=%0h act_id=%0h exp_resp=%0h act_resp=%0h",
                    exp.id, act.id, exp.resp, act.resp
                );
            end
        endfunction

        function void compare_r_pair(input axi_r_beat exp, input axi_r_beat act);
            if ((exp.id == act.id) &&
                (exp.beat_index == act.beat_index) &&
                (exp.resp == act.resp) &&
                (exp.last == act.last) &&
                (exp.data == act.data)) begin
                pass_r_count = pass_r_count + 1;
                $display("[SB PASS] R beat=%0d addr=%08h data=%08h resp=%0h last=%0b",
                    act.beat_index, exp.addr, act.data, act.resp, act.last);
            end
            else begin
                fail_r_count = fail_r_count + 1;
                $fatal(1,
                    "[SB FAIL] R mismatch beat=%0d. exp_addr=%08h act_data=%08h exp_data=%08h exp_resp=%0h act_resp=%0h exp_last=%0b act_last=%0b",
                    act.beat_index,
                    exp.addr,
                    act.data,
                    exp.data,
                    exp.resp,
                    act.resp,
                    exp.last,
                    act.last
                );
            end
        endfunction

        task automatic compare_b();
            axi_b_response exp;
            axi_b_response act;

            forever begin
                exp_b_mb.get(exp);
                act_b_mb.get(act);
                compare_b_pair(exp, act);
            end
        endtask

        task automatic compare_r();
            axi_r_beat exp;
            axi_r_beat act;

            forever begin
                exp_r_mb.get(exp);
                act_r_mb.get(act);
                compare_r_pair(exp, act);
            end
        endtask

        function void report();
            $display("================================================================");
            $display("[SCOREBOARD SUMMARY]");
            $display("  B channel : pass=%0d fail=%0d", pass_b_count, fail_b_count);
            $display("  R channel : pass=%0d fail=%0d", pass_r_count, fail_r_count);
            $display("================================================================");
        endfunction
    endclass

    // ============================================================================
    //                         Functional Coverage
    // ============================================================================

    class axi_functional_coverage;
        covergroup cg_axi with function sample(
            input bit [7:0] burst_len,
            input addr_class_e addr_class,
            input strb_class_e strb_class,
            input resp_type req_resp,
            input resp_type beat_resp,
            input bit w_before_aw,
            input int unsigned aw_stall,
            input int unsigned w_stall,
            input int unsigned b_stall,
            input int unsigned ar_stall,
            input int unsigned r_stall
        );
            option.per_instance = 1;

            cp_burst_len: coverpoint burst_len {
                bins single = {0};
                bins short_burst = {[1:3]};
                bins long_burst = {[4:15]};
            }

            cp_addr_class: coverpoint addr_class {
                bins low = {ADDR_CLASS_LOW};
                bins mid = {ADDR_CLASS_MID};
                bins high = {ADDR_CLASS_HIGH};
                bins boundary = {ADDR_CLASS_BOUNDARY};
                bins oob = {ADDR_CLASS_OOB};
            }

            cp_strb_class: coverpoint strb_class {
                bins full = {STRB_CLASS_FULL};
                bins zero = {STRB_CLASS_ZERO};
                bins partial = {STRB_CLASS_PARTIAL};
            }

            cp_req_resp: coverpoint req_resp {
                bins okay = {AXI_OKAY};
                bins slverr = {AXI_SLVERR};
                bins decerr = {AXI_DECERR};
            }

            cp_beat_resp: coverpoint beat_resp {
                bins okay = {AXI_OKAY};
                bins slverr = {AXI_SLVERR};
                bins decerr = {AXI_DECERR};
            }

            cp_w_before_aw: coverpoint w_before_aw {
                bins ordered = {1'b0};
                bins w_first = {1'b1};
            }

            cp_aw_stall: coverpoint aw_stall {
                bins none = {0};
                bins short_stall = {[1:3]};
                bins long_stall = {[4:$]};
            }

            cp_b_stall: coverpoint b_stall {
                bins none = {0};
                bins delayed = {[1:$]};
            }

            cp_r_stall: coverpoint r_stall {
                bins none = {0};
                bins delayed = {[1:$]};
            }

            cross_len_resp: cross cp_burst_len, cp_beat_resp;
            cross_addr_resp: cross cp_addr_class, cp_beat_resp;
            cross_strb_resp: cross cp_strb_class, cp_beat_resp;
        endgroup

        function new();
            cg_axi = new();
        endfunction

        function addr_class_e classify_addr(input bit [ADDR_W-1:0] addr, input bit [7:0] len);
            logic [ADDR_W:0] end_addr;

            end_addr = addr + ((len + 1) << BYTE_OFFSET_W);
            if (addr >= MEMORY_BYTES) return ADDR_CLASS_OOB;
            if (end_addr > MEMORY_BYTES) return ADDR_CLASS_BOUNDARY;
            if (addr < (MEMORY_BYTES / 4)) return ADDR_CLASS_LOW;
            if (addr < (MEMORY_BYTES * 3 / 4)) return ADDR_CLASS_MID;
            return ADDR_CLASS_HIGH;
        endfunction

        function strb_class_e classify_strb(input bit [STRB_W-1:0] strb);
            if (strb == '1) return STRB_CLASS_FULL;
            if (strb == '0) return STRB_CLASS_ZERO;
            return STRB_CLASS_PARTIAL;
        endfunction

        function void sample_write(
            input axi_write_transaction wr,
            input resp_type req_resp,
            input resp_type final_resp,
            input bit w_before_aw,
            input axi_driver driver
        );
            cg_axi.sample(
                wr.len,
                classify_addr(wr.addr, wr.len),
                classify_strb(wr.strb[0]),
                req_resp,
                final_resp,
                w_before_aw,
                driver.aw_stall_cycles,
                driver.w_stall_cycles,
                driver.b_stall_cycles,
                driver.ar_stall_cycles,
                driver.r_stall_cycles
            );
        endfunction

        function void sample_read(
            input axi_read_request rd,
            input resp_type req_resp,
            input resp_type first_beat_resp,
            input axi_driver driver
        );
            cg_axi.sample(
                rd.len,
                classify_addr(rd.addr, rd.len),
                STRB_CLASS_FULL,
                req_resp,
                first_beat_resp,
                1'b0,
                driver.aw_stall_cycles,
                driver.w_stall_cycles,
                driver.b_stall_cycles,
                driver.ar_stall_cycles,
                driver.r_stall_cycles
            );
        endfunction

        function void report();
            $display("================================================================");
            $display("[FUNCTIONAL COVERAGE SUMMARY]");
            $display("  cg_axi coverage = %0.2f%%", cg_axi.get_coverage());
            $display("================================================================");
        endfunction
    endclass

    // ============================================================================
    //                           Environment Wrapper
    // ============================================================================

    class axi_env;
        mailbox #(axi_write_transaction) wr_complete_mb;
        mailbox #(axi_read_request) rd_req_mb;
        mailbox #(axi_b_response) exp_b_mb;
        mailbox #(axi_r_beat) exp_r_mb;
        mailbox #(axi_b_response) act_b_mb;
        mailbox #(axi_r_beat) act_r_mb;

        axi_driver driver;
        axi_input_monitor in_mon;
        axi_output_monitor out_mon;
        axi_ref_model ref_model;
        axi_scoreboard scoreboard;
        axi_functional_coverage cov;

        function new();
            wr_complete_mb = new(0);
            rd_req_mb = new(0);
            exp_b_mb = new(0);
            exp_r_mb = new(0);
            act_b_mb = new(0);
            act_r_mb = new(0);

            driver = new();
            in_mon = new(wr_complete_mb, rd_req_mb);
            out_mon = new(act_b_mb, act_r_mb);
            ref_model = new(wr_complete_mb, rd_req_mb, exp_b_mb, exp_r_mb);
            scoreboard = new(exp_b_mb, exp_r_mb, act_b_mb, act_r_mb);
            cov = new();
        endfunction

        task automatic start();
            fork
                in_mon.run();
                out_mon.run();
                ref_model.run();
                scoreboard.run();
            join_none
        endtask

        function void report();
            scoreboard.report();
            cov.report();
        endfunction
    endclass

    // ============================================================================
    //                           Test Sequences
    // ============================================================================

    class axi_test_lib;
        axi_env env;
        axi_ref_model ref_model;
        int unsigned case_num;

        function new(input axi_env env);
            this.env = env;
            ref_model = env.ref_model;
            case_num = 0;
        endfunction

        function resp_type predict_request(input axi_write_transaction wr);
            return ref_model.request_response(wr.addr, wr.len, wr.size, wr.burst);
        endfunction

        function resp_type predict_write_b_response(input axi_write_transaction wr);
            return ref_model.predict_write_response(wr);
        endfunction

        function resp_type predict_first_beat(input axi_read_request rd);
            resp_type req_resp;
            req_resp = ref_model.request_response(rd.addr, rd.len, rd.size, rd.burst);
            return ref_model.beat_response(req_resp, rd.get_beat_address(0));
        endfunction

        function bit randomize_ok(input axi_write_transaction wr);
            if (!wr.randomize()) begin
                $fatal(1, "[TEST ERROR]: randomize failed for %s", wr.name);
                return 1'b0;
            end
            return 1'b1;
        endfunction

        task automatic run_write_read_check(
            input axi_write_transaction wr,
            input axi_driver_ctrl w_ctrl,
            input axi_driver_ctrl r_ctrl
        );
            axi_read_request rd;

            wr.print();
            env.driver.drive_write(wr, w_ctrl);
            env.cov.sample_write(
                wr,
                predict_request(wr),
                predict_write_b_response(wr),
                w_ctrl.w_before_aw,
                env.driver
            );

            rd = new(wr.name);
            rd.copy_from_write(wr);
            rd.print();
            env.driver.drive_read(rd, r_ctrl);
            env.cov.sample_read(rd, predict_request(wr), predict_first_beat(rd), env.driver);
        endtask

        task automatic seq_basic_single_beat();
            axi_write_transaction wr;
            axi_driver_ctrl ctrl;

            $display("[SEQ] basic single-beat write/read");
            wr = new("seq_basic");
            if (!wr.randomize() with { len == 0; }) $fatal(1, "[TEST ERROR]: seq_basic randomize failed");
            ctrl = new();
            run_write_read_check(wr, ctrl, ctrl);
        endtask

        task automatic seq_random_valid_burst(input int unsigned num = 20);
            axi_write_transaction wr;
            axi_driver_ctrl ctrl;

            $display("[SEQ] random valid burst x%0d", num);
            for (int i = 0; i < num; i++) begin
                case_num = i;
                wr = new($sformatf("seq_random_valid_%0d", i));
                if (!randomize_ok(wr)) continue;
                ctrl = new();
                run_write_read_check(wr, ctrl, ctrl);
            end
        endtask

        task automatic seq_partial_strb(input int unsigned num = 10);
            axi_write_transaction wr;
            axi_driver_ctrl ctrl;

            $display("[SEQ] partial WSTRB x%0d", num);
            for (int i = 0; i < num; i++) begin
                wr = new($sformatf("seq_partial_strb_%0d", i));
                if (!wr.randomize() with {
                    foreach (strb[beat_index]) {
                        strb[beat_index] inside {4'h3, 4'hc, 4'h5, 4'ha};
                    }
                }) $fatal(1, "[TEST ERROR]: seq_partial_strb randomize failed");
                ctrl = new();
                run_write_read_check(wr, ctrl, ctrl);
            end
        endtask

        task automatic seq_w_before_aw(input int unsigned num = 10);
            axi_write_transaction wr;
            axi_driver_ctrl ctrl;

            $display("[SEQ] W-before-AW x%0d", num);
            for (int i = 0; i < num; i++) begin
                wr = new($sformatf("seq_w_before_aw_%0d", i));
                if (!randomize_ok(wr)) continue;
                ctrl = new();
                ctrl.w_before_aw = 1'b1;
                run_write_read_check(wr, ctrl, ctrl);
            end
        endtask

        task automatic seq_backpressure(input int unsigned num = 10);
            axi_write_transaction wr;
            axi_driver_ctrl w_ctrl;
            axi_driver_ctrl r_ctrl;

            $display("[SEQ] B/R backpressure x%0d", num);
            for (int i = 0; i < num; i++) begin
                wr = new($sformatf("seq_backpressure_%0d", i));
                if (!randomize_ok(wr)) continue;
                w_ctrl = new();
                r_ctrl = new();
                w_ctrl.random_b_stall = 1'b1;
                r_ctrl.random_r_stall = 1'b1;
                run_write_read_check(wr, w_ctrl, r_ctrl);
            end
        endtask

        task automatic seq_unaligned_address(input int unsigned num = 5);
            axi_write_transaction wr;
            axi_driver_ctrl ctrl;

            $display("[SEQ] unaligned address (SLVERR) x%0d", num);
            for (int i = 0; i < num; i++) begin
                wr = new($sformatf("seq_unaligned_%0d", i));
                wr.c_aligned_address.constraint_mode(0);
                if (!wr.randomize() with { wr.addr[BYTE_OFFSET_W-1:0] != '0; }) begin
                    $fatal(1, "[TEST ERROR]: seq_unaligned randomize failed");
                end
                ctrl = new();
                run_write_read_check(wr, ctrl, ctrl);
            end
        endtask

        task automatic seq_invalid_burst(input int unsigned num = 3);
            axi_write_transaction wr;
            axi_driver_ctrl ctrl;

            $display("[SEQ] invalid burst type (SLVERR) x%0d", num);
            for (int i = 0; i < num; i++) begin
                wr = new($sformatf("seq_invalid_burst_%0d", i));
                wr.c_supported.constraint_mode(0);
                if (!wr.randomize() with {
                    len inside {[0:15]};
                    size == BYTE_OFFSET_W;
                    burst != AXI_BURST_INCR;
                    lock == 1'b0;
                    cache == 4'b0000;
                    prot == 3'b000;
                    qos == 4'b0000;
                    addr[BYTE_OFFSET_W-1:0] == '0;
                    addr <= (BRAM_DEPTH * STRB_W) - ((len + 1) << size);
                    data.size() == len + 1;
                    strb.size() == len + 1;
                }) $fatal(1, "[TEST ERROR]: seq_invalid_burst randomize failed");
                ctrl = new();
                run_write_read_check(wr, ctrl, ctrl);
            end
        endtask

        task automatic seq_4kb_crossing(input int unsigned num = 3);
            axi_write_transaction wr;
            axi_driver_ctrl ctrl;
            bit [ADDR_W-1:0] base_addr;

            $display("[SEQ] 4KB boundary crossing (SLVERR) x%0d", num);
            for (int i = 0; i < num; i++) begin
                wr = new($sformatf("seq_4kb_cross_%0d", i));
                wr.c_address_range.constraint_mode(0);
                base_addr = 32'h00000FF0;
                if (!wr.randomize() with {
                    len inside {[4:8]};
                    size == BYTE_OFFSET_W;
                    burst == AXI_BURST_INCR;
                    addr == base_addr;
                    data.size() == len + 1;
                    strb.size() == len + 1;
                }) $fatal(1, "[TEST ERROR]: seq_4kb_cross randomize failed");
                ctrl = new();
                run_write_read_check(wr, ctrl, ctrl);
            end
        endtask

        task automatic seq_full_out_of_range(input int unsigned num = 5);
            axi_write_transaction wr;
            axi_driver_ctrl ctrl;

            $display("[SEQ] fully out-of-range address (DECERR) x%0d", num);
            for (int i = 0; i < num; i++) begin
                wr = new($sformatf("seq_full_oob_%0d", i));
                wr.c_address_range.constraint_mode(0);
                if (!wr.randomize() with {
                    addr >= MEMORY_BYTES;
                    addr <= MEMORY_BYTES + 32'h100;
                }) $fatal(1, "[TEST ERROR]: seq_full_oob randomize failed");
                ctrl = new();
                run_write_read_check(wr, ctrl, ctrl);
            end
        endtask

        task automatic seq_burst_middle_out_of_range(input int unsigned num = 5);
            axi_write_transaction wr;
            axi_driver_ctrl ctrl;
            bit [ADDR_W-1:0] start_addr;

            $display("[SEQ] burst-middle out-of-range (mixed DECERR) x%0d", num);
            for (int i = 0; i < num; i++) begin
                wr = new($sformatf("seq_mid_oob_%0d", i));
                wr.c_address_range.constraint_mode(0);
                start_addr = MEMORY_BYTES - STRB_W;
                if (!wr.randomize() with {
                    len inside {[1:3]};
                    size == BYTE_OFFSET_W;
                    burst == AXI_BURST_INCR;
                    addr == start_addr;
                    data.size() == len + 1;
                    strb.size() == len + 1;
                }) $fatal(1, "[TEST ERROR]: seq_mid_oob randomize failed");
                ctrl = new();
                run_write_read_check(wr, ctrl, ctrl);
            end
        endtask

        task automatic seq_write_then_read_stream(input int unsigned num = 5);
            axi_write_transaction wr;
            axi_read_request rd;
            axi_driver_ctrl ctrl;
            int unsigned write_num;
            int unsigned read_num;

            $display("[SEQ] write stream then read stream x%0d", num);
            ctrl = new();
            for (int i = 0; i < num; i++) begin
                write_num = $urandom_range(5, 2);
                for (int w = 0; w < write_num; w++) begin
                    wr = new($sformatf("seq_stream_w_%0d_%0d", i, w));
                    if (!randomize_ok(wr)) continue;
                    wr.print();
                    env.driver.drive_write(wr, ctrl);
                end

                read_num = $urandom_range(5, 2);
                for (int r = 0; r < read_num; r++) begin
                    wr = new($sformatf("seq_stream_r_%0d_%0d", i, r));
                    if (!randomize_ok(wr)) continue;
                    rd = new(wr.name);
                    rd.copy_from_write(wr);
                    rd.print();
                    env.driver.drive_read(rd, ctrl);
                end
            end
        endtask

        task automatic run_all();
            seq_basic_single_beat();
            seq_random_valid_burst(20);
            seq_partial_strb(8);
            seq_w_before_aw(8);
            seq_backpressure(8);
            seq_write_then_read_stream(5);
            seq_unaligned_address(5);
            seq_invalid_burst(3);
            seq_4kb_crossing(3);
            seq_full_out_of_range(5);
            seq_burst_middle_out_of_range(5);
        endtask
    endclass

    // ============================================================================
    //                      Clock Generation and Reset Task
    // ============================================================================

    axi_env env;
    axi_test_lib tests;

    always #(`CLK_PERIOD / 2.0) ACLK = ~ACLK;

    task automatic drive_reset();
        env.driver.init_outputs();
        ARESETn = 1'b1;
        force ACLK = 1'b0;
        #20 ARESETn = 1'b0;
        #20 ARESETn = 1'b1;
        release ACLK;
        @(negedge ACLK);
        env.ref_model.reset_mem();
    endtask

    // ============================================================================
    //                                  Main Flow
    // ============================================================================

    initial begin
        $display("================================================================");
        $display("  [INFO] PATTERN2 class-based DV environment start");
        $display("================================================================");

        $srandom(32'h2026_0912);
        env = new();
        env.start();
        drive_reset();
        tests = new(env);
        tests.run_all();

        #100;
        env.report();

        $display("================================================================");
        $display("      [PASS] : PATTERN2 all sequences completed               ");
        $display("================================================================");
        $finish;
    end

    // ============================================================================
    //                              SystemVerilog Assertion
    // ============================================================================

    S_AW_STABLE: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        AW_VALID && !AW_READY |=> $stable({AW_ID, AW_ADDR, AW_LEN, AW_SIZE, AW_BURST,
            AW_LOCK, AW_CACHE, AW_PROT, AW_QOS}))
    else $fatal(1, "[ASSERT]: AW payload must stay stable while AWVALID=1 and AWREADY=0.");

    S_W_STABLE: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        W_VALID && !W_READY |=> $stable({W_DATA, W_STRB, W_LAST}))
    else $fatal(1, "[ASSERT]: W payload must stay stable while WVALID=1 and WREADY=0.");

    S_B_STABLE: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        B_VALID && !B_READY |=> $stable({B_ID, B_RESP}))
    else $fatal(1, "[ASSERT]: B payload must stay stable while BVALID=1 and BREADY=0.");

    S_AR_STABLE: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        AR_VALID && !AR_READY |=> $stable({AR_ID, AR_ADDR, AR_LEN, AR_SIZE, AR_BURST,
            AR_LOCK, AR_CACHE, AR_PROT, AR_QOS}))
    else $fatal(1, "[ASSERT]: AR payload must stay stable while ARVALID=1 and ARREADY=0.");

    S_R_STABLE: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        R_VALID && !R_READY |=> $stable({R_ID, R_DATA, R_RESP, R_LAST}))
    else $fatal(1, "[ASSERT]: R payload must stay stable while RVALID=1 and RREADY=0.");

    CHECK_RESET_VALID_LOW: assert property(
        @(posedge ACLK) !ARESETn |-> (!AW_VALID && !W_VALID && !AR_VALID))
    else $fatal(1, "[ASSERT]: manager VALID must be low during reset.");

    CHECK_NO_X_AW: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        AW_VALID |-> (!$isunknown({AW_ID, AW_ADDR, AW_LEN, AW_SIZE, AW_BURST,
            AW_LOCK, AW_CACHE, AW_PROT, AW_QOS})))
    else $fatal(1, "[ASSERT]: AW payload contains X/Z while AWVALID=1.");

    CHECK_NO_X_W: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        W_VALID |-> (!$isunknown({W_DATA, W_STRB, W_LAST})))
    else $fatal(1, "[ASSERT]: W payload contains X/Z while WVALID=1.");

    CHECK_NO_X_AR: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        AR_VALID |-> (!$isunknown({AR_ID, AR_ADDR, AR_LEN, AR_SIZE, AR_BURST,
            AR_LOCK, AR_CACHE, AR_PROT, AR_QOS})))
    else $fatal(1, "[ASSERT]: AR payload contains X/Z while ARVALID=1.");

endmodule
