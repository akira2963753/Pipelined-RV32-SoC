`include "SYSTEM_DEF.vh"

module RISCV_CPU_tb ();
    reg clk;
    reg rst_n;

    reg [7:0] InstrMem [0:`INSTR_MEM_SIZE - 1]; 
    reg [7:0] DataMem [0:`DATA_MEM_SIZE - 1];
    integer i;
    integer register_file,dm_file;
    RISCV_CPU test(clk,rst_n);

    initial begin
        clk = 0;
        rst_n = 1;
        @(negedge clk) rst_n = 0;
        @(negedge clk) rst_n = 1;
        #1000 begin
            register_file = $fopen("C:/Users/harry/Desktop/Project/RISCV/Five-Stage-Pipelined-CPU/Testbench/RF.out", "w");
            if (register_file) begin
                $fdisplay(register_file, "// Register File Contents with Index");
                $fdisplay(register_file, "// Format: [Index] Data");
                for (i = 0; i < `GPR_SIZE; i = i + 1) begin
                    $fdisplay(register_file, "[%0d] %h", i, test.Register_File.GPR[i]);
                end
                $fclose(register_file);
                $display("Register File written to RF.out");
            end
            else $display("Failed to open RF.out");

            dm_file = $fopen("C:/Users/harry/Desktop/Project/RISCV/Five-Stage-Pipelined-CPU/Testbench/DM.out", "w");
            if (dm_file) begin
                $fdisplay(dm_file, "// Data Memory Contents with Address");
                $fdisplay(dm_file, "// Format: [Address] Data");
                for (i = 0; i < `DATA_MEM_SIZE; i = i + 1) begin
                    $fdisplay(dm_file, "[%0d] %h", i, test.Data_Memory.DataMem[i]);
                end
                $fclose(dm_file);
                $display("Data Memory written to DM.out");
            end
            else $display("Failed to open DM.out");
        end
        #10 $finish;
    end

    always #5 clk <= ~ clk;

    initial begin : Preprocess
        $readmemh("C:/Users/harry/Desktop/Project/RISCV/Five-Stage-Pipelined-CPU/Testbench/IM.dat", InstrMem);
        $readmemh("C:/Users/harry/Desktop/Project/RISCV/Five-Stage-Pipelined-CPU/Testbench/DM.dat", DataMem);
        for (i = 0; i < `INSTR_MEM_SIZE; i = i + 1) begin
            test.Instruction_Memory.InstrMem[i] = InstrMem[i];
        end

        for (i = 0; i < `DATA_MEM_SIZE; i = i + 1) begin
            test.Data_Memory.DataMem[i] = DataMem[i];
        end
        $display("Initialize the Instr_Mem & Data_Mem");
    end
endmodule