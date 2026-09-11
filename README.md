# Pipelined RV32 SoC

A synthesizable 32-bit RISC-V processor with a five-stage pipeline, dynamic
branch prediction, private L1 instruction/data caches, and independent AXI4
memory buses.

This repository contains the CPU core, standalone cache and AXI4 verification
environments, the integrated processor, architecture documents, and an
automated Vivado regression flow.

## Current status

- ISA: RV32I and RV32M
- Pipeline: IF, ID, EX, MEM, WB
- Hazard handling: forwarding, load-use stall, pipeline flush
- Branch prediction: BHT with 2-bit counters and a BTB
- L1 caches: two-way set associative, 64 sets, eight 32-bit words per line
- D-Cache policy: write-through, no-write-allocate
- Memory interface: full AXI4 with 4-bit transaction IDs
- Cache refill: eight-beat incrementing AXI4 bursts
- Verification: all 12 processor regression cases pass
- Synthesis: Vivado 2025.1, zero errors and zero critical warnings

## Architecture

```text
                              +----------------------+
                              |  Five-stage RV32 CPU |
                              +----------+-----------+
                                         |
                          +--------------+--------------+
                          |                             |
                    instruction                     load/store
                          |                             |
                    +-----v-----+                 +-----v-----+
                    |  I-Cache  |                 |  D-Cache  |
                    +-----+-----+                 +-----+-----+
                          | AXI4 read                   | AXI4 read/write
                    +-----v-----+                 +-----v-----+
                    | I AXI4 Bus|                 | D AXI4 Bus|
                    +-----+-----+                 +-----+-----+
                          |                             |
                    +-----v-----+                 +-----v-----+
                    | I-BRAM    |                 | D-BRAM    |
                    +-----------+                 +-----------+
```

The instruction and data paths use independent AXI4 managers. One-entry
response buffers at the CPU/cache boundary preserve a response until the
pipeline can accept the instruction-side and data-side results atomically.
This prevents response loss and forward-progress problems during simultaneous
cache activity.

Architecture diagrams and design notes are available in [`SPEC/`](SPEC/).

![Processor architecture](SPEC/RISC-V%20Processor.png)

## Repository layout

```text
.
|-- five-stage-example/          # Frozen educational five-stage CPU reference
|-- ip/
|   |-- AXI4/                    # AXI4-to-BRAM bridge RTL and standalone tests
|   `-- CACHE/
|       |-- 00_TESTBED/          # Combined cache VCS verification
|       |-- 01_RTL/              # Active I-Cache and D-Cache RTL
|       `-- legacy/              # Previous cache implementation and XDC
|-- RISC-V-Processor/            # Integrated processor and regression flow
|   |-- RTL/
|   |-- Pattern/                 # Existing assembly-style test cases
|   `-- Testbench/               # Golden model and generated memory images
|-- SPEC/                        # Architecture documents and diagrams
|-- LICENSE
`-- README.md
```

## Supported instructions

| Group | Instructions |
|---|---|
| Integer register | `ADD SUB SLL SLT SLTU XOR SRL SRA OR AND` |
| Integer immediate | `ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI` |
| Multiply/divide | `MUL MULH MULHSU MULHU DIV DIVU REM REMU` |
| Load | `LB LH LW LBU LHU` |
| Store | `SB SH SW` |
| Branch | `BEQ BNE BLT BGE BLTU BGEU` |
| Jump | `JAL JALR` |
| Upper immediate | `LUI AUIPC` |
| CSR | `CSRRW CSRRS CSRRC` |

## Verification

### Requirements

- Windows
- Python 3
- Xilinx Vivado 2025.1

The checked-in Vivado batch flow currently uses the local Windows installation
at `C:\Xilinx\2025.1\Vivado`. If the repository is cloned elsewhere, update the
absolute processor paths in `RISC-V-Processor/Script.tcl`,
`RISC-V-Processor/RTL/I_BRAM.sv`, and
`RISC-V-Processor/RTL/RISCV_PROCESSOR_tb.v`.

### Run the processor regression

```powershell
cd RISC-V-Processor
python Verify_Script.py
```

Select one test case or enter `all` to execute the complete 12-case regression.
For every case, the script:

1. Converts the assembly-style pattern into instruction bytes.
2. Generates Vivado `.coe` and synthesizable 32-bit `.mem` images.
3. Runs the Python golden model.
4. Creates a fresh Vivado behavioral simulation snapshot.
5. Compares all 32 GPR values and 32 bytes of data memory.
6. Fails the run if either AXI4 SVA checker reports a protocol violation.

The final integrated version passes all 12 existing cases without modifying
their test programs.

### AXI4 protocol checking

The standalone AXI4 verification environment is located under
[`ip/AXI4/`](ip/AXI4/). Cache integration tests and protocol assertions are
located under [`ip/CACHE/`](ip/CACHE/).

## Synthesis result

The integrated `RISCV_PROCESSOR` top was synthesized for
`xc7z010clg400-1` with Vivado 2025.1:

- 0 synthesis errors
- 0 critical warnings
- instruction `.mem` initialization successfully read by synthesis

The current constraint requests a 250 MHz clock. Passing synthesis does not by
itself guarantee post-place-and-route timing closure; implementation and timing
sign-off remain separate steps.

## License

This project is released under the [MIT License](LICENSE).
