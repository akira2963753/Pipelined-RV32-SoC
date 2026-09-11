`include "SYSTEM_DEF.vh"

module I_Mem (
    input [`INSTR_ADDR_WIDTH - 1:0] Instr_Addr,
    output reg [`INSTR_WIDTH - 1:0] Instr
);
    reg [7:0] InstrMem [0:`INSTR_MEM_SIZE - 1]; 

    always @(*) begin
        Instr = {InstrMem[Instr_Addr], InstrMem[Instr_Addr+1], InstrMem[Instr_Addr+2], InstrMem[Instr_Addr+3]};  
    end

endmodule