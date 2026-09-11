`include "SYSTEM_DEF.vh"

module ALU(
    input [31:0] Src1,
    input [31:0] Src2,
    input [4:0] ALU_Ctrl_op,
    output reg [31:0] ALU_Result,
    output Zero_Flag
);
    wire signed [31:0] Src1_Signed,Src2_Signed;
    reg signed [63:0] Mul_Result;
    assign Src1_Signed = Src1;
    assign Src2_Signed = Src2;
    assign Zero_Flag = (ALU_Result==0);

    always @(*) begin
        case(ALU_Ctrl_op)
            `ALU_CTRL_ADD   : ALU_Result = Src1 + Src2;
            `ALU_CTRL_SUB   : ALU_Result = Src1 - Src2;
            `ALU_CTRL_SLT   : ALU_Result = (Src1_Signed < Src2_Signed);
            `ALU_CTRL_SLTU  : ALU_Result = (Src1 < Src2);
            `ALU_CTRL_GE    : ALU_Result = (Src1_Signed >= Src2_Signed);
            `ALU_CTRL_GEU   : ALU_Result = (Src1 >= Src2);
            `ALU_CTRL_AND   : ALU_Result = Src1 & Src2;
            `ALU_CTRL_OR    : ALU_Result = Src1 | Src2;
            `ALU_CTRL_XOR   : ALU_Result = Src1 ^ Src2;
            `ALU_CTRL_SLL   : ALU_Result = Src1 << Src2[4:0];
            `ALU_CTRL_SRL   : ALU_Result = Src1 >> Src2[4:0];
            `ALU_CTRL_SRA   : ALU_Result = Src1_Signed >>> Src2[4:0];
            `ALU_CTRL_MUL   : begin
                Mul_Result = Src1_Signed * Src2_Signed;
                ALU_Result = Mul_Result[31:0];
            end
            `ALU_CTRL_DIV   : ALU_Result = Src1_Signed / Src2_Signed;
            `ALU_CTRL_REM   : ALU_Result = Src1_Signed % Src2_Signed;
            `ALU_CTRL_MULH  : begin
                Mul_Result = Src1_Signed * Src2_Signed;
                ALU_Result = Mul_Result[63:32];                
            end
            `ALU_CTRL_MULHSU: begin
                // MULHSU: signed × unsigned 注意這裡無號數 x 有號數要加上 $sigend 然後做 Sign extend
                Mul_Result = Src1_Signed * $signed({1'b0, Src2});
                ALU_Result = Mul_Result[63:32];
            end
            `ALU_CTRL_MULHU : begin
                Mul_Result = Src1 * Src2;
                ALU_Result = Mul_Result[63:32];                  
            end
            `ALU_CTRL_DIVU  : ALU_Result = Src1 / Src2;
            `ALU_CTRL_REMU  : ALU_Result = Src1 % Src2;            
        endcase
    end
endmodule