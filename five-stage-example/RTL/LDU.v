`include "SYSTEM_DEF.vh"

module LDU(
    input [2:0] MEM_Funct3,
    input [`DATA_WIDTH - 1:0] Mem_R_Data,
    output reg [`DATA_WIDTH - 1:0] LDU_Result
);
    // DPU implementation
    always @(*) begin
        case(MEM_Funct3)
            3'b000 : LDU_Result = {{24{Mem_R_Data[7]}}, Mem_R_Data[7:0]}; // Load Byte
            3'b001 : LDU_Result = {{16{Mem_R_Data[15]}}, Mem_R_Data[15:0]}; // Load Half Word
            3'b010 : LDU_Result = Mem_R_Data;
            3'b100 : LDU_Result = {24'b0, Mem_R_Data[7:0]}; // Load Byte Unsigned
            3'b101 : LDU_Result = {16'b0, Mem_R_Data[15:0]}; // Load Half Word Unsigned
            default : LDU_Result = Mem_R_Data;
        endcase
    end
endmodule