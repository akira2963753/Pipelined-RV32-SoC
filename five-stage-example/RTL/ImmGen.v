`include "SYSTEM_DEF.vh"

module ImmGen(
    input [`INSTR_WIDTH - 1:0] Instr,
    input [2:0] Imm_Type,
    output reg [`DATA_WIDTH - 1:0] Imm
);
    
    always @(*) begin
        case (Imm_Type)
            `I_TYPE_IMM : Imm = {{20{Instr[31]}},Instr[31:20]};
            `S_TYPE_IMM : Imm = {{20{Instr[31]}},Instr[31:25],Instr[11:7]};
            `B_TYPE_IMM : Imm = {{19{Instr[31]}},Instr[31],Instr[7],Instr[30:25],Instr[11:8],1'b0};
            `U_TYPE_IMM : Imm = {Instr[31:12],12'b0};
            `J_TYPE_IMM : Imm = {{11{Instr[31]}},Instr[31],Instr[19:12],Instr[20],Instr[30:21],1'b0};
            default : Imm = 0;
        endcase
    end

endmodule