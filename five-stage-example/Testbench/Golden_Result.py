#!/usr/bin/env python3
"""
RISC-V RV32I + RV32M Golden Reference Generator
簡易模擬器，用於產生 RF.golden 和 DM.golden 檔案
支援 RV32I 基本指令集 + RV32M 乘除法擴展 (MUL, DIV, REM)
"""

# 全域變數
instruction_memory = bytearray(256)  # 256 bytes
data_memory = bytearray(32)          # 32 bytes
registers = [0] * 32                 # x0-x31
pc = 0

# ============================================================================
# 檔案載入函式
# ============================================================================

def load_im(filename='IM.dat'):
    """讀取指令記憶體（大端序）"""
    global instruction_memory
    idx = 0
    with open(filename, 'r', encoding='latin-1') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('//'):
                continue
            try:
                instruction_memory[idx] = int(line, 16)
                idx += 1
            except (ValueError, IndexError):
                continue

def load_dm(filename='DM.dat'):
    """讀取資料記憶體（小端序）"""
    global data_memory
    idx = 0
    with open(filename, 'r', encoding='latin-1') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('//'):
                continue
            try:
                data_memory[idx] = int(line, 16)
                idx += 1
            except (ValueError, IndexError):
                continue

# ============================================================================
# 輔助函式
# ============================================================================

def sign_extend(val, bits):
    """符號擴展"""
    sign_bit = 1 << (bits - 1)
    if val & sign_bit:
        return val | (~((1 << bits) - 1) & 0xFFFFFFFF)
    return val

def to_signed(val):
    """32-bit 無符號轉有符號"""
    if val & 0x80000000:
        return val - 0x100000000
    return val

# ============================================================================
# 指令 Fetch & Decode
# ============================================================================

def fetch():
    """從 PC 讀取 32-bit 指令（大端序）"""
    global pc
    return (
        (instruction_memory[pc] << 24) |
        (instruction_memory[pc+1] << 16) |
        (instruction_memory[pc+2] << 8) |
        instruction_memory[pc+3]
    )

def extract_imm(inst, opcode):
    """根據 opcode 提取立即數"""
    if opcode in [0x13, 0x03, 0x67, 0x73]:  # I-Type
        imm = (inst >> 20) & 0xFFF
        return sign_extend(imm, 12)

    elif opcode == 0x23:  # S-Type
        imm = (((inst >> 25) & 0x7F) << 5) | ((inst >> 7) & 0x1F)
        return sign_extend(imm, 12)

    elif opcode == 0x63:  # B-Type
        imm = (
            (((inst >> 31) & 1) << 12) |
            (((inst >> 7) & 1) << 11) |
            (((inst >> 25) & 0x3F) << 5) |
            (((inst >> 8) & 0xF) << 1)
        )
        return sign_extend(imm, 13)

    elif opcode in [0x37, 0x17]:  # U-Type
        return inst & 0xFFFFF000

    elif opcode == 0x6F:  # J-Type
        imm = (
            (((inst >> 31) & 1) << 20) |
            (((inst >> 12) & 0xFF) << 12) |
            (((inst >> 20) & 1) << 11) |
            (((inst >> 21) & 0x3FF) << 1)
        )
        return sign_extend(imm, 21)

    return 0

def decode(inst):
    """解碼 32-bit 指令"""
    opcode = inst & 0x7F
    rd = (inst >> 7) & 0x1F
    funct3 = (inst >> 12) & 0x7
    rs1 = (inst >> 15) & 0x1F
    rs2 = (inst >> 20) & 0x1F
    funct7 = (inst >> 25) & 0x7F
    imm = extract_imm(inst, opcode)

    return {
        'opcode': opcode,
        'rd': rd,
        'rs1': rs1,
        'rs2': rs2,
        'funct3': funct3,
        'funct7': funct7,
        'imm': imm,
        'raw': inst
    }

# ============================================================================
# 指令執行函式
# ============================================================================

def execute_r_type(d):
    """執行 R-Type 指令"""
    global pc, registers
    rs1_val = registers[d['rs1']]
    rs2_val = registers[d['rs2']]
    funct3 = d['funct3']
    funct7 = d['funct7']
    result = 0

    if funct3 == 0b000:  # ADD/SUB/MUL
        if funct7 == 0x20:
            result = (rs1_val - rs2_val) & 0xFFFFFFFF  # SUB
        elif funct7 == 0x01:
            # MUL - 取低 32 位
            product = to_signed(rs1_val) * to_signed(rs2_val)
            result = product & 0xFFFFFFFF
        else:
            result = (rs1_val + rs2_val) & 0xFFFFFFFF  # ADD
    elif funct3 == 0b001:  # SLL/MULH
        if funct7 == 0x01:
            # MULH - 有號×有號，取高 32 位
            product = to_signed(rs1_val) * to_signed(rs2_val)
            result = (product >> 32) & 0xFFFFFFFF
        else:
            result = (rs1_val << (rs2_val & 0x1F)) & 0xFFFFFFFF  # SLL
    elif funct3 == 0b010:  # SLT/MULHSU
        if funct7 == 0x01:
            # MULHSU - 有號×無號，取高 32 位
            product = to_signed(rs1_val) * rs2_val  # rs1 有號，rs2 無號
            result = (product >> 32) & 0xFFFFFFFF
        else:
            result = 1 if to_signed(rs1_val) < to_signed(rs2_val) else 0  # SLT
    elif funct3 == 0b011:  # SLTU/MULHU
        if funct7 == 0x01:
            # MULHU - 無號×無號，取高 32 位
            product = rs1_val * rs2_val
            result = (product >> 32) & 0xFFFFFFFF
        else:
            result = 1 if rs1_val < rs2_val else 0  # SLTU
    elif funct3 == 0b100:  # XOR/DIV
        if funct7 == 0x01:
            # DIV - 有號除法
            dividend = to_signed(rs1_val)
            divisor = to_signed(rs2_val)
            if divisor == 0:
                # 除以零：商 = -1
                result = 0xFFFFFFFF
            elif dividend == -2147483648 and divisor == -1:
                # 溢位：商 = 最小負數
                result = 0x80000000
            else:
                # 向零取整
                quotient = int(dividend / divisor)
                result = quotient & 0xFFFFFFFF
        else:
            result = rs1_val ^ rs2_val  # XOR
    elif funct3 == 0b101:  # SRL/SRA/DIVU
        if funct7 == 0x01:
            # DIVU - 無號除法
            if rs2_val == 0:
                # 除以零：商 = 0xFFFFFFFF
                result = 0xFFFFFFFF
            else:
                result = (rs1_val // rs2_val) & 0xFFFFFFFF
        elif funct7 == 0x20:  # SRA
            result = (to_signed(rs1_val) >> (rs2_val & 0x1F)) & 0xFFFFFFFF
        else:  # SRL
            result = rs1_val >> (rs2_val & 0x1F)
    elif funct3 == 0b110:  # OR/REM
        if funct7 == 0x01:
            # REM - 有號餘數（RISC-V 使用 truncated division，不是 Python 的 floored division）
            dividend = to_signed(rs1_val)
            divisor = to_signed(rs2_val)
            if divisor == 0:
                # 除以零：餘數 = 被除數
                result = rs1_val
            elif dividend == -2147483648 and divisor == -1:
                # 溢位：餘數 = 0
                result = 0
            else:
                # RISC-V REM: remainder = dividend - (dividend/divisor)*divisor
                # 使用 truncated division (int() 向零取整)
                quotient = int(dividend / divisor)
                remainder = dividend - (quotient * divisor)
                result = remainder & 0xFFFFFFFF
        else:
            result = rs1_val | rs2_val  # OR
    elif funct3 == 0b111:  # AND/REMU
        if funct7 == 0x01:
            # REMU - 無號餘數
            if rs2_val == 0:
                # 除以零：餘數 = 被除數
                result = rs1_val
            else:
                result = (rs1_val % rs2_val) & 0xFFFFFFFF
        else:
            result = rs1_val & rs2_val  # AND

    if d['rd'] != 0:
        registers[d['rd']] = result & 0xFFFFFFFF
    pc += 4

def execute_i_alu(d):
    """執行 I-Type ALU 指令"""
    global pc, registers
    rs1_val = registers[d['rs1']]
    imm = d['imm']
    funct3 = d['funct3']
    result = 0

    if funct3 == 0b000:  # ADDI
        result = (rs1_val + imm) & 0xFFFFFFFF
    elif funct3 == 0b010:  # SLTI
        result = 1 if to_signed(rs1_val) < to_signed(imm) else 0
    elif funct3 == 0b011:  # SLTIU
        result = 1 if rs1_val < (imm & 0xFFFFFFFF) else 0
    elif funct3 == 0b100:  # XORI
        result = rs1_val ^ (imm & 0xFFFFFFFF)
    elif funct3 == 0b110:  # ORI
        result = rs1_val | (imm & 0xFFFFFFFF)
    elif funct3 == 0b111:  # ANDI
        result = rs1_val & (imm & 0xFFFFFFFF)
    elif funct3 == 0b001:  # SLLI
        shamt = imm & 0x1F
        result = (rs1_val << shamt) & 0xFFFFFFFF
    elif funct3 == 0b101:  # SRLI/SRAI
        shamt = imm & 0x1F
        if (imm >> 10) & 1:  # SRAI
            result = (to_signed(rs1_val) >> shamt) & 0xFFFFFFFF
        else:  # SRLI
            result = rs1_val >> shamt

    if d['rd'] != 0:
        registers[d['rd']] = result & 0xFFFFFFFF
    pc += 4

def execute_load(d):
    """執行 Load 指令（小端序）"""
    global pc, registers, data_memory
    addr = (registers[d['rs1']] + d['imm']) & 0xFFFFFFFF
    funct3 = d['funct3']

    # 防止越界
    if addr >= len(data_memory):
        pc += 4
        return

    val = 0
    if funct3 == 0b000:  # LB (signed)
        val = data_memory[addr]
        val = sign_extend(val, 8)
    elif funct3 == 0b001:  # LH (signed)
        if addr + 1 < len(data_memory):
            val = data_memory[addr] | (data_memory[addr+1] << 8)
            val = sign_extend(val, 16)
    elif funct3 == 0b010:  # LW
        if addr + 3 < len(data_memory):
            val = (data_memory[addr] |
                   (data_memory[addr+1] << 8) |
                   (data_memory[addr+2] << 16) |
                   (data_memory[addr+3] << 24))
    elif funct3 == 0b100:  # LBU (unsigned)
        val = data_memory[addr]
    elif funct3 == 0b101:  # LHU (unsigned)
        if addr + 1 < len(data_memory):
            val = data_memory[addr] | (data_memory[addr+1] << 8)

    if d['rd'] != 0:
        registers[d['rd']] = val & 0xFFFFFFFF
    pc += 4

def execute_store(d):
    """執行 Store 指令（小端序）"""
    global pc, registers, data_memory
    addr = (registers[d['rs1']] + d['imm']) & 0xFFFFFFFF
    val = registers[d['rs2']]
    funct3 = d['funct3']

    if addr >= len(data_memory):
        pc += 4
        return

    if funct3 == 0b000:  # SB
        data_memory[addr] = val & 0xFF
    elif funct3 == 0b001:  # SH
        if addr + 1 < len(data_memory):
            data_memory[addr] = val & 0xFF
            data_memory[addr+1] = (val >> 8) & 0xFF
    elif funct3 == 0b010:  # SW
        if addr + 3 < len(data_memory):
            data_memory[addr] = val & 0xFF
            data_memory[addr+1] = (val >> 8) & 0xFF
            data_memory[addr+2] = (val >> 16) & 0xFF
            data_memory[addr+3] = (val >> 24) & 0xFF

    pc += 4

def execute_branch(d):
    """執行 Branch 指令"""
    global pc, registers
    rs1_val = registers[d['rs1']]
    rs2_val = registers[d['rs2']]
    funct3 = d['funct3']

    taken = False
    if funct3 == 0b000:  # BEQ
        taken = rs1_val == rs2_val
    elif funct3 == 0b001:  # BNE
        taken = rs1_val != rs2_val
    elif funct3 == 0b100:  # BLT
        taken = to_signed(rs1_val) < to_signed(rs2_val)
    elif funct3 == 0b101:  # BGE
        taken = to_signed(rs1_val) >= to_signed(rs2_val)
    elif funct3 == 0b110:  # BLTU
        taken = rs1_val < rs2_val
    elif funct3 == 0b111:  # BGEU
        taken = rs1_val >= rs2_val

    if taken:
        pc = (pc + d['imm']) & 0xFFFFFFFF
    else:
        pc += 4

def execute_lui(d):
    """執行 LUI 指令"""
    global pc, registers
    if d['rd'] != 0:
        registers[d['rd']] = d['imm'] & 0xFFFFFFFF
    pc += 4

def execute_auipc(d):
    """執行 AUIPC 指令"""
    global pc, registers
    if d['rd'] != 0:
        registers[d['rd']] = (pc + d['imm']) & 0xFFFFFFFF
    pc += 4

def execute_jal(d):
    """執行 JAL 指令"""
    global pc, registers
    if d['rd'] != 0:
        registers[d['rd']] = (pc + 4) & 0xFFFFFFFF
    pc = (pc + d['imm']) & 0xFFFFFFFF

def execute_jalr(d):
    """執行 JALR 指令"""
    global pc, registers
    target = (registers[d['rs1']] + d['imm']) & 0xFFFFFFFE
    if d['rd'] != 0:
        registers[d['rd']] = (pc + 4) & 0xFFFFFFFF
    pc = target

def execute_system(d):
    """執行 System 指令（ECALL/EBREAK）"""
    global pc
    # 停止執行
    pc = 0xFFFFFFFF

def execute(d):
    """執行解碼後的指令"""
    global pc
    opcode = d['opcode']

    if opcode == 0x33:      # R-Type
        execute_r_type(d)
    elif opcode == 0x13:    # I-Type ALU
        execute_i_alu(d)
    elif opcode == 0x03:    # Load
        execute_load(d)
    elif opcode == 0x23:    # Store
        execute_store(d)
    elif opcode == 0x63:    # Branch
        execute_branch(d)
    elif opcode == 0x37:    # LUI
        execute_lui(d)
    elif opcode == 0x17:    # AUIPC
        execute_auipc(d)
    elif opcode == 0x6F:    # JAL
        execute_jal(d)
    elif opcode == 0x67:    # JALR
        execute_jalr(d)
    elif opcode == 0x73:    # CSR/System
        execute_system(d)
    else:
        # 未知指令，跳過
        pc += 4

# ============================================================================
# 主循環
# ============================================================================

def run(max_cycles=10000):
    """執行模擬"""
    global pc
    cycles = 0

    while cycles < max_cycles and pc < len(instruction_memory) - 3:
        # Fetch
        inst = fetch()

        # 檢查是否為結束或 NOP
        if inst == 0 or pc >= 0xFFFFFF00:
            break

        # Decode
        decoded = decode(inst)

        # Execute
        execute(decoded)

        cycles += 1

    return cycles

# ============================================================================
# 輸出 Golden 檔案
# ============================================================================

def save_golden():
    """產生 RF.golden 和 DM.golden"""
    # RF.golden
    with open('RF.golden', 'w') as f:
        f.write("// Register File Contents with Index\n")
        f.write("// Format: [Index] Data\n")
        for i in range(32):
            f.write(f"[{i}] {registers[i]:08x}\n")

    # DM.golden
    with open('DM.golden', 'w') as f:
        f.write("// Data Memory Contents with Address\n")
        f.write("// Format: [Address] Data\n")
        for i in range(len(data_memory)):
            f.write(f"[{i}] {data_memory[i]:02x}\n")

# ============================================================================
# 主程式
# ============================================================================

if __name__ == '__main__':
    print("=" * 50)
    print("RISC-V RV32I Golden Reference Generator")
    print("=" * 50)

    print("\n[1/4] Loading instruction memory...")
    load_im('IM.dat')
    print(f"  Loaded {sum(1 for b in instruction_memory if b != 0)} bytes")

    print("[2/4] Loading data memory...")
    load_dm('DM.dat')
    print(f"  Loaded {sum(1 for b in data_memory if b != 0)} bytes")

    print("[3/4] Running simulation...")
    cycles = run()
    print(f"  Simulation done: {cycles} cycles")

    print("[4/4] Saving golden output...")
    save_golden()
    print("  RF.golden created")
    print("  DM.golden created")

    print("\n" + "=" * 50)
    print("Done! Golden files ready for verification.")
    print("=" * 50)
