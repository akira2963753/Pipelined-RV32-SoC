/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    PATTERN.sv
* Project:      RISC-V CPU AXI4 Bus
* Module:       PATTERN
* Author:       Marco <harry2963753@gmail.com>
*
* Description:
*   Class-based non-UVM AXI4 verification environment for learning.
*   Components: driver, input/output monitor, reference model,
*               scoreboard, functional coverage, assertions.
*
*
******************************************************************************/

`timescale 1ns/1ps

import AXI4_PKG::*;

`define CLK_PERIOD 10.0
`define HS_TIMEOUT 1000

module PATTERN #(
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

    // ============================================================================
    //                                  Constraints
    // ============================================================================    
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
    // ============================================================================
    //                                  Function
    // ============================================================================
        function new(input string name = "axi_write_transaction");
            this.name = name;
        endfunction

        function int unsigned get_beat_count();
            return len + 1;
        endfunction

        function bit [ADDR_W-1:0] get_beat_address(input int unsigned beat_index);
            return addr + (beat_index << size);
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

    // ============================================================================
    //                          Request and Response Class
    // ============================================================================

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
        string name;
        bit [ID_W-1:0] id;
        resp_type resp;

        function new(input string name = "B");
            this.name = name;
        endfunction
    endclass

    class axi_r_beat;
        string name;
        bit [ID_W-1:0] id;
        bit [ADDR_W-1:0] addr;
        bit [DATA_W-1:0] data;
        resp_type resp;
        bit last;
        int unsigned beat_index;

        function new(input string name = "R");
            this.name = name;
        endfunction
    endclass

    // ============================================================================
    //                         Driver Control Structs
    // ============================================================================

    class axi_driver_ctrl;
        int unsigned aw_delay_cycles;
        int unsigned w_delay_cycles;
        int unsigned ar_delay_cycles;
        rand int unsigned b_ready_delay;
        rand int unsigned r_ready_delay;

        constraint c_b_ready_delay {
            b_ready_delay inside {[0:10]};
        }

        constraint c_r_ready_delay {
            r_ready_delay inside {[0:10]};
        }

        function new();
            aw_delay_cycles = 0;
            w_delay_cycles = 0;
            ar_delay_cycles = 0;
            b_ready_delay = 0;
            r_ready_delay = 0;
        endfunction
    endclass

    // ============================================================================
    //                              AXI Driver
    // ============================================================================

    class axi_driver;
        // 紀錄 AW_VALID 送出，但是 AW_READY = 0 的 cycle
        int unsigned aw_stall_cycles;
        // 紀錄 W_VALID 送出，但是 W_READY = 0 的 cylce
        int unsigned w_stall_cycles;
        // 紀錄 driver 故意讓 B_READY = 0 的 cycle
        int unsigned b_stall_cycles;
        // 紀錄 AR_VALID 送出，但是 AR_READY = 0 的 cylce
        int unsigned ar_stall_cycles;
        // 紀錄 driver 故意讓 R_READY = 0 的 cycle
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
                else $fatal(1,
                            "================================================================\n"
                            "   [DRV FAIL]: AW HANDSHAKE TIMEOUT !                           \n"
                            "   AW_ID = %0h, AW_ADDR = %0h, cycles = %0d                     \n"
                            "================================================================", 
                            AW_ID, AW_ADDR, cycles);
            end

            @(negedge ACLK);
            AW_VALID = 1'b0;
        endtask

        task automatic handshake_w(
            input axi_write_transaction txn,
            input int unsigned pre_delay = 0
        );
            int cycles;

            repeat(pre_delay) @(negedge ACLK);
            @(negedge ACLK);
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
                    else $fatal(1, 
                                "================================================================\n"
                                "   [DRV FAIL]: W_HANDSHAKE TIMEOUT !                            \n"
                                "   beat = %0d, cycles = %0d                                     \n"
                                "================================================================\n",
                                beat, cycles);
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
                else $fatal(1,
                    "================================================================\n"
                    "   [DRV FAIL]: AR HANDSHAKE TIMEOUT !                           \n"
                    "   AR_ID = %0h, AR_ADDR = %0h, cycles = %0d                     \n"
                    "================================================================",
                    AR_ID, AR_ADDR, cycles);
            end

            @(negedge ACLK);
            AR_VALID = 1'b0;
        endtask

        task automatic accept_b(input axi_driver_ctrl ctrl);
            int cycles;

            B_READY = 1'b0;
            repeat(ctrl.b_ready_delay) begin
                @(negedge ACLK);
                b_stall_cycles = b_stall_cycles + 1;
            end

            B_READY = 1'b1;
            cycles = 0;
            while (!B_VALID) begin
                @(negedge ACLK);
                cycles = cycles + 1;
                CHECK_DRV_B_HS: assert (cycles < `HS_TIMEOUT)
                else $fatal(1,
                    "================================================================\n"
                    "   [DRV FAIL]: B HANDSHAKE TIMEOUT !                            \n"
                    "   B_ID = %0h, B_RESP = %0h, cycles = %0d                       \n"
                    "================================================================",
                    B_ID, B_RESP, cycles);
            end

            @(negedge ACLK);
            B_READY = 1'b0;
        endtask

        task automatic accept_r(
            input int unsigned beat_count,
            input axi_driver_ctrl ctrl
        );
            int cycles;

            R_READY = 1'b0;

            for (int beat = 0; beat < beat_count; beat++) begin
                repeat(ctrl.r_ready_delay) begin
                    @(negedge ACLK);
                    r_stall_cycles = r_stall_cycles + 1;
                end

                R_READY = 1'b1;
                cycles = 0;
                while (!R_VALID) begin
                    @(negedge ACLK);
                    cycles = cycles + 1;
                    CHECK_DRV_R_HS: assert (cycles < `HS_TIMEOUT)
                    else $fatal(1,
                        "================================================================\n"
                        "   [DRV FAIL]: R HANDSHAKE TIMEOUT !                            \n"
                        "   beat = %0d, R_ID = %0h, R_RESP = %0h, cycles = %0d           \n"
                        "================================================================",
                        beat, R_ID, R_RESP, cycles);
                end

                @(negedge ACLK);
                R_READY = 1'b0;
            end
        endtask

        task automatic drive_write(
            input axi_write_transaction txn,
            input axi_driver_ctrl ctrl
        );
            // AW and W are independent AXI channels. Their configured delays
            // determine whether AW, W, or both become valid first.
            fork
                handshake_aw(txn, ctrl.aw_delay_cycles);
                handshake_w(txn, ctrl.w_delay_cycles);
            join

            accept_b(ctrl);
        endtask

        task automatic drive_read(
            input axi_read_request rd,
            input axi_driver_ctrl ctrl
        );
            handshake_ar(rd, ctrl.ar_delay_cycles);
            accept_r(rd.get_beat_count(), ctrl);
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
                end
                else begin
                    if (AW_VALID && AW_READY) capture_aw();
                    if (W_VALID && W_READY) capture_w();
                    if (AR_VALID && AR_READY) capture_ar();
                end
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

        task automatic capture_w();
            if (!wr_collect_active || pending_wr == null) begin
                $fatal(1,
                    "================================================================\n"
                    "   [INMON FAIL]: W HANDSHAKE WITHOUT ACTIVE AW COLLECTION !     \n"
                    "   W_DATA = %08h, W_STRB = %0h, W_LAST = %0b                    \n"
                    "================================================================",
                    W_DATA, W_STRB, W_LAST);
            end

            pending_wr.data[wr_beat_count] = W_DATA;
            pending_wr.strb[wr_beat_count] = W_STRB;
            wr_beat_count = wr_beat_count + 1;

            if (W_LAST) begin
                if (wr_beat_count != pending_wr.get_beat_count()) begin
                    $fatal(1,
                        "================================================================\n"
                        "   [INMON FAIL]: W BEAT COUNT MISMATCH !                        \n"
                        "   expected = %0d, observed = %0d                                \n"
                        "================================================================",
                        pending_wr.get_beat_count(), wr_beat_count);
                end
                // Ownership moves to the mailbox; this monitor does not reuse
                // or modify pending_wr after the transaction is published.
                wr_complete_mb.put(pending_wr);
                wr_collect_active = 1'b0;
                wr_beat_count = 0;
                pending_wr = null;
            end
        endtask

        task automatic capture_ar();
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
        endtask
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
                end
                else begin
                    if (B_VALID && B_READY) capture_b();
                    if (R_VALID && R_READY) capture_r();
                end
            end
        endtask

        task automatic capture_b();
            axi_b_response b;

            b = new("act_b");
            b.id = B_ID;
            b.resp = B_RESP;
            act_b_mb.put(b);
        endtask

        task automatic capture_r();
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
        endtask
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

            // Calculate the total number of bytes transferred by one burst.
            transfer_bytes = ({1'b0, length} + 1'b1) * (2**size);
            // Calculate the total address boundary
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
            if ({1'b0, address} >= MEMORY_BYTES) return AXI_DECERR;
            else return request_resp;
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
            // 這裡要轉成 word address, 因為 reference memory 是吃 word address
            int unsigned word_idx;
            word_idx = addr >> BYTE_OFFSET_W;

            if (word_idx >= BRAM_DEPTH) return;

            for (int byte_idx = 0; byte_idx < STRB_W; byte_idx++) begin
                if (strb[byte_idx]) mem[word_idx][byte_idx*8 +: 8] = data[byte_idx*8 +: 8];
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
                    "================================================================\n"
                    "   [SB FAIL]: B RESPONSE MISMATCH !                             \n"
                    "   expected: B_ID = %0h, B_RESP = %0h                           \n"
                    "   actual  : B_ID = %0h, B_RESP = %0h                           \n"
                    "================================================================",
                    exp.id, exp.resp, act.id, act.resp
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
                    "================================================================\n"
                    "   [SB FAIL]: R BEAT MISMATCH !                                 \n"
                    "   beat = %0d, address = %08h                                   \n"
                    "   expected: data = %08h, resp = %0h, last = %0b                \n"
                    "   actual  : data = %08h, resp = %0h, last = %0b                \n"
                    "================================================================",
                    act.beat_index,
                    exp.addr,
                    exp.data,
                    exp.resp,
                    exp.last,
                    act.data,
                    act.resp,
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
                $fatal(1,
                    "================================================================\n"
                    "   [TEST FAIL]: RANDOMIZATION FAILED !                          \n"
                    "   transaction = %s                                              \n"
                    "================================================================",
                    wr.name);
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
                w_ctrl.w_delay_cycles < w_ctrl.aw_delay_cycles,
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
            if (!wr.randomize() with { len == 0; }) $fatal(1,
                "================================================================\n"
                "   [TEST FAIL]: seq_basic RANDOMIZATION FAILED !                \n"
                "================================================================");
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
                }) $fatal(1,
                    "================================================================\n"
                    "   [TEST FAIL]: seq_partial_strb RANDOMIZATION FAILED !         \n"
                    "================================================================");
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
                ctrl.aw_delay_cycles = $urandom_range(8, 1);
                ctrl.w_delay_cycles = 0;
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
                if (!w_ctrl.randomize() with {
                    b_ready_delay inside {[1:5]};
                    r_ready_delay == 0;
                }) $fatal(1,
                    "================================================================\n"
                    "   [TEST FAIL]: B BACKPRESSURE RANDOMIZATION FAILED !           \n"
                    "================================================================");
                if (!r_ctrl.randomize() with {
                    b_ready_delay == 0;
                    r_ready_delay inside {[1:5]};
                }) $fatal(1,
                    "================================================================\n"
                    "   [TEST FAIL]: R BACKPRESSURE RANDOMIZATION FAILED !           \n"
                    "================================================================");
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
                    $fatal(1,
                        "================================================================\n"
                        "   [TEST FAIL]: seq_unaligned RANDOMIZATION FAILED !            \n"
                        "================================================================");
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
                }) $fatal(1,
                    "================================================================\n"
                    "   [TEST FAIL]: seq_invalid_burst RANDOMIZATION FAILED !        \n"
                    "================================================================");
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
                }) $fatal(1,
                    "================================================================\n"
                    "   [TEST FAIL]: seq_4kb_cross RANDOMIZATION FAILED !            \n"
                    "================================================================");
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
                }) $fatal(1,
                    "================================================================\n"
                    "   [TEST FAIL]: seq_full_oob RANDOMIZATION FAILED !             \n"
                    "================================================================");
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
                }) $fatal(1,
                    "================================================================\n"
                    "   [TEST FAIL]: seq_mid_oob RANDOMIZATION FAILED !              \n"
                    "================================================================");
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
    else $fatal(1,
        "================================================================\n"
        "   [ASSERT FAIL]: AW PAYLOAD CHANGED WHILE STALLED !            \n"
        "   AW_VALID = %0b, AW_READY = %0b, AW_ADDR = %08h               \n"
        "================================================================",
        AW_VALID, AW_READY, AW_ADDR);

    S_W_STABLE: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        W_VALID && !W_READY |=> $stable({W_DATA, W_STRB, W_LAST}))
    else $fatal(1,
        "================================================================\n"
        "   [ASSERT FAIL]: W PAYLOAD CHANGED WHILE STALLED !             \n"
        "   W_VALID = %0b, W_READY = %0b, W_DATA = %08h                  \n"
        "================================================================",
        W_VALID, W_READY, W_DATA);

    S_B_STABLE: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        B_VALID && !B_READY |=> $stable({B_ID, B_RESP}))
    else $fatal(1,
        "================================================================\n"
        "   [ASSERT FAIL]: B PAYLOAD CHANGED WHILE STALLED !             \n"
        "   B_VALID = %0b, B_READY = %0b, B_ID = %0h, B_RESP = %0h       \n"
        "================================================================",
        B_VALID, B_READY, B_ID, B_RESP);

    S_AR_STABLE: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        AR_VALID && !AR_READY |=> $stable({AR_ID, AR_ADDR, AR_LEN, AR_SIZE, AR_BURST,
            AR_LOCK, AR_CACHE, AR_PROT, AR_QOS}))
    else $fatal(1,
        "================================================================\n"
        "   [ASSERT FAIL]: AR PAYLOAD CHANGED WHILE STALLED !            \n"
        "   AR_VALID = %0b, AR_READY = %0b, AR_ADDR = %08h               \n"
        "================================================================",
        AR_VALID, AR_READY, AR_ADDR);

    S_R_STABLE: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        R_VALID && !R_READY |=> $stable({R_ID, R_DATA, R_RESP, R_LAST}))
    else $fatal(1,
        "================================================================\n"
        "   [ASSERT FAIL]: R PAYLOAD CHANGED WHILE STALLED !             \n"
        "   R_VALID = %0b, R_READY = %0b, R_ID = %0h, R_DATA = %08h      \n"
        "================================================================",
        R_VALID, R_READY, R_ID, R_DATA);

    CHECK_RESET_VALID_LOW: assert property(
        @(posedge ACLK) !ARESETn |-> (!AW_VALID && !W_VALID && !AR_VALID))
    else $fatal(1,
        "================================================================\n"
        "   [ASSERT FAIL]: MANAGER VALID ASSERTED DURING RESET !         \n"
        "   AW_VALID = %0b, W_VALID = %0b, AR_VALID = %0b                \n"
        "================================================================",
        AW_VALID, W_VALID, AR_VALID);

    CHECK_NO_X_AW: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        AW_VALID |-> (!$isunknown({AW_ID, AW_ADDR, AW_LEN, AW_SIZE, AW_BURST,
            AW_LOCK, AW_CACHE, AW_PROT, AW_QOS})))
    else $fatal(1,
        "================================================================\n"
        "   [ASSERT FAIL]: AW PAYLOAD CONTAINS X/Z !                     \n"
        "================================================================");

    CHECK_NO_X_W: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        W_VALID |-> (!$isunknown({W_DATA, W_STRB, W_LAST})))
    else $fatal(1,
        "================================================================\n"
        "   [ASSERT FAIL]: W PAYLOAD CONTAINS X/Z !                      \n"
        "================================================================");

    CHECK_NO_X_AR: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        AR_VALID |-> (!$isunknown({AR_ID, AR_ADDR, AR_LEN, AR_SIZE, AR_BURST,
            AR_LOCK, AR_CACHE, AR_PROT, AR_QOS})))
    else $fatal(1,
        "================================================================\n"
        "   [ASSERT FAIL]: AR PAYLOAD CONTAINS X/Z !                     \n"
        "================================================================");

endmodule
