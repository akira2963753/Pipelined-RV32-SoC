`include "SYSTEM_DEF.vh"

module CSR (
    input clk,
    input rst_n,
    input CSR_en,             
    input [11:0] CSR_Addr,         
    input [`DATA_WIDTH - 1:0] CSR_W_Data,      
    input [2:0] Funct3,             
    output reg [`DATA_WIDTH - 1:0] CSR_R_Data    
);

    // CSR Address Definition
    parameter CSR_MSTATUS = 12'h300;
    parameter CSR_MTVEC   = 12'h305;
    parameter CSR_MEPC    = 12'h341;
    parameter CSR_MCAUSE  = 12'h342;
    parameter CSR_RDCYCLE = 12'hc00;

    // Constrol State Register
    reg [31:0] mstatus;
    reg [31:0] mtvec;
    reg [31:0] mepc;
    reg [31:0] mcause;
    reg [31:0] rdcycle;

    // CSR Read
    always @(*) begin
        case (CSR_Addr)
            CSR_MSTATUS: CSR_R_Data = mstatus;
            CSR_MTVEC:   CSR_R_Data = mtvec;
            CSR_MEPC:    CSR_R_Data = mepc;
            CSR_MCAUSE:  CSR_R_Data = mcause;
            CSR_RDCYCLE: CSR_R_Data = rdcycle;
            default:     CSR_R_Data = 32'h0;
        endcase
    end

    // CSR Write
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus <= 32'h0;
            mtvec   <= 32'h0;
            mepc    <= 32'h0;
            mcause  <= 32'h0;
            rdcycle <= 32'h0;
        end
        else if (CSR_en) begin
            case (CSR_Addr)
                CSR_MSTATUS: begin
                    case (Funct3[1:0])
                        2'b01: mstatus <= CSR_W_Data;              // CSRRW
                        2'b10: mstatus <= mstatus | CSR_W_Data;    // CSRRS
                        2'b11: mstatus <= mstatus & ~CSR_W_Data;   // CSRRC
                    endcase
                end
                CSR_MTVEC: begin
                    case (Funct3[1:0])
                        2'b01: mtvec <= CSR_W_Data;
                        2'b10: mtvec <= mtvec | CSR_W_Data;
                        2'b11: mtvec <= mtvec & ~CSR_W_Data;
                    endcase
                end
                CSR_MEPC: begin
                    case (Funct3[1:0])
                        2'b01: mepc <= CSR_W_Data;
                        2'b10: mepc <= mepc | CSR_W_Data;
                        2'b11: mepc <= mepc & ~CSR_W_Data;
                    endcase
                end
                CSR_MCAUSE: begin
                    case (Funct3[1:0])
                        2'b01: mcause <= CSR_W_Data;
                        2'b10: mcause <= mcause | CSR_W_Data;
                        2'b11: mcause <= mcause & ~CSR_W_Data;
                    endcase
                end
                CSR_RDCYCLE: begin
                    rdcycle <= CSR_W_Data;
                end
                default: ;
            endcase
            rdcycle <= rdcycle + 1; // clk ++
        end
        else rdcycle <= rdcycle + 1; // clk ++
    end

endmodule