`include "SYSTEM_DEF.vh"

module ID_EX(
    input clk,
    input rst_n,
    input ID_EX_Flush,
    // Control Signals Inputs
    input [1:0] ID_ALU_op,
    input ID_ALU_src1,
    input ID_ALU_src2,
    input ID_Branch,
    input ID_Jump,
    input ID_Mem_r,
    input ID_Mem_w,
    input ID_Reg_w,
    input [1:0] ID_WB_sel,

    // Data Inputs
    input [`DATA_WIDTH - 1:0] ID_PC,
    input [`DATA_WIDTH - 1:0] ID_Rs1_Data,
    input [`DATA_WIDTH - 1:0] ID_Rs2_Data,
    input [`DATA_WIDTH - 1:0] ID_Imm,
    input [`ADDR_WIDTH - 1:0] ID_Rs1_Addr,
    input [`ADDR_WIDTH - 1:0] ID_Rs2_Addr,
    input [`ADDR_WIDTH - 1:0] ID_Rd_Addr,
    input [6:0] ID_Funct7,
    input [2:0] ID_Funct3,
    input ID_CSR_en,
    input ID_Predict_Taken,

    // Control Signal Outputs
    output reg [1:0] EX_ALU_op,
    output reg EX_ALU_src1,
    output reg EX_ALU_src2,
    output reg EX_Branch,
    output reg EX_Jump,
    output reg EX_Mem_r,
    output reg EX_Mem_w,
    output reg EX_Reg_w,
    output reg [1:0] EX_WB_sel,

    // Data Outputs
    output reg [`DATA_WIDTH - 1:0] EX_PC,
    output reg [`DATA_WIDTH - 1:0] EX_Rs1_Data,
    output reg [`DATA_WIDTH - 1:0] EX_Rs2_Data,
    output reg [`DATA_WIDTH - 1:0] EX_Imm,
    output reg [`ADDR_WIDTH - 1:0] EX_Rs1_Addr,
    output reg [`ADDR_WIDTH - 1:0] EX_Rs2_Addr,
    output reg [`ADDR_WIDTH - 1:0] EX_Rd_Addr,
    output reg [6:0] EX_Funct7,
    output reg [2:0] EX_Funct3,
    output reg EX_CSR_en,
    output reg EX_Predict_Taken
);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            EX_ALU_op <= 0;
            EX_ALU_src1 <= 0;
            EX_ALU_src2 <= 0;
            EX_Branch <= 0;
            EX_Jump <= 0;
            EX_Mem_r <= 0;
            EX_Mem_w <= 0;
            EX_Reg_w <= 0;
            EX_WB_sel <= 0;
            EX_PC <= 0;
            EX_Rs1_Data <= 0;
            EX_Rs2_Data <= 0;
            EX_Imm <= 0;
            EX_Rs1_Addr <= 0;
            EX_Rs2_Addr <= 0;
            EX_Rd_Addr <= 0;
            EX_Funct7 <= 0;
            EX_Funct3 <= 0;
            EX_CSR_en <= 0;
            EX_Predict_Taken <= 0;
        end
        else begin
            // Control Signals
            EX_ALU_op <= (ID_EX_Flush)? 0 : ID_ALU_op;
            EX_ALU_src1 <= (ID_EX_Flush)? 0 : ID_ALU_src1;
            EX_ALU_src2 <= (ID_EX_Flush)? 0 : ID_ALU_src2;
            EX_Branch <= (ID_EX_Flush)? 0 : ID_Branch;
            EX_Jump <= (ID_EX_Flush)? 0 : ID_Jump;
            EX_Mem_r <= (ID_EX_Flush)? 0 : ID_Mem_r;
            EX_Mem_w <= (ID_EX_Flush)? 0 : ID_Mem_w;
            EX_Reg_w <= (ID_EX_Flush)? 0 : ID_Reg_w;
            EX_WB_sel <= (ID_EX_Flush)? 0 : ID_WB_sel;
            EX_CSR_en <= (ID_EX_Flush)? 0 : ID_CSR_en;

            // Data
            EX_PC <= ID_PC;
            EX_Rs1_Data <= ID_Rs1_Data;
            EX_Rs2_Data <= ID_Rs2_Data;
            EX_Imm <= ID_Imm;
            EX_Rs1_Addr <= ID_Rs1_Addr;
            EX_Rs2_Addr <= ID_Rs2_Addr;
            EX_Rd_Addr <= ID_Rd_Addr;
            EX_Funct7 <= ID_Funct7;
            EX_Funct3 <= ID_Funct3;
            EX_Predict_Taken <= ID_Predict_Taken;
        end
    end
endmodule