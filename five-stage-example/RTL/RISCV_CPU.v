/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    RISC_CPU.v
* Project:      Five-Stage-Pipelined-RISC-V-CPU Design 
*               (Forwarding/Hazard/Flush/Dynamic Branch Prediction)
* Module:       RISC_CPU
* Author:       Marco <harry2963753@gmail.com>
* Created:      2025/09/30
* Modified:     2026/02/09
* Version:      2.0
* Comment Opt:  Claude Code
*
* Description:
*   This is a Five-Stage-Pipelined-RISC-V-CPU Design, having Forwarding, 
*   Hazard Detection(Flush), Dynamic Branch Prediction and it supports 
*   RV32I & RV32I.
*
* Dependencies:
*   - SYSTEM_DEF.vh
*   - other_module.v
******************************************************************************/

`include "SYSTEM_DEF.vh"

module RISCV_CPU(
    input aclk,
    input aresetn);

    wire    [`PC_WIDTH - 1:0]       IF_PC;
    wire    [`PC_WIDTH - 1:0]       PC_Plus_4;
    wire    [`PC_WIDTH - 1:0]       ID_PC,EX_PC,PC_Plus_Imm;
    wire    IF_ID_w;
    wire    [`INSTR_WIDTH - 1:0]    IF_Instr;
    wire    [`INSTR_WIDTH - 1:0]    ID_Instr;

    wire    [`DATA_WIDTH - 1:0]     ID_Rs1_Data,EX_Rs1_Data;
    wire    [`DATA_WIDTH - 1:0]     ID_Rs2_Data,EX_Rs2_Data;
    wire    [`ADDR_WIDTH - 1:0]     ID_Rs1_Addr,EX_Rs1_Addr;
    wire    [`ADDR_WIDTH - 1:0]     ID_Rs2_Addr,EX_Rs2_Addr;
    wire    [`ADDR_WIDTH - 1:0]     ID_Rd_Addr,EX_Rd_Addr,MEM_Rd_Addr,WB_Rd_Addr;
    wire    [6:0]   ID_Funct7,EX_Funct7;
    wire    [2:0]   ID_Funct3,EX_Funct3,MEM_Funct3;

    wire    Branch_Taken;
    wire    [2:0]   Imm_Type;
    wire    [1:0]   ID_ALU_op,EX_ALU_op;
    wire    [1:0]   ID_WB_sel,EX_WB_sel,MEM_WB_sel,WB_WB_sel;
    wire    ID_Reg_w,EX_Reg_w,WB_Reg_w;
    wire    ID_ALU_src1,EX_ALU_src1;
    wire    ID_ALU_src2,EX_ALU_src2;
    wire    ID_Mem_w,EX_Mem_w,MEM_Mem_w;
    wire    ID_Mem_r,EX_Mem_r,MEM_Mem_r;
    wire    ID_Branch,EX_Branch;
    wire    ID_Jump,EX_Jump;
    wire    [1:0]   PC_sel;
    wire    IF_ID_Flush;
    wire    ID_EX_Flush,ID_EX_Flush_0,ID_EX_Flush_1;

    wire    [`DATA_WIDTH - 1:0]     ID_Imm,EX_Imm,MEM_Imm,WB_Imm;
    wire    [`OPCODE_WIDTH - 1:0]   Opcode;
    wire    [`DATA_WIDTH - 1:0]     Src1_Data,Src2_Data;
    wire    [`DATA_WIDTH - 1:0]     Src1,Src2;
    wire    [`DATA_WIDTH - 1:0]     ALU_Result,EX_ALU_Result,MEM_ALU_Result,WB_ALU_Result;
    wire    [4:0]   ALU_Ctrl_op;
    wire    Zero_Flag;

    wire    [`DATA_WIDTH - 1:0]     EX_PC_Plus_4,MEM_PC_Plus_4,WB_PC_Plus_4;
    wire    [`DATA_WIDTH - 1:0]     EX_Mem_W_Data,MEM_Mem_W_Data;
    wire    [`DATA_WIDTH - 1:0]     Mem_R_Data,MEM_Mem_R_Data,WB_Mem_R_Data;
    wire    [`DATA_WIDTH - 1:0]     WB_Data;
    wire    [1:0]   Forward_A,Forward_B;
    wire    [3:0]   EX_Mem_W_Strb,MEM_Mem_W_Strb;

    wire    ID_CSR_en,EX_CSR_en;
    wire    [`DATA_WIDTH - 1:0]     CSR_R_Data;

    wire    Predict;
    wire    [`PC_WIDTH - 1:0] BTB_PC;
    wire    BTB_Valid;
    wire    Predict_Taken,ID_Predict_Taken,EX_Predict_Taken;

    assign Predict_Taken = Predict && BTB_Valid;

    // Instruction Decode
    assign Opcode = ID_Instr[6:0];
    assign ID_Rs1_Addr = (Opcode == `U_TYPE_LUI) ? 5'b0 : ID_Instr[19:15];
    assign ID_Rs2_Addr = (Opcode == `U_TYPE_LUI) ? 5'b0 : ID_Instr[24:20];
    assign ID_Rd_Addr = ID_Instr[11:7];
    assign ID_Funct7 = ID_Instr[31:25];
    assign ID_Funct3 = ID_Instr[14:12];

    assign EX_Mem_W_Data = Src2_Data;

    // PC MUX
    assign PC_sel = ((Branch_Taken||EX_Jump)&&~EX_Predict_Taken)? 2'd3 :
                    (EX_Predict_Taken&&~(Branch_Taken||EX_Jump))? 2'd2 :  
                    (Predict_Taken)? 2'd1 : 2'd0;

    // PC + 4 
    assign EX_PC_Plus_4 = EX_PC + 4;

    // ALU MUX
    assign Src1_Data = (Forward_A == 2'b00)? EX_Rs1_Data :
                    (Forward_A == 2'b01)? WB_Data : MEM_ALU_Result;

    assign Src1 = (EX_ALU_src1)? EX_PC : Src1_Data; // Fix [Origin EX_PC_Plus_4]

    assign Src2_Data = (Forward_B == 2'b00)? EX_Rs2_Data :
                    (Forward_B == 2'b01)? WB_Data : MEM_ALU_Result;

    assign Src2 = (EX_ALU_src2)? EX_Imm : Src2_Data;

    assign EX_ALU_Result = (EX_Branch)? PC_Plus_Imm : 
                        (EX_CSR_en)? CSR_R_Data : ALU_Result;

    // WB MUX
    assign WB_Data = (WB_WB_sel == 2'b00)? WB_ALU_Result : 
                    (WB_WB_sel == 2'b01)? WB_PC_Plus_4 : 
                    (WB_WB_sel == 2'b10)? WB_Mem_R_Data : WB_Imm;

    assign ID_EX_Flush = ID_EX_Flush_1 || ID_EX_Flush_0;

    PC Program_Counter (
        .clk(aclk),
        .rst_n(aresetn),
        .PC_sel(PC_sel),
        .EX_ALU_Result(EX_ALU_Result),
        .PC_Plus_4(PC_Plus_4),
        .BTB_PC(BTB_PC),
        .EX_PC_Plus_4(EX_PC_Plus_4),
        .IF_PC(IF_PC));

    PC_Adder PC_Adder_inst (
        .IF_ID_w(IF_ID_w),
        .PC_In(IF_PC),
        .PC_Out(PC_Plus_4));

    BHT Branch_History_Table (
        .clk(aclk),
        .rst_n(aresetn),
        .PC_Tag(IF_PC[`BHT_PC_WIDTH - 1:0]),
        .Branch_Taken(Branch_Taken),
        .EX_PC_Tag(EX_PC[`BHT_PC_WIDTH - 1:0]),
        .Predict(Predict));

    BTB Branch_Tag_Buffer (
        .clk(aclk),
        .rst_n(aresetn),
        .PC_Tag(IF_PC[`BHT_PC_WIDTH - 1:0]),
        .BTB_PC(BTB_PC),
        .BTB_Valid(BTB_Valid),
        .EX_PC_Tag(EX_PC[`BHT_PC_WIDTH - 1:0]),
        .Branch_PC(EX_ALU_Result),
        .Branch_Taken(Branch_Taken));

    I_Mem Instruction_Memory (
        .Instr_Addr(IF_PC),
        .Instr(IF_Instr));
    
    IF_ID IF_ID_inst (
        .clk(aclk),
        .rst_n(aresetn),
        .IF_ID_w(IF_ID_w),
        .IF_ID_Flush(IF_ID_Flush),
        .IF_PC(IF_PC),
        .IF_Instr(IF_Instr),
        .IF_Predict_Taken(Predict_Taken),
        .ID_PC(ID_PC),
        .ID_Predict_Taken(ID_Predict_Taken),
        .ID_Instr(ID_Instr));

    RF Register_File(
        .clk(aclk),
        .rst_n(aresetn),
        .Reg_w(WB_Reg_w),
        .Rs1_Addr(ID_Rs1_Addr),
        .Rs2_Addr(ID_Rs2_Addr),
        .Rd_Addr(WB_Rd_Addr),
        .Rd_Data(WB_Data),
        .Rs1_Data(ID_Rs1_Data),
        .Rs2_Data(ID_Rs2_Data));

    Control Control_Unit(
        .Opcode(Opcode),
        .Branch_Taken(Branch_Taken),
        .ID_EX_Jump(EX_Jump),
        .EX_Predict_Taken(EX_Predict_Taken),
        .ID_PC(ID_PC),
        .Branch_PC(EX_ALU_Result),
        .Imm_Type(Imm_Type),
        .ALU_op(ID_ALU_op),
        .WB_sel(ID_WB_sel),
        .Reg_w(ID_Reg_w),
        .ALU_src1(ID_ALU_src1),
        .ALU_src2(ID_ALU_src2),
        .Mem_w(ID_Mem_w),
        .Mem_r(ID_Mem_r),
        .Branch(ID_Branch),
        .Jump(ID_Jump),
        .CSR_en(ID_CSR_en),
        .IF_ID_Flush(IF_ID_Flush),
        .ID_EX_Flush_1(ID_EX_Flush_1));

    ImmGen Immediate_Generator(
        .Instr(ID_Instr),
        .Imm_Type(Imm_Type),
        .Imm(ID_Imm));

    Hazard_Unit Hazard_Unit_inst(
        .Rs1Addr(ID_Rs1_Addr),
        .Rs2Addr(ID_Rs2_Addr),
        .RdAddr(EX_Rd_Addr),
        .EX_Mem_r(EX_Mem_r),
        .IF_ID_w(IF_ID_w),
        .ID_EX_Flush_0(ID_EX_Flush_0));

    ID_EX ID_EX_inst(
        .clk(aclk),
        .rst_n(aresetn),
        .ID_EX_Flush(ID_EX_Flush),
        .ID_ALU_op(ID_ALU_op),
        .ID_ALU_src1(ID_ALU_src1),
        .ID_ALU_src2(ID_ALU_src2),
        .ID_Branch(ID_Branch),
        .ID_Jump(ID_Jump),
        .ID_Mem_r(ID_Mem_r),
        .ID_Mem_w(ID_Mem_w),
        .ID_Reg_w(ID_Reg_w),
        .ID_WB_sel(ID_WB_sel),
        .ID_PC(ID_PC),
        .ID_Rs1_Data(ID_Rs1_Data),
        .ID_Rs2_Data(ID_Rs2_Data),
        .ID_Imm(ID_Imm),
        .ID_Rs1_Addr(ID_Rs1_Addr),
        .ID_Rs2_Addr(ID_Rs2_Addr),
        .ID_Rd_Addr(ID_Rd_Addr),
        .ID_Funct7(ID_Funct7),
        .ID_Funct3(ID_Funct3),
        .ID_CSR_en(ID_CSR_en),
        .ID_Predict_Taken(ID_Predict_Taken),
        .EX_ALU_op(EX_ALU_op),
        .EX_ALU_src1(EX_ALU_src1),
        .EX_ALU_src2(EX_ALU_src2),
        .EX_Branch(EX_Branch),
        .EX_Jump(EX_Jump),
        .EX_Mem_r(EX_Mem_r),
        .EX_Mem_w(EX_Mem_w),
        .EX_Reg_w(EX_Reg_w),
        .EX_WB_sel(EX_WB_sel),
        .EX_PC(EX_PC),
        .EX_Rs1_Data(EX_Rs1_Data),
        .EX_Rs2_Data(EX_Rs2_Data),
        .EX_Imm(EX_Imm),
        .EX_Rs1_Addr(EX_Rs1_Addr),
        .EX_Rs2_Addr(EX_Rs2_Addr),
        .EX_Rd_Addr(EX_Rd_Addr),
        .EX_Funct7(EX_Funct7),
        .EX_Funct3(EX_Funct3),
        .EX_CSR_en(EX_CSR_en),
        .EX_Predict_Taken(EX_Predict_Taken));

    CSR Control_State_Register(
        .clk(aclk),
        .rst_n(aresetn),
        .CSR_en(EX_CSR_en),
        .CSR_Addr(EX_Imm[11:0]),
        .CSR_W_Data(Src1_Data),
        .Funct3(EX_Funct3),
        .CSR_R_Data(CSR_R_Data));

    ALU Arithmetic_Logic_Unit(
        .Src1(Src1),
        .Src2(Src2),
        .ALU_Ctrl_op(ALU_Ctrl_op),
        .ALU_Result(ALU_Result),
        .Zero_Flag(Zero_Flag));

    ALU_Control ALU_Control_Unit(
        .ALU_op(EX_ALU_op),
        .Funct3(EX_Funct3),
        .Funct7(EX_Funct7),
        .Mem_W_Strb(EX_Mem_W_Strb),
        .ALU_Ctrl_op(ALU_Ctrl_op));

    BPU Branch_Processing_Unit(
        .ALU_Result0(ALU_Result[0]),
        .Zero_Flag(Zero_Flag),
        .Funct3(EX_Funct3),
        .EX_Branch(EX_Branch),
        .EX_PC(EX_PC),
        .EX_Imm(EX_Imm),
        .PC_Plus_Imm(PC_Plus_Imm),
        .Branch_Taken(Branch_Taken));


    Forwarding_Unit Forwarding_Unit_inst(
        .MEM_Rd_Addr(MEM_Rd_Addr),
        .MEM_Reg_w(MEM_Reg_w),
        .WB_Rd_Addr(WB_Rd_Addr),
        .WB_Reg_w(WB_Reg_w),
        .EX_Rs1_Addr(EX_Rs1_Addr),
        .EX_Rs2_Addr(EX_Rs2_Addr),
        .Forward_A(Forward_A),
        .Forward_B(Forward_B));

    EX_MEM EX_MEM_inst(
        .clk(aclk),
        .rst_n(aresetn),
        .EX_Mem_r(EX_Mem_r),
        .EX_Mem_w(EX_Mem_w),
        .EX_Reg_w(EX_Reg_w),
        .EX_WB_sel(EX_WB_sel),
        .EX_Imm(EX_Imm),
        .EX_PC_Plus_4(EX_PC_Plus_4),
        .EX_ALU_Result(EX_ALU_Result),
        .EX_Mem_W_Data(EX_Mem_W_Data),
        .EX_Rd_Addr(EX_Rd_Addr),
        .EX_Mem_W_Strb(EX_Mem_W_Strb),
        .EX_Funct3(EX_Funct3),
        .MEM_Mem_r(MEM_Mem_r),
        .MEM_Mem_w(MEM_Mem_w),
        .MEM_Reg_w(MEM_Reg_w),
        .MEM_WB_sel(MEM_WB_sel),
        .MEM_Imm(MEM_Imm),
        .MEM_PC_Plus_4(MEM_PC_Plus_4),
        .MEM_ALU_Result(MEM_ALU_Result),
        .MEM_Mem_W_Data(MEM_Mem_W_Data),
        .MEM_Rd_Addr(MEM_Rd_Addr),
        .MEM_Mem_W_Strb(MEM_Mem_W_Strb),
        .MEM_Funct3(MEM_Funct3));

    D_Mem Data_Memory(
        .clk(aclk),
        .Mem_r(MEM_Mem_r),
        .Mem_w(MEM_Mem_w),
        .Mem_W_Strb(MEM_Mem_W_Strb),
        .Mem_Addr(MEM_ALU_Result),
        .Mem_W_Data(MEM_Mem_W_Data),
        .Mem_R_Data(Mem_R_Data));

    LDU Load_Data_Unit(
        .MEM_Funct3(MEM_Funct3),
        .Mem_R_Data(Mem_R_Data),
        .LDU_Result(MEM_Mem_R_Data));

    MEM_WB MEM_WB_inst(
        .clk(aclk),
        .rst_n(aresetn),
        .MEM_Reg_w(MEM_Reg_w),
        .MEM_WB_sel(MEM_WB_sel),
        .MEM_Imm(MEM_Imm),
        .MEM_PC_Plus_4(MEM_PC_Plus_4),
        .MEM_Mem_R_Data(MEM_Mem_R_Data),
        .MEM_ALU_Result(MEM_ALU_Result),
        .MEM_Rd_Addr(MEM_Rd_Addr),
        .WB_Reg_w(WB_Reg_w),
        .WB_WB_sel(WB_WB_sel),
        .WB_Imm(WB_Imm),
        .WB_PC_Plus_4(WB_PC_Plus_4),
        .WB_Mem_R_Data(WB_Mem_R_Data),
        .WB_ALU_Result(WB_ALU_Result),
        .WB_Rd_Addr(WB_Rd_Addr));

endmodule