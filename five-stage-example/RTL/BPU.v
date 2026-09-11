`include "SYSTEM_DEF.vh"

module BPU (
    input ALU_Result0,
    input Zero_Flag,
    input [2:0] Funct3,
    input EX_Branch,
    input [`PC_WIDTH-1:0] EX_PC,
    input [`DATA_WIDTH-1:0] EX_Imm,
    output [`PC_WIDTH-1:0] PC_Plus_Imm,
    output Branch_Taken
);
    reg Taken;
    assign PC_Plus_Imm = EX_PC + EX_Imm;
    assign Branch_Taken = Taken && EX_Branch; // Have Glitch (SOMECASE)

    always @(*) begin
        case(Funct3)
            3'b000: Taken = Zero_Flag;       // BEQ
            3'b001: Taken = !Zero_Flag;      // BNE
            3'b100: Taken = ALU_Result0;     // BLT
            3'b101: Taken = ALU_Result0;     // BGE
            3'b110: Taken = ALU_Result0;     // BLTU
            3'b111: Taken = ALU_Result0;     // BGEU 
            default: Taken = 0;
        endcase
    end

endmodule