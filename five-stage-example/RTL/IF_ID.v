`include "SYSTEM_DEF.vh"

module IF_ID(
    input clk,
    input rst_n,
    input IF_ID_w,
    input IF_ID_Flush,
    input [`PC_WIDTH - 1:0] IF_PC,
    input [`INSTR_WIDTH - 1:0] IF_Instr,
    input IF_Predict_Taken,
    output reg [`PC_WIDTH - 1:0] ID_PC,
    output reg [`INSTR_WIDTH - 1:0] ID_Instr,
    output reg ID_Predict_Taken
);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ID_PC <= 0;
            ID_Instr <= `NOP;
            ID_Predict_Taken <= 0;
        end
        else begin
            if (IF_ID_w) begin
                ID_PC <= (IF_ID_Flush)? 0 : IF_PC;
                ID_Instr <= (IF_ID_Flush)? `NOP : IF_Instr;
                ID_Predict_Taken <= IF_Predict_Taken;
            end
            else begin
                ID_PC <= ID_PC;
                ID_Instr <= ID_Instr;
                ID_Predict_Taken <= ID_Predict_Taken;
            end
        end
    end

endmodule