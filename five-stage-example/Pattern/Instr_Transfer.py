#!/usr/bin/env python3
# RISC-V RV32I + RV32M 指令轉換器（支援標籤）

import re
import sys

# 指令編碼表
OPCODES = {
    # R-type (RV32I)
    'ADD': 0x33, 'SUB': 0x33, 'SLL': 0x33, 'SLT': 0x33, 'SLTU': 0x33,
    'XOR': 0x33, 'SRL': 0x33, 'SRA': 0x33, 'OR': 0x33, 'AND': 0x33,
    # R-type (RV32M Extension)
    'MUL': 0x33, 'MULH': 0x33, 'MULHSU': 0x33, 'MULHU': 0x33,
    'DIV': 0x33, 'DIVU': 0x33, 'REM': 0x33, 'REMU': 0x33,
    # I-type (arithmetic)
    'ADDI': 0x13, 'SLTI': 0x13, 'SLTIU': 0x13, 'XORI': 0x13, 'ORI': 0x13, 'ANDI': 0x13,
    'SLLI': 0x13, 'SRLI': 0x13, 'SRAI': 0x13,
    # I-type (load)
    'LB': 0x03, 'LH': 0x03, 'LW': 0x03, 'LBU': 0x03, 'LHU': 0x03,
    # I-type (jump/system)
    'JALR': 0x67, 'ECALL': 0x73, 'EBREAK': 0x73,
    # CSR instructions
    'CSRRW': 0x73, 'CSRRS': 0x73, 'CSRRC': 0x73,
    'CSRRWI': 0x73, 'CSRRSI': 0x73, 'CSRRCI': 0x73,
    # S-type
    'SB': 0x23, 'SH': 0x23, 'SW': 0x23,
    # B-type
    'BEQ': 0x63, 'BNE': 0x63, 'BLT': 0x63, 'BGE': 0x63, 'BLTU': 0x63, 'BGEU': 0x63,
    # Pseudo-instruction (將被轉換成 BGE)
    'BLE': 0x63, 'BLEU': 0x63, 'BGT': 0x63, 'BGTU': 0x63,
    # U-type
    'LUI': 0x37, 'AUIPC': 0x17,
    # J-type
    'JAL': 0x6F
}

FUNCT3 = {
    'ADD': 0, 'SUB': 0, 'ADDI': 0, 'SLL': 1, 'SLLI': 1, 'SLT': 2, 'SLTI': 2,
    'SLTU': 3, 'SLTIU': 3, 'XOR': 4, 'XORI': 4, 'SRL': 5, 'SRA': 5, 'SRLI': 5, 'SRAI': 5,
    'OR': 6, 'ORI': 6, 'AND': 7, 'ANDI': 7, 'LB': 0, 'LH': 1, 'LW': 2, 'LBU': 4, 'LHU': 5,
    'SB': 0, 'SH': 1, 'SW': 2,
    'BEQ': 0, 'BNE': 1, 'BLT': 4, 'BGE': 5, 'BLTU': 6, 'BGEU': 7,
    'BLE': 5, 'BLEU': 7, 'BGT': 4, 'BGTU': 6,  # 偽指令
    'JALR': 0, 'ECALL': 0, 'EBREAK': 0,
    'CSRRW': 1, 'CSRRS': 2, 'CSRRC': 3, 'CSRRWI': 5, 'CSRRSI': 6, 'CSRRCI': 7,
    # RV32M Extension
    'MUL': 0, 'MULH': 1, 'MULHSU': 2, 'MULHU': 3,
    'DIV': 4, 'DIVU': 5, 'REM': 6, 'REMU': 7
}

FUNCT7 = {
    'ADD': 0, 'SUB': 0x20, 'SLL': 0, 'SLT': 0, 'SLTU': 0, 'XOR': 0,
    'SRL': 0, 'SRA': 0x20, 'OR': 0, 'AND': 0, 'SLLI': 0, 'SRLI': 0, 'SRAI': 0x20,
    # RV32M Extension (所有 RV32M 指令 funct7 = 0x01)
    'MUL': 0x01, 'MULH': 0x01, 'MULHSU': 0x01, 'MULHU': 0x01,
    'DIV': 0x01, 'DIVU': 0x01, 'REM': 0x01, 'REMU': 0x01
}

def parse_csr(csr_name):
    """解析 CSR 名稱，返回 CSR 位址"""
    csr_map = {
        'mstatus': 0x300, 'mtvec': 0x305, 'mepc': 0x341, 'mcause': 0x342,
        'rdcycle': 0xC00, 'rdcycleh': 0xC80, 'rdinstret': 0xC02, 'rdinstreth': 0xC82
    }
    if csr_name in csr_map:
        return csr_map[csr_name]
    if csr_name.startswith('0x'):
        return int(csr_name, 16)
    return int(csr_name)

def parse_register(reg):
    """解析暫存器名稱，返回數字"""
    if reg.startswith('x'):
        return int(reg[1:])
    return 0

def parse_immediate(imm, labels=None, current_addr=0):
    """解析立即數或標籤"""
    # 如果是標籤引用
    if labels and imm in labels:
        offset = labels[imm] - current_addr
        return offset
    # 如果是數字
    if imm.startswith('0x'):
        return int(imm, 16)
    if imm.lstrip('-').isdigit():
        return int(imm)
    # 無法解析，返回 0
    return 0

def sign_extend(value, bits):
    """符號擴展"""
    if value & (1 << (bits - 1)):
        value -= (1 << bits)
    return value

def collect_labels(lines):
    """第一次掃描：收集所有標籤及其位址"""
    labels = {}
    address = 0

    for line in lines:
        line = line.strip()

        # 跳過空行和註解
        if not line or line.startswith('//'):
            continue

        # 移除行尾註解（以 // 開頭的部分）
        if '//' in line:
            code_part = line.split('//')[0].strip()
        else:
            code_part = line

        # 檢查是否為標籤定義（只在代碼部分檢查冒號）
        if ':' in code_part:
            parts = code_part.split(':', 1)
            if len(parts) >= 2:
                label_name = parts[0].strip()
                # 記錄標籤位址
                labels[label_name] = address

                # 檢查標籤後是否有指令
                rest = parts[1].strip()
                if rest:
                    # 標籤後有指令，計入位址
                    address += 4
                continue

        # 一般指令，位址 +4
        parts = code_part.split()
        if parts and parts[0].upper() in OPCODES:
            address += 4

    return labels

def encode_instruction(parts, labels=None, current_addr=0):
    """編碼單一指令"""
    opcode_name = parts[0].upper()

    # 處理偽指令 BLE, BLEU, BGT, BGTU
    if opcode_name in ['BLE', 'BLEU', 'BGT', 'BGTU']:
        # BLE rs1, rs2, label => BGE rs2, rs1, label
        # BGT rs1, rs2, label => BLT rs2, rs1, label
        rs1 = parts[1].rstrip(',')
        rs2 = parts[2].rstrip(',')
        target = parts[3]

        if opcode_name == 'BLE':
            return encode_instruction(['BGE', rs2, rs1, target], labels, current_addr)
        elif opcode_name == 'BLEU':
            return encode_instruction(['BGEU', rs2, rs1, target], labels, current_addr)
        elif opcode_name == 'BGT':
            return encode_instruction(['BLT', rs2, rs1, target], labels, current_addr)
        elif opcode_name == 'BGTU':
            return encode_instruction(['BLTU', rs2, rs1, target], labels, current_addr)

    opcode = OPCODES.get(opcode_name, 0)

    # R-type 指令 (包含 RV32I 和 RV32M)
    if opcode_name in ['ADD', 'SUB', 'SLL', 'SLT', 'SLTU', 'XOR', 'SRL', 'SRA', 'OR', 'AND',
                       'MUL', 'MULH', 'MULHSU', 'MULHU', 'DIV', 'DIVU', 'REM', 'REMU']:
        rd = parse_register(parts[1].rstrip(','))
        rs1 = parse_register(parts[2].rstrip(','))
        rs2 = parse_register(parts[3])
        funct3 = FUNCT3[opcode_name]
        funct7 = FUNCT7[opcode_name]
        return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    # I-type 立即數運算
    elif opcode_name in ['ADDI', 'SLTI', 'SLTIU', 'XORI', 'ORI', 'ANDI']:
        rd = parse_register(parts[1].rstrip(','))
        rs1 = parse_register(parts[2].rstrip(','))
        imm = parse_immediate(parts[3], labels, current_addr)
        # 處理負數偏移量：轉換成 12-bit 二補數
        if imm < 0:
            imm = (1 << 12) + imm
        imm = imm & 0xFFF
        funct3 = FUNCT3[opcode_name]
        return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    # I-type 移位
    elif opcode_name in ['SLLI', 'SRLI', 'SRAI']:
        rd = parse_register(parts[1].rstrip(','))
        rs1 = parse_register(parts[2].rstrip(','))
        shamt = parse_immediate(parts[3], labels, current_addr) & 0x1F
        funct3 = FUNCT3[opcode_name]
        funct7 = FUNCT7[opcode_name]
        imm = (funct7 << 5) | shamt
        return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    # I-type 載入指令
    elif opcode_name in ['LB', 'LH', 'LW', 'LBU', 'LHU']:
        rd = parse_register(parts[1].rstrip(','))
        match = re.match(r'(-?\d+)\(x(\d+)\)', parts[2])
        imm = parse_immediate(match.group(1), labels, current_addr)
        # 處理負數偏移量：轉換成 12-bit 二補數
        if imm < 0:
            imm = (1 << 12) + imm
        imm = imm & 0xFFF
        rs1 = int(match.group(2))
        funct3 = FUNCT3[opcode_name]
        return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    # S-type 儲存指令
    elif opcode_name in ['SB', 'SH', 'SW']:
        rs2 = parse_register(parts[1].rstrip(','))
        match = re.match(r'(-?\d+)\(x(\d+)\)', parts[2])
        imm = parse_immediate(match.group(1), labels, current_addr)
        # 處理負數偏移量：轉換成 12-bit 二補數
        if imm < 0:
            imm = (1 << 12) + imm
        imm = imm & 0xFFF
        rs1 = int(match.group(2))
        funct3 = FUNCT3[opcode_name]
        imm_11_5 = (imm >> 5) & 0x7F
        imm_4_0 = imm & 0x1F
        return (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_4_0 << 7) | opcode

    # B-type 分支指令
    elif opcode_name in ['BEQ', 'BNE', 'BLT', 'BGE', 'BLTU', 'BGEU']:
        rs1 = parse_register(parts[1].rstrip(','))
        rs2 = parse_register(parts[2].rstrip(','))
        imm = parse_immediate(parts[3], labels, current_addr)
        # 處理負數偏移量：轉換成 13-bit 二補數
        if imm < 0:
            imm = (1 << 13) + imm
        imm = imm & 0x1FFE
        funct3 = FUNCT3[opcode_name]
        imm_12 = (imm >> 12) & 1
        imm_11 = (imm >> 11) & 1
        imm_10_5 = (imm >> 5) & 0x3F
        imm_4_1 = (imm >> 1) & 0xF
        return (imm_12 << 31) | (imm_10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_4_1 << 8) | (imm_11 << 7) | opcode

    # U-type 指令
    elif opcode_name in ['LUI', 'AUIPC']:
        rd = parse_register(parts[1].rstrip(','))
        imm = parse_immediate(parts[2], labels, current_addr) & 0xFFFFF
        return (imm << 12) | (rd << 7) | opcode

    # J-type JAL
    elif opcode_name == 'JAL':
        rd = parse_register(parts[1].rstrip(','))
        imm = parse_immediate(parts[2], labels, current_addr)
        # 處理負數偏移量：轉換成 21-bit 二補數
        if imm < 0:
            imm = (1 << 21) + imm
        imm = imm & 0x1FFFFE
        imm_20 = (imm >> 20) & 1
        imm_19_12 = (imm >> 12) & 0xFF
        imm_11 = (imm >> 11) & 1
        imm_10_1 = (imm >> 1) & 0x3FF
        return (imm_20 << 31) | (imm_10_1 << 21) | (imm_11 << 20) | (imm_19_12 << 12) | (rd << 7) | opcode

    # I-type JALR
    elif opcode_name == 'JALR':
        rd = parse_register(parts[1].rstrip(','))
        rs1 = parse_register(parts[2].rstrip(','))
        imm = parse_immediate(parts[3], labels, current_addr)
        # 處理負數偏移量：轉換成 12-bit 二補數
        if imm < 0:
            imm = (1 << 12) + imm
        imm = imm & 0xFFF
        funct3 = FUNCT3[opcode_name]
        return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    # CSR 指令
    elif opcode_name in ['CSRRW', 'CSRRS', 'CSRRC', 'CSRRWI', 'CSRRSI', 'CSRRCI']:
        rd = parse_register(parts[1].rstrip(','))
        csr_addr = parse_csr(parts[2].rstrip(','))
        funct3 = FUNCT3[opcode_name]

        if opcode_name.endswith('I'):  # 立即數版本
            uimm = parse_immediate(parts[3], labels, current_addr) & 0x1F
            return (csr_addr << 20) | (uimm << 15) | (funct3 << 12) | (rd << 7) | opcode
        else:  # 暫存器版本
            rs1 = parse_register(parts[3])
            return (csr_addr << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    # 系統指令
    elif opcode_name == 'ECALL':
        return 0x73
    elif opcode_name == 'EBREAK':
        return 0x100073

    return 0

def convert_instructions(input_file, output_file):
    """轉換指令檔案（支援標籤）"""
    # 讀取所有行
    with open(input_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    # 第一次掃描：收集標籤
    labels = collect_labels(lines)

    if labels:
        print(f"找到 {len(labels)} 個標籤:")
        for label, addr in labels.items():
            print(f"  {label}: 0x{addr:04X}")

    # 第二次掃描：轉換指令
    with open(output_file, 'w', encoding='utf-8') as f_out:
        address = 0

        for line in lines:
            original_line = line.strip()

            # 跳過空行和註解
            if not original_line or original_line.startswith('//'):
                continue

            # 移除行尾註解
            if '//' in original_line:
                code_part = original_line.split('//')[0].strip()
                original_line_for_comment = original_line  # 保留完整註解用於輸出
            else:
                code_part = original_line
                original_line_for_comment = original_line

            # 處理標籤定義（只在代碼部分檢查冒號）
            if ':' in code_part:
                parts = code_part.split(':', 1)
                label_name = parts[0].strip()

                # 檢查標籤後是否有指令
                if len(parts) > 1:
                    rest = parts[1].strip()
                    if rest:
                        # 標籤後有指令，處理該指令
                        code_part = rest
                        original_line_for_comment = rest
                    else:
                        # 只有標籤，跳過
                        continue
                else:
                    continue

            # 解析指令
            parts = code_part.split()
            if not parts or parts[0].upper() not in OPCODES:
                continue

            try:
                # 編碼指令
                machine_code = encode_instruction(parts, labels, address)

                # 轉換為大端序位元組
                bytes_data = machine_code.to_bytes(4, 'big')

                # 寫入註解
                f_out.write(f"// {original_line_for_comment}\n")

                # 寫入十六進制位元組（大寫）
                for byte in bytes_data:
                    f_out.write(f"{byte:02X}\n")

                # 更新位址
                address += 4

            except Exception as e:
                print(f"Error processing line: {original_line}")
                print(f"Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("使用方法: python rv32i_transfer.py <instruction_file>")
        print("範例: python rv32i_transfer.py Pattern/TestCase1.dat")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = "IM.dat"

    try:
        convert_instructions(input_file, output_file)
        print(f"\n轉換完成！")
        print(f"輸入檔案：{input_file}")
        print(f"輸出檔案：{output_file}")
    except FileNotFoundError:
        print(f"錯誤：找不到檔案 {input_file}")
    except Exception as e:
        print(f"轉換過程中發生錯誤：{e}")
