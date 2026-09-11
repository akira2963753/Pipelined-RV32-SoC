`include "SYSTEM_DEF.vh"

module Forwarding_Unit(
    input [`ADDR_WIDTH - 1:0] MEM_Rd_Addr,
    input MEM_Reg_w,
    input [`ADDR_WIDTH - 1:0] WB_Rd_Addr,
    input WB_Reg_w,
    input [`ADDR_WIDTH - 1:0] EX_Rs1_Addr,
    input [`ADDR_WIDTH - 1:0] EX_Rs2_Addr,
    output reg [1:0] Forward_A,
    output reg [1:0] Forward_B
);

    wire load_EX_MEM = (MEM_Reg_w&&MEM_Rd_Addr!=0);
    wire load_MEM_WB = (WB_Reg_w&&WB_Rd_Addr!=0);

    always @(*) begin
        if(load_EX_MEM && (MEM_Rd_Addr==EX_Rs1_Addr)) Forward_A = 2'b10; // ALU_Result
        else if(load_MEM_WB && (WB_Rd_Addr==EX_Rs1_Addr)) Forward_A = 2'b01; // WB_DATA
        else Forward_A = 2'b00;

        if(load_EX_MEM && (MEM_Rd_Addr==EX_Rs2_Addr)) Forward_B = 2'b10; // ALU_Result
        else if(load_MEM_WB && (WB_Rd_Addr==EX_Rs2_Addr)) Forward_B = 2'b01; // WB_DATA
        else Forward_B = 2'b00;
    end

endmodule