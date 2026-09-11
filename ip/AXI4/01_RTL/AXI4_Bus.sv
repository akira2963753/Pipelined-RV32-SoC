/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    AXI4_Bus.sv
* Project:      RISC-V CPU AXI4 Bus
* Module:       AXI4_Bus
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         Vivado 2025.1
*
* Description:
*   AXI4 slave to single-port synchronous BRAM bridge. The implementation
*   supports one outstanding read burst and one outstanding write burst.
*   Only aligned, full-width INCR bursts are supported.
******************************************************************************/

`timescale 1ns/1ps

import AXI4_PKG::*;

module AXI4_Bus #(
    parameter int DATA_W = 32,
    parameter int ADDR_W = 32,
    parameter int ID_W = 4,
    parameter int BRAM_DEPTH = 1024,
    parameter int BRAM_ADDR_W = $clog2(BRAM_DEPTH)
)(
    input logic ACLK,
    input logic ARESETn,

    // ============================================================================
    //                      Write Address Channel Ports (AW)
    // ============================================================================
    input logic [ID_W-1:0] AW_ID,
    input logic [ADDR_W-1:0] AW_ADDR,
    input logic [7:0] AW_LEN,   // number of beats in a burst + 1
    input logic [2:0] AW_SIZE,  // beat size (bytes)
    input logic [1:0] AW_BURST, // 00:fixed / 01:incr / 10:wrap / 11:reserved
    input logic AW_LOCK,        // Avoid data hazard under the multi-core, fixed 0

    input logic [3:0] AW_CACHE, // {Write-Alloc, Read-Alloc, Modifiable, Bufferable} = 4'b000

    input logic [2:0] AW_PROT,  // {Inst/Data, Secure/-, Privileged/-} = 3'b000
    input logic [3:0] AW_QOS,   // Quality of Service, fixed 4'b0000
    input logic AW_VALID,
    output logic AW_READY,

    // ============================================================================
    //                          Write Data Channel Ports (W)
    // ============================================================================
    input logic [DATA_W-1:0] W_DATA,
    input logic [DATA_W/8-1:0] W_STRB,
    input logic W_LAST, // Indicates the final beat of a burst.
    input logic W_VALID,
    output logic W_READY,

    // ============================================================================
    //                         Write Response Channel Ports (B)
    // ============================================================================
    output logic [ID_W-1:0] B_ID,
    output resp_type B_RESP,
    // 00: OKAY,   normal completion
    // 01: EXOKAY, successful exclusive access
    // 10: SLVERR, subordinate error
    // 11: DECERR, address decode error
    output logic B_VALID,
    input logic B_READY,

    // ============================================================================
    //                          Read Address Channel Ports (AR)
    // ============================================================================
    input logic [ID_W-1:0] AR_ID,
    input logic [ADDR_W-1:0] AR_ADDR,
    input logic [7:0] AR_LEN,
    input logic [2:0] AR_SIZE,
    input logic [1:0] AR_BURST,
    input logic AR_LOCK,
    input logic [3:0] AR_CACHE,
    input logic [2:0] AR_PROT,
    input logic [3:0] AR_QOS,
    input logic AR_VALID,
    output logic AR_READY,

    // ============================================================================
    //                           Read Data Channel Ports (R)
    // ============================================================================
    output logic [ID_W-1:0] R_ID,
    output logic [DATA_W-1:0] R_DATA,
    output resp_type R_RESP,
    output logic R_LAST,
    output logic R_VALID,
    input logic R_READY,

    // ============================================================================
    //                      BRAM Interface Ports (Subordinate)
    // ============================================================================
    output logic BRAM_EN,
    output logic [DATA_W/8-1:0] BRAM_WE,
    output logic [BRAM_ADDR_W-1:0] BRAM_ADDR,
    output logic [DATA_W-1:0] BRAM_DIN,
    input logic [DATA_W-1:0] BRAM_DOUT
);

    localparam int STRB_W = DATA_W / 8;
    localparam int BYTE_OFFSET_W = $clog2(STRB_W);
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;
    localparam logic [ADDR_W:0] MEMORY_BYTES = BRAM_DEPTH * STRB_W;

    // ============================================================================
    //                          Write Controller State Register
    // ============================================================================
    logic write_active; // Indicates that a write burst is in progress.
    logic [ID_W-1:0] write_id;
    logic [ADDR_W-1:0] write_addr;
    logic [7:0] write_len;
    logic [7:0] write_beat;
    logic [2:0] write_size;
    resp_type write_req_resp;

    // ============================================================================
    //                          Read Controller State Register
    // ============================================================================
    logic read_active;  // Indicates that a read burst is in progress.
    logic [ID_W-1:0] read_id;
    logic [ADDR_W-1:0] read_addr;
    logic [7:0] read_len;
    logic [7:0] read_beat;
    logic [2:0] read_size;
    resp_type read_req_resp;

    // ============================================================================
    //                                  Read Pending
    // ============================================================================
    logic read_pending;
    logic [ID_W-1:0] read_pending_id;
    resp_type read_pending_resp;
    logic read_pending_last;

    logic write_fire;
    logic write_expected_last;
    resp_type write_beat_resp;
    resp_type write_last_resp;
    logic read_capture;
    logic read_issue;
    logic read_issue_last;
    resp_type read_issue_resp;

    // ============================================================================
    //                  Function for checking transaction format
    // ============================================================================
    function automatic resp_type request_response(
        input logic [ADDR_W-1:0] address,
        input logic [7:0] length,
        input logic [2:0] size,
        input logic [1:0] burst
    );
        logic [ADDR_W:0] transfer_bytes;
        logic [12:0] boundary_sum;
        begin
            // Calculate the total number of bytes transferred by one burst.
            transfer_bytes = ({1'b0, length} + 1'b1) << size;

            // address[11:0] is the offset within a 4 KB region;
            // the burst must not cross the 4 KB boundary.
            boundary_sum = {1'b0, address[11:0]} + transfer_bytes[12:0];

            if(burst != AXI_BURST_INCR) request_response = AXI_SLVERR; // fixed incr
            else if(size != BYTE_OFFSET_W) request_response = AXI_SLVERR;
            else if(address[BYTE_OFFSET_W-1:0] != '0) request_response = AXI_SLVERR;
            else if(boundary_sum > 13'd4096) request_response = AXI_SLVERR;
            else request_response = AXI_OKAY;
        end
    endfunction

    // ============================================================================
    //                  Function of checking beat address format
    // ============================================================================
    function automatic resp_type beat_response(
        input resp_type request_resp,
        input logic [ADDR_W-1:0] address
    );
        begin
            if(request_resp != AXI_OKAY) beat_response = request_resp;
            else if({1'b0, address} >= MEMORY_BYTES) beat_response = AXI_DECERR; // Address exceeds the BRAM range.
            else beat_response = AXI_OKAY;
        end
    endfunction

    // ============================================================================
    //             Function of merging response (DECERR > SLVERR > OKAY)
    // ============================================================================
    function automatic resp_type merge_response(
        input resp_type accumulated,
        input resp_type current
    );
        begin
            if((accumulated == AXI_DECERR) || (current == AXI_DECERR))  merge_response = AXI_DECERR;
            else if((accumulated == AXI_SLVERR) || (current == AXI_SLVERR)) merge_response = AXI_SLVERR;
            else merge_response = AXI_OKAY;
        end
    endfunction


    // ============================================================================
    //                           Channel description (W)
    // ============================================================================
    // (1) AW channel: describe this transaction such as id, addr, len, size, brust
    // (n) W channel: describe the write data of each beats
    // (1) B channel: response the result of this transaction
    // ============================================================================
    //                              Write Operation Flow
    // ============================================================================
    // (1) Wait for an AW channel handshake and latch the transaction metadata.
    // (2) Wait for W channel handshakes. For each accepted beat, validate it and,
    //     if no error is detected, write its enabled bytes to BRAM.
    //
    //     For each beat, check:
    //       - Does WLAST match the expected final beat?
    //       - Is the current beat address within the BRAM address range?
    //
    //     If this is not the final beat, advance the address and beat counter,
    //     and accumulate the response status.
    //
    // (3) After the expected final W beat, assert BVALID and wait for the
    //     B channel handshake to return the final response to the manager.
    // ============================================================================

    always_comb begin
        AW_READY = !write_active && !B_VALID; // No write transaction or pending response; ready to accept AW.
        W_READY = write_active && !B_VALID; // A write burst is active; ready to accept W beats.
        write_expected_last = (write_beat == write_len);
        write_beat_resp = beat_response(write_req_resp, write_addr);
        write_last_resp = merge_response(write_beat_resp, (W_LAST == write_expected_last) ? AXI_OKAY : AXI_SLVERR);
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if(!ARESETn) begin
            write_active <= 1'b0;
            write_id <= '0;
            write_addr <= '0;
            write_len <= '0;
            write_beat <= '0;
            write_size <= '0;
            write_req_resp <= AXI_OKAY;
            B_ID <= '0;
            B_RESP <= AXI_OKAY;
            B_VALID <= 1'b0;
        end
        else begin
            // Write address channel handshake
            if(AW_VALID && AW_READY) begin
  				write_active <= 1'b1;
                write_id <= AW_ID;
                write_addr <= AW_ADDR;
                write_len <= AW_LEN;
                write_beat <= '0;
                write_size <= AW_SIZE;
                write_req_resp <= request_response(AW_ADDR, AW_LEN, AW_SIZE, AW_BURST);
            end

            // Wrtie channel handshake
            if(W_VALID && W_READY) begin
                write_req_resp <= merge_response(write_req_resp, write_last_resp);
                if(write_expected_last) begin
                    write_active <= 1'b0;
                    B_ID <= write_id;
                    B_RESP <= merge_response(write_req_resp, write_last_resp);
                    B_VALID <= 1'b1;
                end
                else begin
                    write_addr <= write_addr + ({{(ADDR_W-1){1'b0}}, 1'b1} << write_size);
                    write_beat <= write_beat + 1'b1;
                end
            end

            // Write response channel handshake
            if(B_VALID && B_READY) B_VALID <= 1'b0;

        end
    end

    // ============================================================================
    //                           Channel Description (R)
    // ============================================================================
    // (1) AR channel: describes the read transaction
    // (N) R channel : returns one read data beat and its response for each beat.
    //                 RLAST is asserted on the final beat of the burst.
    // ============================================================================
    //                             Read Operation Flow
    // ============================================================================
    // (1) Wait for an AR channel handshake and latch the transaction metadata.
    //
    // (2) For each beat, issue a synchronous BRAM read and save its response
    //     metadata.
    //
    //     For each beat, check:
    //       - Is the current beat address within the BRAM address range?
    //       - Is this the expected final beat of the burst?
    //
    //     If this is not the final beat, advance the address and beat counter.
    //
    // (3) When the BRAM read data is available, assert RVALID and wait for the
    //     R channel handshake to return the data and response to the manager.
    //
    //     If RREADY is low, hold RDATA, RID, RRESP, and RLAST stable until the
    //     manager accepts the current beat.
    // ============================================================================

    always_comb begin
        AR_READY = !read_active && !read_pending && !R_VALID;

        // Determines whether pending BRAM read data can be transferred to the R channel this cycle.
        read_capture = read_pending && (!R_VALID || R_READY);

        // Determines whether the next read beat can be issued to BRAM this cycle.
        // - read_active: a read burst is in progress.
        // - (!read_pending || read_capture): the pending-data slot can advance.
        // - (!R_VALID || R_READY): the R channel can advance.
        // - !(W_VALID && W_READY): no write handshake is using the single-port BRAM.
        read_issue = read_active && (!read_pending || read_capture) &&
                     (!R_VALID || R_READY) && !(W_VALID && W_READY);
        read_issue_resp = beat_response(read_req_resp, read_addr);
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if(!ARESETn) begin
            read_active <= 1'b0;
            read_id <= '0;
            read_addr <= '0;
            read_len <= '0;
            read_beat <= '0;
            read_size <= '0;
            read_req_resp <= AXI_OKAY;
            read_pending <= 1'b0;
            read_pending_id <= '0;
            read_pending_resp <= AXI_OKAY;
            read_pending_last <= 1'b0;
            R_ID <= '0;
            R_DATA <= '0;
            R_RESP <= AXI_OKAY;
            R_LAST <= 1'b0;
            R_VALID <= 1'b0;
        end
        else begin

            // Read channel handshake
            if(R_VALID && R_READY) begin
                R_VALID <= 1'b0;
                R_LAST <= 1'b0;
            end

            // Read address channel handshake
            if(AR_VALID && AR_READY) begin
                read_active <= 1'b1;
                read_id <= AR_ID;
                read_addr <= AR_ADDR;
                read_len <= AR_LEN;
                read_beat <= '0;
                read_size <= AR_SIZE;
                read_req_resp <= request_response(AR_ADDR, AR_LEN, AR_SIZE, AR_BURST);
            end

            // Transfer the pending BRAM read data to the R channel and assert RVALID.
            if(read_capture) begin
                R_ID <= read_pending_id;
                R_DATA <= (read_pending_resp == AXI_OKAY) ? BRAM_DOUT : '0;
                R_RESP <= read_pending_resp;
                R_LAST <= read_pending_last;
                R_VALID <= 1'b1;
            end

            // Issue a BRAM read and save the metadata required for the corresponding R beat.
            if(read_issue) begin
                read_pending <= 1'b1;
                read_pending_id <= read_id;
                read_pending_resp <= read_issue_resp;
                read_pending_last <= (read_beat == read_len);

                if(read_beat == read_len) begin // the last read data
                    read_active <= 1'b0;
                end
                else begin
                    read_addr <= read_addr + ({{(ADDR_W-1){1'b0}}, 1'b1} << read_size);
                    read_beat <= read_beat + 1'b1;
                end
            end
            else if(read_capture) begin
                read_pending <= 1'b0;
            end
        end
    end

    // ============================================================================
    //                              BRAM Controller
    // ============================================================================
    always_comb begin
        BRAM_EN = 1'b0;
        BRAM_WE = '0;
        BRAM_ADDR = '0;
        BRAM_DIN = '0;

        if(W_VALID && W_READY) begin // W channel handshake completed.
            BRAM_EN = (write_beat_resp == AXI_OKAY) && (|W_STRB);
            BRAM_WE = (write_beat_resp == AXI_OKAY) ? W_STRB : '0;
            BRAM_ADDR = write_addr[BRAM_ADDR_W+BYTE_OFFSET_W-1:BYTE_OFFSET_W]; // Convert the AXI byte address to a BRAM word address.
            BRAM_DIN = W_DATA;
        end
        else if(read_issue) begin
            BRAM_EN = (read_issue_resp == AXI_OKAY);
            BRAM_ADDR = read_addr[BRAM_ADDR_W+BYTE_OFFSET_W-1:BYTE_OFFSET_W];
        end
    end

endmodule
