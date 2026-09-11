`include "SYSTEM_DEF.vh"

module RF(
    input clk,
    input rst_n,
    input Reg_w,
    input [`ADDR_WIDTH - 1:0] Rs1_Addr,
    input [`ADDR_WIDTH - 1:0] Rs2_Addr,
    input [`ADDR_WIDTH - 1:0] Rd_Addr,
    input [`DATA_WIDTH - 1:0] Rd_Data,
    output [`DATA_WIDTH - 1:0] Rs1_Data,
    output [`DATA_WIDTH - 1:0] Rs2_Data
);

    reg [`DATA_WIDTH - 1:0] GPR[0:`GPR_SIZE - 1];
    integer i;

    always @(negedge clk or negedge rst_n) begin
        if(!rst_n) for (i = 0; i < `GPR_SIZE; i = i + 1) GPR[i] <= 0;
        else begin
            if(Reg_w && Rd_Addr != 0) GPR[Rd_Addr] <= Rd_Data; 
            else;
        end
    end

    assign Rs1_Data = (Rs1_Addr == 0) ? 32'b0 : GPR[Rs1_Addr];
    assign Rs2_Data = (Rs2_Addr == 0) ? 32'b0 : GPR[Rs2_Addr];

endmodule