`include "SYSTEM_DEF.vh"

module Hazard_Unit(
    input [`ADDR_WIDTH - 1:0] Rs1Addr,
    input [`ADDR_WIDTH - 1:0] Rs2Addr,
    input [`ADDR_WIDTH - 1:0] RdAddr,
    input EX_Mem_r,
    output reg IF_ID_w = 1,
    output reg ID_EX_Flush_0
);

    always @(*) begin
        if(EX_Mem_r&&((RdAddr==Rs1Addr)||(RdAddr==Rs2Addr))) begin
            IF_ID_w = 1'b0;
            ID_EX_Flush_0 = 1'b1;
        end 
        else begin
            IF_ID_w = 1'b1;
            ID_EX_Flush_0 = 1'b0;
        end
    end

endmodule