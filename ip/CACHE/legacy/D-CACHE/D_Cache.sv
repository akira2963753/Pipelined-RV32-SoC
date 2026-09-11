/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    D_Cache.sv
* Project:      RISC-V CPU Cache
* Module:       D_Cache
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         Vivado 2025.1
*
* Description:
*   Two-way write-through, no-write-allocate data cache with an AXI4 manager.
*   Read misses use one eight-beat INCR burst. Stores use single-beat writes.
******************************************************************************/

`timescale 1ns/1ps

import AXI4_PKG::*;

module D_Cache #(
    parameter int DATA_W = 32,
    parameter int ADDR_W = 32,
    parameter int ID_W = 4,
    parameter int WAY = 2,
    parameter int SET = 64,
    parameter int BLOCK_WORD_SIZE = 8
) (
    input logic ACLK,
    input logic ARESETn,

    input logic CPU_REQ,
    input logic [ADDR_W-1:0] CPU_REQ_ADDR,
    output logic CPU_REQ_VALID,
    output logic [DATA_W-1:0] CPU_REQ_DATA,

    input logic CPU_WR_EN,
    input logic [DATA_W-1:0] CPU_WR_DATA,
    input logic [DATA_W/8-1:0] CPU_WR_STRB,
    output logic BUSY,

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

    localparam int STRB_W = DATA_W / 8;
    localparam int BYTE_LSB = $clog2(STRB_W);
    localparam int WORD_OFFSET_W = $clog2(BLOCK_WORD_SIZE);
    localparam int INDEX_W = $clog2(SET);
    localparam int OFFSET_W = BYTE_LSB + WORD_OFFSET_W;
    localparam int TAG_W = ADDR_W - INDEX_W - OFFSET_W;
    localparam int WAY_W = $clog2(WAY);
    localparam int REFILL_CNT_W = $clog2(BLOCK_WORD_SIZE);
    localparam int CACHE_WORDS = SET * BLOCK_WORD_SIZE;
    localparam int CACHE_WORD_ADDR_W = $clog2(CACHE_WORDS);
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;

    typedef enum logic [2:0] {
        IDLE,
        LOOKUP,
        SEND_WRITE,
        WRITE_RESPONSE,
        SEND_AR,
        REFILL,
        RESPOND
    } state_t;

    state_t state;
    state_t next_state;

    (* ram_style = "distributed" *)
    logic [DATA_W-1:0] data_way0 [0:CACHE_WORDS-1];
    (* ram_style = "distributed" *)
    logic [DATA_W-1:0] data_way1 [0:CACHE_WORDS-1];
    (* ram_style = "distributed" *)
    logic [TAG_W-1:0] tag_way0 [0:SET-1];
    (* ram_style = "distributed" *)
    logic [TAG_W-1:0] tag_way1 [0:SET-1];
    logic valid_array [0:WAY-1][0:SET-1];
    logic [WAY_W-1:0] lru_array [0:SET-1];

    logic request_is_write;
    logic [ADDR_W-1:0] request_addr;
    logic [DATA_W-1:0] request_write_data;
    logic [STRB_W-1:0] request_write_strb;
    logic [DATA_W-1:0] response_data;

    logic [ADDR_W-1:0] aw_addr_reg;
    logic [DATA_W-1:0] w_data_reg;
    logic [STRB_W-1:0] w_strb_reg;
    logic aw_done;
    logic w_done;

    logic [ADDR_W-1:0] ar_addr_reg;
    logic [WAY_W-1:0] refill_way;
    logic [INDEX_W-1:0] miss_index;
    logic [TAG_W-1:0] miss_tag;
    logic [WORD_OFFSET_W-1:0] miss_word;
    logic [REFILL_CNT_W-1:0] refill_count;
    logic refill_failed;

    logic [INDEX_W-1:0] lookup_index;
    logic [TAG_W-1:0] lookup_tag;
    logic [WORD_OFFSET_W-1:0] lookup_word;
    logic [CACHE_WORD_ADDR_W-1:0] lookup_data_addr;
    logic [CACHE_WORD_ADDR_W-1:0] refill_data_addr;
    logic cache_hit;
    logic [WAY_W-1:0] hit_way;
    logic ar_fire;
    logic r_fire;
    logic aw_fire;
    logic w_fire;
    logic b_fire;
    logic current_read_beat_good;
    logic current_read_last_good;
    logic refill_write;
    logic refill_commit;
    logic write_cache_commit;
    logic [DATA_W-1:0] merged_write_data;

    integer way_idx;
    integer set_idx;
    integer byte_idx;

    assign lookup_index = request_addr[OFFSET_W+INDEX_W-1:OFFSET_W];
    assign lookup_tag = request_addr[ADDR_W-1:OFFSET_W+INDEX_W];
    assign lookup_word = request_addr[OFFSET_W-1:BYTE_LSB];
    assign lookup_data_addr = {lookup_index, lookup_word};
    assign refill_data_addr = {miss_index, refill_count};

    always_comb begin
        cache_hit = 1'b0;
        hit_way = '0;

        if(valid_array[0][lookup_index] &&
           (tag_way0[lookup_index] == lookup_tag)) begin
            cache_hit = 1'b1;
            hit_way = '0;
        end else if(valid_array[1][lookup_index] &&
                    (tag_way1[lookup_index] == lookup_tag)) begin
            cache_hit = 1'b1;
            hit_way = WAY_W'(1);
        end
    end

    always_comb begin
        if(hit_way == '0) merged_write_data = data_way0[lookup_data_addr];
        else              merged_write_data = data_way1[lookup_data_addr];

        for(int byte_pos = 0; byte_pos < STRB_W; byte_pos = byte_pos + 1) begin
            if(request_write_strb[byte_pos])
                merged_write_data[byte_pos*8 +: 8] =
                    request_write_data[byte_pos*8 +: 8];
        end
    end

    assign AW_ID = '0;
    assign AW_ADDR = aw_addr_reg;
    assign AW_LEN = 8'd0;
    assign AW_SIZE = BYTE_LSB;
    assign AW_BURST = AXI_BURST_INCR;
    assign AW_LOCK = 1'b0;
    assign AW_CACHE = 4'b0000;
    assign AW_PROT = 3'b000;
    assign AW_QOS = 4'b0000;
    assign W_DATA = w_data_reg;
    assign W_STRB = w_strb_reg;
    assign W_LAST = 1'b1;

    assign AR_ID = '0;
    assign AR_ADDR = ar_addr_reg;
    assign AR_LEN = BLOCK_WORD_SIZE - 1;
    assign AR_SIZE = BYTE_LSB;
    assign AR_BURST = AXI_BURST_INCR;
    assign AR_LOCK = 1'b0;
    assign AR_CACHE = 4'b0000;
    assign AR_PROT = 3'b000;
    assign AR_QOS = 4'b0000;

    assign CPU_REQ_VALID = (state == RESPOND);
    assign CPU_REQ_DATA = response_data;
    assign BUSY = (state != IDLE) && (state != RESPOND);

    assign aw_fire = AW_VALID && AW_READY;
    assign w_fire = W_VALID && W_READY;
    assign b_fire = B_VALID && B_READY;
    assign ar_fire = AR_VALID && AR_READY;
    assign r_fire = R_VALID && R_READY;

    assign current_read_beat_good = (R_ID == AR_ID) && (R_RESP == AXI_OKAY);
    assign current_read_last_good =
        (refill_count == BLOCK_WORD_SIZE - 1) == R_LAST;
    assign refill_write = (state == REFILL) && r_fire &&
                          current_read_beat_good &&
                          (refill_count < BLOCK_WORD_SIZE);
    assign refill_commit = refill_write && R_LAST && !refill_failed &&
                           current_read_last_good;
    assign write_cache_commit = (state == WRITE_RESPONSE) && b_fire &&
                                (B_ID == AW_ID) && (B_RESP == AXI_OKAY) &&
                                cache_hit;

    always_comb begin
        next_state = state;

        case(state)
            IDLE: begin
                if(CPU_WR_EN || CPU_REQ) next_state = LOOKUP;
            end

            LOOKUP: begin
                if(request_is_write) next_state = SEND_WRITE;
                else if(cache_hit) next_state = RESPOND;
                else next_state = SEND_AR;
            end

            SEND_WRITE: begin
                if((aw_done || aw_fire) && (w_done || w_fire))
                    next_state = WRITE_RESPONSE;
            end

            WRITE_RESPONSE: begin
                if(b_fire) next_state = IDLE;
            end

            SEND_AR: begin
                if(ar_fire) next_state = REFILL;
            end

            REFILL: begin
                if(r_fire && R_LAST) begin
                    if(!refill_failed && current_read_beat_good &&
                       current_read_last_good)
                        next_state = RESPOND;
                    else
                        next_state = IDLE;
                end
            end

            RESPOND: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always_ff @(posedge ACLK) begin
        if(refill_write) begin
            if(refill_way == '0)
                data_way0[refill_data_addr] <= R_DATA;
            else
                data_way1[refill_data_addr] <= R_DATA;
        end else if(write_cache_commit) begin
            if(hit_way == '0)
                data_way0[lookup_data_addr] <= merged_write_data;
            else
                data_way1[lookup_data_addr] <= merged_write_data;
        end

        if(refill_commit) begin
            if(refill_way == '0)
                tag_way0[miss_index] <= miss_tag;
            else
                tag_way1[miss_index] <= miss_tag;
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if(!ARESETn) begin
            state <= IDLE;
            request_is_write <= 1'b0;
            request_addr <= '0;
            request_write_data <= '0;
            request_write_strb <= '0;
            response_data <= '0;
            aw_addr_reg <= '0;
            w_data_reg <= '0;
            w_strb_reg <= '0;
            aw_done <= 1'b0;
            w_done <= 1'b0;
            AW_VALID <= 1'b0;
            W_VALID <= 1'b0;
            B_READY <= 1'b0;
            ar_addr_reg <= '0;
            refill_way <= '0;
            miss_index <= '0;
            miss_tag <= '0;
            miss_word <= '0;
            refill_count <= '0;
            refill_failed <= 1'b0;
            AR_VALID <= 1'b0;
            R_READY <= 1'b0;

            for(set_idx = 0; set_idx < SET; set_idx = set_idx + 1) begin
                lru_array[set_idx] <= '0;

                for(way_idx = 0; way_idx < WAY; way_idx = way_idx + 1)
                    valid_array[way_idx][set_idx] <= 1'b0;
            end
        end else begin
            state <= next_state;

            case(state)
                IDLE: begin
                    AW_VALID <= 1'b0;
                    W_VALID <= 1'b0;
                    B_READY <= 1'b0;
                    AR_VALID <= 1'b0;
                    R_READY <= 1'b0;

                    if(CPU_WR_EN) begin
                        request_is_write <= 1'b1;
                        request_addr <= CPU_REQ_ADDR;
                        request_write_data <= CPU_WR_DATA;
                        request_write_strb <= CPU_WR_STRB;
                    end else if(CPU_REQ) begin
                        request_is_write <= 1'b0;
                        request_addr <= CPU_REQ_ADDR;
                    end
                end

                LOOKUP: begin
                    if(request_is_write) begin
                        aw_addr_reg <= request_addr;
                        w_data_reg <= request_write_data;
                        w_strb_reg <= request_write_strb;
                        aw_done <= 1'b0;
                        w_done <= 1'b0;
                        AW_VALID <= 1'b1;
                        W_VALID <= 1'b1;
                        B_READY <= 1'b1;
                    end else if(cache_hit) begin
                        if(hit_way == '0)
                            response_data <= data_way0[lookup_data_addr];
                        else
                            response_data <= data_way1[lookup_data_addr];

                        lru_array[lookup_index] <= ~hit_way;
                    end else begin
                        if(!valid_array[0][lookup_index]) refill_way <= '0;
                        else if(!valid_array[1][lookup_index]) refill_way <= WAY_W'(1);
                        else refill_way <= lru_array[lookup_index];

                        miss_index <= lookup_index;
                        miss_tag <= lookup_tag;
                        miss_word <= lookup_word;
                        ar_addr_reg <= {
                            request_addr[ADDR_W-1:OFFSET_W],
                            {OFFSET_W{1'b0}}
                        };
                        refill_count <= '0;
                        refill_failed <= 1'b0;
                        AR_VALID <= 1'b1;
                    end
                end

                SEND_WRITE: begin
                    if(aw_fire) begin
                        AW_VALID <= 1'b0;
                        aw_done <= 1'b1;
                    end

                    if(w_fire) begin
                        W_VALID <= 1'b0;
                        w_done <= 1'b1;
                    end
                end

                WRITE_RESPONSE: begin
                    if(b_fire) begin
                        B_READY <= 1'b0;

                        if((B_ID == AW_ID) && (B_RESP == AXI_OKAY) && cache_hit)
                            lru_array[lookup_index] <= ~hit_way;
                    end
                end

                SEND_AR: begin
                    if(ar_fire) begin
                        AR_VALID <= 1'b0;
                        R_READY <= 1'b1;
                    end
                end

                REFILL: begin
                    if(r_fire) begin
                        if(current_read_beat_good &&
                           (refill_count < BLOCK_WORD_SIZE) &&
                           (refill_count == miss_word))
                            response_data <= R_DATA;

                        if(!current_read_beat_good || !current_read_last_good)
                            refill_failed <= 1'b1;

                        if(R_LAST) begin
                            R_READY <= 1'b0;
                            refill_count <= '0;

                            if(!refill_failed && current_read_beat_good &&
                               current_read_last_good) begin
                                valid_array[refill_way][miss_index] <= 1'b1;
                                lru_array[miss_index] <= ~refill_way;
                            end
                        end else begin
                            refill_count <= refill_count + 1'b1;
                        end
                    end
                end

                RESPOND: begin
                    AW_VALID <= 1'b0;
                    W_VALID <= 1'b0;
                    B_READY <= 1'b0;
                    AR_VALID <= 1'b0;
                    R_READY <= 1'b0;
                end

                default: begin
                    AW_VALID <= 1'b0;
                    W_VALID <= 1'b0;
                    B_READY <= 1'b0;
                    AR_VALID <= 1'b0;
                    R_READY <= 1'b0;
                end
            endcase
        end
    end

endmodule
