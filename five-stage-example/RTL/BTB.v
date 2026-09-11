`include "SYSTEM_DEF.vh"

module BTB(
    input clk,
    input rst_n,
    input [`BTB_PC_WIDTH - 1:0] PC_Tag,
    output [`PC_WIDTH - 1:0] BTB_PC,
    output BTB_Valid,

    input [`BTB_PC_WIDTH - 1:0] EX_PC_Tag,
    input [`PC_WIDTH - 1:0] Branch_PC,
    input Branch_Taken
);
    integer i;
    // Branch Target Buffer (BTB)
    reg [`PC_WIDTH - 1:0] BTB [0:`BTB_SIZE-1];
    reg Valid [0:`BTB_SIZE-1];

    assign BTB_PC = BTB[PC_Tag];
    assign BTB_Valid = Valid[PC_Tag];

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(i = 0; i < `BTB_SIZE; i = i + 1) begin
                BTB[i] <= 0;
                Valid[i] <= 0;
            end
        end
        else begin
            if(Branch_Taken) begin
                BTB[EX_PC_Tag] <= Branch_PC;
                Valid[EX_PC_Tag] <= 1;
            end
            else;
        end
    end
endmodule