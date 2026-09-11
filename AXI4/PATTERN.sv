/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    PATTERN.sv
* Project:      RISC-V CPU AXI4 Bus
* Module:       PATTERN
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         Vivado 2025.1
*
******************************************************************************/

`define CLK_PERIOD 10.0
`define TIMEOUT 20000000

//import AXI4_PKG::*;

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

    // 若 DATA 32 bits，因此每個 word address 會有 4 Bytes
    localparam int STRB_W = DATA_W / 8;
    localparam int BYTE_OFFSET_W = $clog2(STRB_W);
    localparam logic [1:0] AXI_BURST_FIXED = 2'b00;
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;
    localparam logic [1:0] AXI_BURST_WRAP = 2'b10;
    localparam logic [ID_W-1:0] WRITE_ID = 4'h5;
    localparam logic [ID_W-1:0] READ_ID = 4'ha;
    phase_type phase_status;
    
    bit [31:0] case_num;

    // ============================================================================
    //                  Write Transaction Randomization Class
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

        constraint c_address_range { // 確保整個 Burst 都在 BRAM 的範圍內
            addr <= (BRAM_DEPTH * STRB_W) - ((len + 1) << size);
        }

        constraint c_payload_size { // 定義 Dyanmic Array 是取決於 length
            data.size() == len + 1;
            strb.size() == len + 1;
        }

        constraint c_solve_order { // 必須先決定好 len 才能夠決定 addr
            solve len before addr;
        }

        function new(input string name = "axi_write_transaction");
            this.name = name;
        endfunction

        function int unsigned get_beat_count();
            return len + 1;
        endfunction

        function bit [ADDR_W-1:0] get_beat_address(
            input int unsigned beat_index
        );
            return addr + (beat_index << size);
        endfunction

        function void print();
            $display("================================================================");
            $display("[%s] id=%0h addr=%08h len=%0d beats=%0d size=%0d burst=%0b",
                name,
                id,
                addr,
                len,
                get_beat_count(),
                size,
                burst
            );
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

    axi_write_transaction write_txn;


    // ============================================================================
    //                     Create The Golden Memory for checking
    // ============================================================================

    class axi_golden_mem;
        bit [DATA_W-1:0] golden_mem [0:BRAM_DEPTH-1];

        function new();
            reset();
        endfunction

        function void reset();
            foreach (golden_mem[word_idx]) begin
                golden_mem[word_idx] = '0;
            end
        endfunction

        function void write(
            input bit [ADDR_W-1:0] addr,
            input bit [DATA_W-1:0] data,
            input bit [STRB_W-1:0] strb
        );
            int unsigned word_idx;

            word_idx = addr >> BYTE_OFFSET_W;

            for (int byte_idx = 0; byte_idx < STRB_W; byte_idx++) begin
                if (strb[byte_idx]) begin
                    golden_mem[word_idx][byte_idx*8 +: 8] = data[byte_idx*8 +: 8];
                end
            end
        endfunction

        function bit [DATA_W-1:0] read(
            input bit [ADDR_W-1:0] addr
        );
            int unsigned word_idx;

            word_idx = addr >> BYTE_OFFSET_W;
            return golden_mem[word_idx];
        endfunction

    endclass

    axi_golden_mem golden_model;

    // ============================================================================
    //                      Clock Generation and Reset Task
    // ============================================================================
    always #(`CLK_PERIOD / 2.0) ACLK = ~ACLK;

    task automatic drive_reset();
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

        ARESETn = 1'b1;
        force ACLK = 1'b0;
        #20 ARESETn = 1'b0;
        #20 ARESETn = 1'b1;
        release ACLK;
        @(negedge ACLK);
    endtask

    // ============================================================================
    //                          AXI Write Address Task
    // ============================================================================ 

    task automatic send_aw(input axi_write_transaction txn);
        int cycles;

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
        
        while(!AW_READY) begin
            @(negedge ACLK);
            cycles = cycles + 1;
            CHECK_AW_HS: assert(cycles < 100)
            else $fatal(1, "[ERROR]: AW HandShake Timeout");
        end

        @(negedge ACLK) AW_VALID = 1'b0; // 握手成功

    endtask
    
    // ============================================================================
    //                              AXI Write Task
    // ============================================================================ 

    task automatic send_w(input axi_write_transaction txn, input update_golden);
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

                CHECK_W_HS: assert (cycles < 100)
                else $fatal(1, "[ERROR] : W handshake timeout");
            end

            @(negedge ACLK);

            if(update_golden) begin
                golden_model.write(
                    txn.get_beat_address(beat),
                    txn.data[beat],
                    txn.strb[beat]
                );
            end
        end

        W_DATA = '0;
        W_STRB = '0;
        W_LAST = 1'b0;
        W_VALID = 1'b0;
    endtask

    // ============================================================================
    //                          AXI Write Response Task
    // ============================================================================ 

    task automatic wait_b(
        input axi_write_transaction txn,
        input resp_type exp_resp);

        int cycles;
        cycles = 0;
        B_READY = 1'b1;

        while(!B_VALID) begin
            @(negedge ACLK);
            cycles = cycles + 1;
            CHECK_B_HS: assert(cycles < 100)
            else $fatal(1, "[ERROR]: B HandShake Timeout");
        end

        @(negedge ACLK);

        CHECK_B_ID: assert (B_ID == txn.id)
        else $fatal(1, "[ERROR]: B_ID Mismatch. Expected = %0h, Get = %0h",
        txn.id, B_ID);

        CHECK_B_RESP: assert (B_RESP == exp_resp)
        else $fatal(1, "[ERROR]: B_RESP Mismatch. Expected = %0h, Get = %0h", exp_resp, B_RESP);

        B_READY = 1'b0;
    endtask

    // ============================================================================
    //                          AXI Read Address Task
    // ============================================================================

    task automatic send_ar(input axi_write_transaction txn);
        int cycles;

        cycles = 0;
        AR_ID = READ_ID;
        AR_ADDR = txn.addr;
        AR_LEN = txn.len;
        AR_SIZE = txn.size;
        AR_BURST = txn.burst;
        AR_LOCK = txn.lock;
        AR_CACHE = txn.cache;
        AR_PROT = txn.prot;
        AR_QOS = txn.qos;
        AR_VALID = 1'b1;

        // Wait AR handshake
        while (!AR_READY) begin
            @(negedge ACLK);
            cycles = cycles + 1;

            CHECK_AR_HS: assert (cycles < 100)
            else $fatal(1, "[ERROR] : AR HandShake Timeout");
        end

        @(negedge ACLK);
        AR_VALID = 1'b0;
    endtask

    // ============================================================================
    //                          AXI Read and Check Task
    // ============================================================================

    task automatic receive_r_and_check(input axi_write_transaction txn, input resp_type exp_resp);
        bit [ADDR_W-1:0] beat_addr;
        bit [DATA_W-1:0] expected_data;
        int cycles;

        @(negedge ACLK);
        R_READY = 1'b1;

        for (int beat = 0; beat < txn.get_beat_count(); beat++) begin
            cycles = 0;

            while (!R_VALID) begin
                @(negedge ACLK);
                cycles = cycles + 1;

                CHECK_R_HS: assert (cycles < 100)
                else $fatal(1, "[ERROR] : R HandShake Timeout. Beat=%0d", beat);
            end

            beat_addr = txn.get_beat_address(beat);
            expected_data = golden_model.read(beat_addr);

            CHECK_R_ID: assert (R_ID == READ_ID)
            else $fatal(1, "[ERROR] : R_ID mismatch. Expected=%0h, Get=%0h",
                READ_ID,
                R_ID
            );

            CHECK_R_RESP: assert (R_RESP == exp_resp)
            else $fatal(1, "[ERROR] : R_RESP mismatch. Beat=%0d, Expected=%0h, Get=%0h",
                beat,
                exp_resp,
                R_RESP
            );

            CHECK_R_DATA: assert (R_DATA == ((exp_resp==AXI_OKAY)? expected_data : '0))
            else $fatal(1, "[ERROR] : R_DATA mismatch. Beat=%0d, Address=%08h, Expected=%08h, Get=%08h",
                beat,
                beat_addr,
                expected_data,
                R_DATA
            );

            CHECK_R_LAST: assert (R_LAST == (beat == txn.len))
            else $fatal(1, "[ERROR] : R_LAST mismatch. Beat=%0d, Expected=%0b, Get=%0b",
                beat,
                beat == txn.len,
                R_LAST
            );

            $display("[PASS] : Read beat=%0d, address=%08h, data=%08h",
                beat,
                beat_addr,
                R_DATA
            );

            @(negedge ACLK);
        end

        R_READY = 1'b0;
    endtask

    // ============================================================================ 
    //                                  Phase Task
    // ============================================================================ 
    task automatic phase1_task();
        for(int i = 0; i < 100; i++) begin
            case_num = i;
            // 這邊要使用 sformatf 先將 i 帶入字串裡面再送入至 new
            write_txn = new($sformatf("Phase 1: No.%0d", i));
            write_txn.randomize();
            write_txn.print();
            send_aw(write_txn);
            send_w(write_txn, 1);
            wait_b(write_txn, AXI_OKAY);
            send_ar(write_txn);
            receive_r_and_check(write_txn, AXI_OKAY);
        end
        $display("[PHASE 1 PASS]");
    endtask;

    // 這個 task 比較特殊一點，因為如果使用順序的話 send_w 會卡住 w handshake 的邏輯
        task automatic write_w_before_aw(input axi_write_transaction txn);
            fork
                send_w(txn, 1);
                begin
                    // 隨機產生 0 ~ 10 cycle 的 delay
                    repeat($urandom_range(10,0)) @(negedge ACLK);
                    send_aw(txn);
                end
            join
    
            wait_b(txn, AXI_OKAY);
        endtask

    task automatic phase2_task();
        for(int i = 0; i < 100; i++) begin
            case_num = i;
            write_txn = new($sformatf("Phase 2: No.%0d", i));
            write_txn.randomize();
            write_txn.print();
            write_w_before_aw(write_txn);
            send_ar(write_txn);
            receive_r_and_check(write_txn, AXI_OKAY);
        end
        $display("[PHASE 2 PASS]");
    endtask

    task automatic concurrent_wr(input axi_write_transaction txn);
        begin
            send_aw(txn);
            fork
                begin 
                    send_w(txn, 1);
                    wait_b(txn, AXI_OKAY);
                end
                
                begin
                    send_ar(txn);
                    receive_r_and_check(txn, AXI_OKAY);
                end
            join
        end
    endtask

    task automatic phase3_task();
        for(int i = 0; i < 100; i++) begin
            case_num = i;
            write_txn = new($sformatf("Phase 3: No.%0d", i));
            write_txn.randomize();
            write_txn.print();
            concurrent_wr(write_txn);
        end
        $display("[PHASE 3 PASS]");
    endtask

    task automatic phase4_task();
        int write_num;
        int read_num;

        for(int i = 0; i < 100; i++) begin
            case_num = i;
            write_txn = new($sformatf("Phase 4: No.%0d", i));
            write_num = $urandom_range(20, 1);
            for(int n = 0; n < write_num; n++) begin
                $display("Write Operation No.%0d", n);
                write_txn.randomize();
                write_txn.print();
                send_aw(write_txn);
                send_w(write_txn, 1);
                wait_b(write_txn, AXI_OKAY);
            end

            read_num = $urandom_range(20, 1);
            for(int n = 0; n < read_num; n++) begin
                $display("Read Operation No.%0d", n);
                write_txn.randomize();
                write_txn.print();
                send_ar(write_txn);
                receive_r_and_check(write_txn, AXI_OKAY);
            end
        end
    endtask

    task automatic phase5_task();
        for(int i = 0; i < 100; i++) begin
            case_num = i;
            write_txn = new($sformatf("Phase 5: No.%0d", i));
            // 關閉 contraints
            write_txn.c_aligned_address.constraint_mode(0);

            write_txn.randomize() with {
                write_txn.addr[BYTE_OFFSET_W-1:0] != '0;
            };

            write_txn.print();
            send_aw(write_txn);
            send_w(write_txn, 0);
            wait_b(write_txn, AXI_SLVERR);
            send_ar(write_txn);
            receive_r_and_check(write_txn, AXI_SLVERR);
        end
    endtask

    task automatic phase6_task();
        for(int i = 0; i < 100; i++) begin
            case_num = i;
            write_txn = new($sformatf("Phase 6: No.%0d", i));
            // 關閉 contraints
            write_txn.c_address_range.constraint_mode(0);

            write_txn.randomize() with {
                addr > (BRAM_DEPTH * STRB_W) - ((len + 1) << size);
            };

            write_txn.print();
            send_aw(write_txn);
            send_w(write_txn, 0);
            wait_b(write_txn, AXI_DECERR);
            send_ar(write_txn);
            receive_r_and_check(write_txn, AXI_DECERR);
        end
    endtask


    // ============================================================================ 
    //                                  Main Flow
    // ============================================================================ 

    initial begin
        golden_model = new();
        drive_reset();

        // ========================================================================
        //                          Constrained Random Test
        // ========================================================================
        // Phase 1, AW -> W -> AR -> R and check 
        phase_status = PHASE1;
        phase1_task();

        // Phase 2, W -> AW -> AR -> R and check
        phase_status = PHASE2;
        phase2_task();

        // Phase 3, Concurrently Write and Read
        phase_status = PHASE3;
        phase3_task();

        // Phase 4, 隨機交叉連續寫入與讀出
        phase_status = PHASE4;
        phase4_task();

        // ========================================================================
        //                              Direct Error Test
        // ========================================================================

        // Phase 5, unalign address
        phase_status = PHASE5;
        phase5_task();

        // Phae 6, address exceeds the BRAM range. 
        phase_status = PHASE6;
        phase6_task();

        $display("================================================================");
        $display("      [PASS] : All AXI write and readback cases completed       ");
        $display("================================================================");

        #100 $finish;
    end

    // ============================================================================ 
    //                              SystemVerilog Assertion
    // ============================================================================ 
    // Property Name: assert property(condition) <pass event> else <fail event>

    // 規定握手失敗後，並須要保持穩定，不能傳送下一筆資料
    S_AW_STABLE: assert property(
        @(posedge ACLK) disable iff(!ARESETn) 
        AW_VALID && !AW_READY |=> $stable({AW_ID, AW_ADDR, AW_LEN, AW_SIZE, AW_BURST,
        AW_LOCK, AW_CACHE, AW_PROT, AW_QOS}))
    else $fatal(1, "[ERROR]: AW informations must be stable after AW_VALID high & AW_READY low.");

    S_W_STABLE: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        W_VALID && !W_READY |=> $stable({W_DATA, W_STRB, W_LAST}))
    else $fatal(1, "[ERROR]: W informations must be stable after W_VALID high & W_READY low.");
    
    S_P_STABLE: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        B_VALID && !B_READY |=> $stable({B_ID, B_RESP}))
    else $fatal(1, "[ERROR]: B informations must be stable after B_VALID high & B_READY low.");

    S_AR_STABLE: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        AR_VALID && !AR_READY |=> $stable({AR_ID, AR_ADDR, AR_LEN, AR_SIZE, AR_BURST,
        AR_LOCK, AR_CACHE, AR_PROT, AR_QOS}))
    else $fatal(1, "[ERROR]: AR informations must be stable after AR_VALID high and AR_READY low.");

    S_R_STABLE: assert property(
        @(posedge ACLK) disable iff(!ARESETn)
        R_VALID && !R_READY |=> $stable({R_ID, R_DATA, R_RESP, R_LAST}))
    else $fatal(1, "[ERROR]: R informations must be stable after R_READY high and R_VALID low.");

    CHECK_RESET_VALID_LOW: assert property(
        @(posedge ACLK) !ARESETn |-> (!AW_VALID && !W_VALID && !B_VALID && !AR_VALID && !R_VALID)) 
    else $fatal(1, "[ERROR]: VALID signal asserted during reset");
    
endmodule
