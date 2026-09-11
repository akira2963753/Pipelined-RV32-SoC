`include "SYSTEM_DEF.vh"

module MEM_WB(
    input clk,
    input rst_n,
    // Control Signals Inputs
    input MEM_Reg_w,
    input [1:0] MEM_WB_sel,

    // Data Inputs
    input [`DATA_WIDTH - 1:0] MEM_Imm,
    input [`DATA_WIDTH - 1:0] MEM_PC_Plus_4,
    input [`DATA_WIDTH - 1:0] MEM_Mem_R_Data,
    input [`DATA_WIDTH - 1:0] MEM_ALU_Result,
    input [`ADDR_WIDTH - 1:0] MEM_Rd_Addr,

    // Control Signal Outputs
    output reg WB_Reg_w,
    output reg [1:0] WB_WB_sel,

    // Data Outputs
    output reg [`DATA_WIDTH - 1:0] WB_Imm,
    output reg [`DATA_WIDTH - 1:0] WB_PC_Plus_4,
    output reg [`DATA_WIDTH - 1:0] WB_Mem_R_Data,
    output reg [`DATA_WIDTH - 1:0] WB_ALU_Result,
    output reg [`ADDR_WIDTH - 1:0] WB_Rd_Addr
);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            // Control Signals
            WB_Reg_w <= 0;
            WB_WB_sel <= 0;
            WB_Imm <= 0;
            WB_PC_Plus_4 <= 0;
            WB_Mem_R_Data <= 0;
            WB_ALU_Result <= 0;
            WB_Rd_Addr <= 0;
        end
        else begin
            // Control Signals
            WB_Reg_w <= MEM_Reg_w;
            WB_WB_sel <= MEM_WB_sel;

            // Data
            WB_Imm <= MEM_Imm;
            WB_PC_Plus_4 <= MEM_PC_Plus_4;
            WB_Mem_R_Data <= MEM_Mem_R_Data;
            WB_ALU_Result <= MEM_ALU_Result;
            WB_Rd_Addr <= MEM_Rd_Addr;
        end

    end

endmodule