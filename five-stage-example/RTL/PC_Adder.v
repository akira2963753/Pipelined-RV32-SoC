`include "SYSTEM_DEF.vh"

module PC_Adder(
    input IF_ID_w,
    input [`PC_WIDTH - 1:0] PC_In,
    output reg [`PC_WIDTH - 1:0] PC_Out
);

    always @(*) begin
        if (IF_ID_w) PC_Out = PC_In + 4;
        else PC_Out = PC_In;
    end

endmodule