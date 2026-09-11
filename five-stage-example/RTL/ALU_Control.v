`include "SYSTEM_DEF.vh"

module ALU_Control(
    input [1:0] ALU_op,
    input [2:0] Funct3,
    input [6:0] Funct7,
    output reg [3:0] Mem_W_Strb,
    output reg [4:0] ALU_Ctrl_op
);
    always @(*) begin
        case(ALU_op)
            `ALU_OP_ADD : begin
                ALU_Ctrl_op = `ALU_CTRL_ADD;
                case(Funct3) // S-Type
                    3'b000: Mem_W_Strb = 4'b0001; // Byte
                    3'b001: Mem_W_Strb = 4'b0011; // Halfword
                    3'b010: Mem_W_Strb = 4'b1111; // Word
                    default: Mem_W_Strb = 4'b0000; // No write
                endcase
            end
            `ALU_OP_BRANCH : begin
                case(Funct3)
                    3'b000: ALU_Ctrl_op = `ALU_CTRL_SUB;  
                    3'b001: ALU_Ctrl_op = `ALU_CTRL_SUB;   
                    3'b100: ALU_Ctrl_op = `ALU_CTRL_SLT; 
                    3'b101: ALU_Ctrl_op = `ALU_CTRL_GE;    
                    3'b110: ALU_Ctrl_op = `ALU_CTRL_SLTU; 
                    3'b111: ALU_Ctrl_op = `ALU_CTRL_GEU;                     
                    default : ALU_Ctrl_op = `ALU_CTRL_SUB;
                endcase
            end
            `ALU_OP_R_TYPE : begin
                case({Funct7,Funct3})
                    {7'b0000000,3'b000}: ALU_Ctrl_op = `ALU_CTRL_ADD;
                    {7'b0100000,3'b000}: ALU_Ctrl_op = `ALU_CTRL_SUB;  
                    {7'b0000000,3'b001}: ALU_Ctrl_op = `ALU_CTRL_SLL;  
                    {7'b0000000,3'b010}: ALU_Ctrl_op = `ALU_CTRL_SLT; 
                    {7'b0000000,3'b011}: ALU_Ctrl_op = `ALU_CTRL_SLTU;  
                    {7'b0000000,3'b100}: ALU_Ctrl_op = `ALU_CTRL_XOR;   
                    {7'b0000000,3'b101}: ALU_Ctrl_op = `ALU_CTRL_SRL;   
                    {7'b0100000,3'b101}: ALU_Ctrl_op = `ALU_CTRL_SRA;   
                    {7'b0000000,3'b110}: ALU_Ctrl_op = `ALU_CTRL_OR;    
                    {7'b0000000,3'b111}: ALU_Ctrl_op = `ALU_CTRL_AND;
                    // RV32M Extension
                    {7'b0000001,3'b000}: ALU_Ctrl_op = `ALU_CTRL_MUL;
                    {7'b0000001,3'b001}: ALU_Ctrl_op = `ALU_CTRL_MULH;
                    {7'b0000001,3'b010}: ALU_Ctrl_op = `ALU_CTRL_MULHSU;
                    {7'b0000001,3'b011}: ALU_Ctrl_op = `ALU_CTRL_MULHU;
                    {7'b0000001,3'b100}: ALU_Ctrl_op = `ALU_CTRL_DIV;
                    {7'b0000001,3'b101}: ALU_Ctrl_op = `ALU_CTRL_DIVU;
                    {7'b0000001,3'b110}: ALU_Ctrl_op = `ALU_CTRL_REM;
                    {7'b0000001,3'b111}: ALU_Ctrl_op = `ALU_CTRL_REMU;
                    default: ALU_Ctrl_op = `ALU_CTRL_ADD;                    
                endcase
            end
            `ALU_OP_I_TYPE : begin
                case (Funct3)
                    3'b000: ALU_Ctrl_op = `ALU_CTRL_ADD;     
                    3'b010: ALU_Ctrl_op = `ALU_CTRL_SLT;    
                    3'b011: ALU_Ctrl_op = `ALU_CTRL_SLTU;    
                    3'b100: ALU_Ctrl_op = `ALU_CTRL_XOR;          
                    3'b110: ALU_Ctrl_op = `ALU_CTRL_OR;      
                    3'b111: ALU_Ctrl_op = `ALU_CTRL_AND;          
                    3'b001: ALU_Ctrl_op = `ALU_CTRL_SLL;           
                    3'b101: ALU_Ctrl_op = (Funct7 == 7'b0000000)? `ALU_CTRL_SRL : `ALU_CTRL_SRA; 
                    default: ALU_Ctrl_op = `ALU_CTRL_ADD;
                endcase                
            end
        endcase
    end
endmodule