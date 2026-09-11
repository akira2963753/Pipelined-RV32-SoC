`include "SYSTEM_DEF.vh"

module PC(
    input clk,
    input rst_n,
    input [1:0] PC_sel,
    input [`PC_WIDTH-1:0] EX_ALU_Result,
    input [`PC_WIDTH-1:0] PC_Plus_4,
    input [`PC_WIDTH-1:0] BTB_PC,
    input [`PC_WIDTH-1:0] EX_PC_Plus_4,
    output reg [`PC_WIDTH-1:0] IF_PC
    );

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) IF_PC <= 0;
        else begin 
            case(PC_sel) 
                2'd0: IF_PC <= PC_Plus_4;
                2'd1: IF_PC <= BTB_PC;
                2'd2: IF_PC <= EX_PC_Plus_4;
                2'd3: IF_PC <= EX_ALU_Result;
                default:;
            endcase
        end
    end

endmodule