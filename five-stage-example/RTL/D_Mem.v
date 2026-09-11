`include "SYSTEM_DEF.vh"

module D_Mem(
    input clk,
    input Mem_r,
    input Mem_w,
    input [`DATA_MEM_ADDR_WIDTH-1:0] Mem_Addr,
    input [`DATA_MEM_WIDTH-1:0] Mem_W_Data,
    input [3:0] Mem_W_Strb,
    output [`DATA_MEM_WIDTH-1:0] Mem_R_Data
);

    reg [7:0] DataMem [0:`DATA_MEM_SIZE - 1];
    integer i;
    always @(posedge clk) begin
        if(Mem_w) begin
            if(Mem_W_Strb[0]) DataMem[Mem_Addr] <= Mem_W_Data[7:0];
            if(Mem_W_Strb[1]) DataMem[Mem_Addr+1] <= Mem_W_Data[15:8];
            if(Mem_W_Strb[2]) DataMem[Mem_Addr+2] <= Mem_W_Data[23:16];
            if(Mem_W_Strb[3]) DataMem[Mem_Addr+3] <= Mem_W_Data[31:24];
        end
        else; // No write operation
    end

    assign Mem_R_Data = (Mem_r)? {DataMem[Mem_Addr+3],DataMem[Mem_Addr+2],DataMem[Mem_Addr+1],DataMem[Mem_Addr]} : 0;

endmodule