/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    D_Cache.sv
* Project:      RISC-V CPU Cache
* Module:       D_Cache
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

`timescale 1ns/1ps

import AXI4_PKG::*;

module D_Cache #(
    parameter int DATA_W = 32,
    parameter int ADDR_W = 32,
    parameter int ID_W = 4,
    parameter int SET = 64,
    parameter int BLOCK_WORD_SIZE = 8
) (
    input logic ACLK,
    input logic ARESETn,

    input logic CPU_REQ_VALID,
    output logic CPU_REQ_READY,
    input logic [ADDR_W-1:0] CPU_REQ_ADDR,
    input logic CPU_REQ_WRITE,
    input logic [DATA_W-1:0] CPU_REQ_WDATA,
    input logic [DATA_W/8-1:0] CPU_REQ_WSTRB,
    output logic CPU_RSP_VALID,
    input logic CPU_RSP_READY,
    output logic [DATA_W-1:0] CPU_RSP_DATA,
    output logic CPU_RSP_ERROR,

    input logic INVALIDATE_VALID,
    output logic INVALIDATE_READY,

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

    output logic [DATA_W-1:0] W_DATA,
    output logic [DATA_W/8-1:0] W_STRB,
    output logic W_LAST,
    output logic W_VALID,
    input logic W_READY,

    input logic [ID_W-1:0] B_ID,
    input resp_type B_RESP,
    input logic B_VALID,
    output logic B_READY,

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

    input logic [ID_W-1:0] R_ID,
    input logic [DATA_W-1:0] R_DATA,
    input resp_type R_RESP,
    input logic R_LAST,
    input logic R_VALID,
    output logic R_READY
);

    localparam int WAY_COUNT = 2;
    localparam int STRB_W = DATA_W / 8;
    localparam int BYTE_LSB = $clog2(STRB_W);
    localparam int WORD_OFFSET_W = $clog2(BLOCK_WORD_SIZE);
    localparam int INDEX_W = $clog2(SET);
    localparam int OFFSET_W = BYTE_LSB + WORD_OFFSET_W;
    localparam int TAG_W = ADDR_W - INDEX_W - OFFSET_W;
    localparam int REFILL_CNT_W = $clog2(BLOCK_WORD_SIZE);
    localparam int CACHE_WORDS = SET * BLOCK_WORD_SIZE;
    localparam int CACHE_WORD_ADDR_W = $clog2(CACHE_WORDS);
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;
    localparam logic [REFILL_CNT_W-1:0] LAST_BEAT = BLOCK_WORD_SIZE - 1;

    typedef enum logic [2:0] {
        LOOKUP,
        SEND_AW_W,
        WAIT_B,
        SEND_AR,
        REFILL
    } state_t;

    state_t state;

    logic [DATA_W-1:0] data_way0 [0:CACHE_WORDS-1];
    logic [DATA_W-1:0] data_way1 [0:CACHE_WORDS-1];
    logic [TAG_W-1:0] tag_way0 [0:SET-1];
    logic [TAG_W-1:0] tag_way1 [0:SET-1];
    logic valid_array [0:WAY_COUNT-1][0:SET-1];
    logic lru_array [0:SET-1];

    logic lookup_valid;
    logic [ADDR_W-1:0] lookup_addr;
    logic lookup_write;
    logic [DATA_W-1:0] lookup_wdata;
    logic [STRB_W-1:0] lookup_wstrb;
    logic lookup_hit;
    logic lookup_hit_way;
    logic [INDEX_W-1:0] lookup_index;
    logic [TAG_W-1:0] lookup_tag;
    logic [WORD_OFFSET_W-1:0] lookup_word;
    logic [CACHE_WORD_ADDR_W-1:0] lookup_data_addr;
    logic [DATA_W-1:0] merged_write_data;

    logic response_valid;
    logic [DATA_W-1:0] response_data;
    logic response_error;
    logic response_slot_ready;

    logic [ADDR_W-1:0] write_addr;
    logic [DATA_W-1:0] write_data;
    logic [STRB_W-1:0] write_strb;
    logic write_hit;
    logic write_hit_way;
    logic [INDEX_W-1:0] write_index;
    logic [CACHE_WORD_ADDR_W-1:0] write_data_addr;
    logic [DATA_W-1:0] write_cache_data;
    logic aw_done;
    logic w_done;

    logic [ADDR_W-1:0] miss_line_addr;
    logic [INDEX_W-1:0] miss_index;
    logic [TAG_W-1:0] miss_tag;
    logic [WORD_OFFSET_W-1:0] miss_word;
    logic refill_way;
    logic [REFILL_CNT_W-1:0] refill_count;
    logic refill_failed;
    logic [DATA_W-1:0] refill_response_data;
    logic [CACHE_WORD_ADDR_W-1:0] refill_data_addr;

    logic cpu_request_fire;
    logic load_hit_complete;
    logic load_miss_start;
    logic store_start;
    logic invalidate_fire;
    logic aw_fire;
    logic w_fire;
    logic b_fire;
    logic ar_fire;
    logic r_fire;
    logic current_beat_good;
    logic current_last_good;

    //=============================================================
    //                       Lookup Datapath
    //=============================================================
    assign lookup_index = lookup_addr[OFFSET_W+INDEX_W-1:OFFSET_W];
    assign lookup_tag = lookup_addr[ADDR_W-1:OFFSET_W+INDEX_W];
    assign lookup_word = lookup_addr[OFFSET_W-1:BYTE_LSB];
    assign lookup_data_addr = {lookup_index, lookup_word};

    always_comb begin : HIT_LOOKUP
        lookup_hit = 1'b0;
        lookup_hit_way = 1'b0;

        if(valid_array[0][lookup_index] && (tag_way0[lookup_index] == lookup_tag)) begin
            lookup_hit = 1'b1;
            lookup_hit_way = 1'b0;
        end
        else if(valid_array[1][lookup_index] && (tag_way1[lookup_index] == lookup_tag)) begin
            lookup_hit = 1'b1;
            lookup_hit_way = 1'b1;
        end
    end

    always_comb begin : WRITE_MERGE
        if(lookup_hit_way) merged_write_data = data_way1[lookup_data_addr];
        else merged_write_data = data_way0[lookup_data_addr];

        for(int byte_idx = 0; byte_idx < STRB_W; byte_idx++) begin
            if(lookup_wstrb[byte_idx]) merged_write_data[byte_idx*8 +: 8] = lookup_wdata[byte_idx*8 +: 8];
        end
    end

    //=============================================================
    //                    CPU Ready-Valid Interface
    //=============================================================
    assign response_slot_ready = !response_valid || CPU_RSP_READY;
    assign load_hit_complete = (state == LOOKUP) && lookup_valid &&
                               !lookup_write && lookup_hit && response_slot_ready;
    assign load_miss_start = (state == LOOKUP) && lookup_valid &&
                             !lookup_write && !lookup_hit && response_slot_ready;
    assign store_start = (state == LOOKUP) && lookup_valid && lookup_write &&
                         response_slot_ready;
    assign CPU_REQ_READY = (state == LOOKUP) && !INVALIDATE_VALID &&
                           (!lookup_valid || load_hit_complete);
    assign cpu_request_fire = CPU_REQ_VALID && CPU_REQ_READY;

    assign CPU_RSP_VALID = response_valid;
    assign CPU_RSP_DATA = response_data;
    assign CPU_RSP_ERROR = response_error;

    assign INVALIDATE_READY = (state == LOOKUP) && !lookup_valid &&
                              !response_valid;
    assign invalidate_fire = INVALIDATE_VALID && INVALIDATE_READY;

    //=============================================================
    //                         AXI Channels
    //=============================================================
    assign AW_ID = '0;
    assign AW_ADDR = write_addr;
    assign AW_LEN = 8'd0;
    assign AW_SIZE = BYTE_LSB;
    assign AW_BURST = AXI_BURST_INCR;
    assign AW_LOCK = 1'b0;
    assign AW_CACHE = 4'b0000;
    assign AW_PROT = 3'b000;
    assign AW_QOS = 4'b0000;
    assign AW_VALID = (state == SEND_AW_W) && !aw_done;

    assign W_DATA = write_data;
    assign W_STRB = write_strb;
    assign W_LAST = 1'b1;
    assign W_VALID = (state == SEND_AW_W) && !w_done;
    assign B_READY = (state == WAIT_B);

    assign AR_ID = '0;
    assign AR_ADDR = miss_line_addr;
    assign AR_LEN = BLOCK_WORD_SIZE - 1;
    assign AR_SIZE = BYTE_LSB;
    assign AR_BURST = AXI_BURST_INCR;
    assign AR_LOCK = 1'b0;
    assign AR_CACHE = 4'b0000;
    assign AR_PROT = 3'b000;
    assign AR_QOS = 4'b0000;
    assign AR_VALID = (state == SEND_AR);
    assign R_READY = (state == REFILL);

    assign aw_fire = AW_VALID && AW_READY;
    assign w_fire = W_VALID && W_READY;
    assign b_fire = B_VALID && B_READY;
    assign ar_fire = AR_VALID && AR_READY;
    assign r_fire = R_VALID && R_READY;
    assign current_beat_good = (R_ID == AR_ID) && (R_RESP == AXI_OKAY);
    assign current_last_good = R_LAST == (refill_count == LAST_BEAT);
    assign refill_data_addr = {miss_index, refill_count};

    //=============================================================
    //                         Cache Control
    //=============================================================
    always_ff @(posedge ACLK or negedge ARESETn) begin : CACHE_CONTROL
        if(!ARESETn) begin
            state <= LOOKUP;
            lookup_valid <= 1'b0;
            lookup_addr <= '0;
            lookup_write <= 1'b0;
            lookup_wdata <= '0;
            lookup_wstrb <= '0;
            response_valid <= 1'b0;
            response_data <= '0;
            response_error <= 1'b0;
            write_addr <= '0;
            write_data <= '0;
            write_strb <= '0;
            write_hit <= 1'b0;
            write_hit_way <= 1'b0;
            write_index <= '0;
            write_data_addr <= '0;
            write_cache_data <= '0;
            aw_done <= 1'b0;
            w_done <= 1'b0;
            miss_line_addr <= '0;
            miss_index <= '0;
            miss_tag <= '0;
            miss_word <= '0;
            refill_way <= 1'b0;
            refill_count <= '0;
            refill_failed <= 1'b0;
            refill_response_data <= '0;

            for(int set_idx = 0; set_idx < SET; set_idx++) begin
                valid_array[0][set_idx] <= 1'b0;
                valid_array[1][set_idx] <= 1'b0;
                lru_array[set_idx] <= 1'b0;
            end
        end
        else begin
            if(response_valid && CPU_RSP_READY) response_valid <= 1'b0;

            case(state)
                LOOKUP: begin
                    if(invalidate_fire) begin
                        for(int set_idx = 0; set_idx < SET; set_idx++) begin
                            valid_array[0][set_idx] <= 1'b0;
                            valid_array[1][set_idx] <= 1'b0;
                            lru_array[set_idx] <= 1'b0;
                        end
                    end

                    if(load_hit_complete) begin
                        response_valid <= 1'b1;
                        response_error <= 1'b0;
                        lru_array[lookup_index] <= ~lookup_hit_way;

                        if(lookup_hit_way) response_data <= data_way1[lookup_data_addr];
                        else response_data <= data_way0[lookup_data_addr];

                        if(cpu_request_fire) begin
                            lookup_valid <= 1'b1;
                            lookup_addr <= CPU_REQ_ADDR;
                            lookup_write <= CPU_REQ_WRITE;
                            lookup_wdata <= CPU_REQ_WDATA;
                            lookup_wstrb <= CPU_REQ_WSTRB;
                        end
                        else lookup_valid <= 1'b0;
                    end
                    else if(load_miss_start) begin
                        lookup_valid <= 1'b0;
                        miss_line_addr <= {
                            lookup_addr[ADDR_W-1:OFFSET_W],
                            {OFFSET_W{1'b0}}
                        };
                        miss_index <= lookup_index;
                        miss_tag <= lookup_tag;
                        miss_word <= lookup_word;
                        refill_way <= (!valid_array[0][lookup_index])? 1'b0 :
                                      (!valid_array[1][lookup_index])? 1'b1 :
                                      lru_array[lookup_index];
                        refill_count <= '0;
                        refill_failed <= 1'b0;
                        refill_response_data <= '0;
                        state <= SEND_AR;
                    end
                    else if(store_start) begin
                        lookup_valid <= 1'b0;
                        write_addr <= {
                            lookup_addr[ADDR_W-1:BYTE_LSB],
                            {BYTE_LSB{1'b0}}
                        };
                        write_data <= lookup_wdata;
                        write_strb <= lookup_wstrb;
                        write_hit <= lookup_hit;
                        write_hit_way <= lookup_hit_way;
                        write_index <= lookup_index;
                        write_data_addr <= lookup_data_addr;
                        write_cache_data <= merged_write_data;
                        aw_done <= 1'b0;
                        w_done <= 1'b0;
                        state <= SEND_AW_W;
                    end
                    else if(!lookup_valid && cpu_request_fire) begin
                        lookup_valid <= 1'b1;
                        lookup_addr <= CPU_REQ_ADDR;
                        lookup_write <= CPU_REQ_WRITE;
                        lookup_wdata <= CPU_REQ_WDATA;
                        lookup_wstrb <= CPU_REQ_WSTRB;
                    end
                end

                SEND_AW_W: begin
                    if(aw_fire) aw_done <= 1'b1;
                    if(w_fire) w_done <= 1'b1;

                    if((aw_done || aw_fire) && (w_done || w_fire)) state <= WAIT_B;
                end

                WAIT_B: begin
                    if(b_fire) begin
                        response_valid <= 1'b1;
                        response_data <= '0;
                        response_error <= (B_ID != AW_ID) || (B_RESP != AXI_OKAY);

                        if((B_ID == AW_ID) && (B_RESP == AXI_OKAY) && write_hit) begin
                            if(write_hit_way) data_way1[write_data_addr] <= write_cache_data;
                            else data_way0[write_data_addr] <= write_cache_data;

                            lru_array[write_index] <= ~write_hit_way;
                        end

                        state <= LOOKUP;
                    end
                end

                SEND_AR: begin
                    if(ar_fire) state <= REFILL;
                end

                REFILL: begin
                    if(r_fire) begin
                        if(current_beat_good) begin
                            if(refill_way) data_way1[refill_data_addr] <= R_DATA;
                            else data_way0[refill_data_addr] <= R_DATA;

                            if(refill_count == miss_word) refill_response_data <= R_DATA;
                        end

                        if(!current_beat_good || !current_last_good) refill_failed <= 1'b1;

                        if(R_LAST) begin
                            response_valid <= 1'b1;
                            state <= LOOKUP;

                            if(!refill_failed && current_beat_good && current_last_good) begin
                                response_error <= 1'b0;
                                response_data <= (refill_count == miss_word)?
                                                 R_DATA : refill_response_data;
                                lru_array[miss_index] <= ~refill_way;

                                if(refill_way) begin
                                    tag_way1[miss_index] <= miss_tag;
                                    valid_array[1][miss_index] <= 1'b1;
                                end
                                else begin
                                    tag_way0[miss_index] <= miss_tag;
                                    valid_array[0][miss_index] <= 1'b1;
                                end
                            end
                            else begin
                                response_error <= 1'b1;
                                response_data <= '0;
                            end
                        end
                        else refill_count <= refill_count + 1'b1;
                    end
                end

                default: begin
                    state <= LOOKUP;
                    lookup_valid <= 1'b0;
                    response_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule
