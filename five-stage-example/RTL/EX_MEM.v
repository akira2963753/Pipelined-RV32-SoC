`include "SYSTEM_DEF.vh"

module EX_MEM(
    input clk,
    input rst_n,
    // Control Signals Inputs
    input EX_Mem_r,
    input EX_Mem_w,
    input EX_Reg_w,
    input [1:0] EX_WB_sel,
    // Data Inputs
    input [`DATA_WIDTH - 1:0] EX_Imm,
    input [`DATA_WIDTH - 1:0] EX_PC_Plus_4,
    input [`DATA_WIDTH - 1:0] EX_ALU_Result,
    input [`DATA_WIDTH - 1:0] EX_Mem_W_Data,
    input [`ADDR_WIDTH - 1:0] EX_Rd_Addr,
    input [3:0] EX_Mem_W_Strb,
    input [2:0] EX_Funct3,

    // Control Signal Outputs
    output reg MEM_Mem_r,
    output reg MEM_Mem_w,
    output reg MEM_Reg_w,
    output reg [1:0] MEM_WB_sel,
    // Data Outputs
    output reg [`DATA_WIDTH - 1:0] MEM_Imm,
    output reg [`DATA_WIDTH - 1:0] MEM_PC_Plus_4,
    output reg [`DATA_WIDTH - 1:0] MEM_ALU_Result,
    output reg [`DATA_WIDTH - 1:0] MEM_Mem_W_Data,
    output reg [`ADDR_WIDTH - 1:0] MEM_Rd_Addr,
    output reg [3:0] MEM_Mem_W_Strb,
    output reg [2:0] MEM_Funct3
);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            // Reset all outputs
            MEM_Mem_r <= 0;
            MEM_Mem_w <= 0;
            MEM_Reg_w <= 0;
            MEM_WB_sel <= 0;
            MEM_Imm <= 0;
            MEM_PC_Plus_4 <= 0;
            MEM_ALU_Result <= 0;
            MEM_Mem_W_Data <= 0;
            MEM_Rd_Addr <= 0;
            MEM_Mem_W_Strb <= 0;
            MEM_Funct3 <= 0;
        end
        else begin
            // Control Signals
            MEM_Mem_r <= EX_Mem_r;
            MEM_Mem_w <= EX_Mem_w;
            MEM_Reg_w <= EX_Reg_w;
            MEM_WB_sel <= EX_WB_sel;
            MEM_Mem_W_Strb <= EX_Mem_W_Strb;
            MEM_Funct3 <= EX_Funct3;

            // Data
            MEM_Imm <= EX_Imm;
            MEM_PC_Plus_4 <= EX_PC_Plus_4;
            MEM_ALU_Result <= EX_ALU_Result;
            MEM_Mem_W_Data <= EX_Mem_W_Data;
            MEM_Rd_Addr <= EX_Rd_Addr;
        end
    end




endmodule