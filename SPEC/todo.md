# RISC-V SoC TODO

## 已確認的架構方向

**CPU Core architecture target:** `RV32IM single-issue in-order core with a decoupled frontend and elastic pipeline.`

- CPU Core 維持獨立的 instruction-side 與 data-side interface。
- I-Cache 對 CPU Core 保持 read-only，只負責 instruction fetch。
- D-Cache 保持 read/write，CPU 若要修改可執行程式碼，必須經由 data-side store。
- Core 外部新增 SoC wrapper，由 SoC 負責 memory、interconnect、boot 與 peripheral。
- 第一版 backing memory 採用 true dual-port Unified SRAM，不再使用彼此隔離的 I-BRAM 與 D-BRAM。

## 目標架構

```text
CPU Core
├── I-Cache ── I-side read interface ──────> Unified SRAM Port A
└── D-Cache ── D-side read/write interface ─> Unified SRAM Port B

External SoC masters, such as DMA or debugger, may write program code into
Unified SRAM through a data/write-capable path. I-Cache remains read-only.
```

## ASIC 開發與驗證環境遷移

已確認直接由 FPGA/Vivado flow 切換至 ASIC flow。新的主要工具鏈為 VCS、Verdi、Design Compiler 與 IC Compiler II；舊 FPGA verification environment 在遷移時直接移除，不保留為主要 regression flow。

### 新環境

- [ ] 建立 ASIC project structure，分離 RTL、testbench、synthesis、gate simulation、PnR、report 與 generated artifact。
- [ ] 建立共用 `file.f`、compile script、run script 與 environment setup，固定 tool version、library、macro、parameter、timescale 與 log 路徑。
- [ ] VCS 採用 compile-once/run-many flow，透過 runtime test name、ELF/memory image 與 seed 執行 regression。
- [ ] Verdi 使用 KDB/FSDB debug flow；正常 regression 預設不開完整 waveform，失敗 testcase 重跑時才開啟必要 scope。
- [ ] 加入 VCS code coverage、assertion coverage、functional coverage 與 X-propagation regression。

### ACT 4.0

- [ ] 以 ACT 4.0 + Sail 作為 RV32I/M architectural verification 主線，不再使用自製 Python golden model。
- [ ] 建立 DUT UDB configuration、`rvmodel_macros.h`、`link.ld` 與 ACT test configuration。
- [ ] VCS testbench 支援載入 ACT self-checking ELF/memory image，並提供 pass、fail、timeout 與必要的 console interface。
- [ ] 先完成 RV32I regression，再執行 RV32M regression，保存 test list、tool version、seed、log 與 coverage database。
- [ ] 為 pipeline hazard、branch flush、cache、AXI backpressure/error 另外建立 directed tests 與 SVA，避免把 ACT 當成完整 microarchitecture verification。

### Synthesis、Gate Simulation 與 PnR

- [ ] Design Compiler flow 執行 read/elaborate/link、`check_design`、constraint check、synthesis、QoR report 與 netlist/SDF 輸出。
- [ ] 使用 Formality 或等效流程確認 RTL 與 synthesized netlist functional equivalence。
- [ ] VCS 執行 post-synthesis zero-delay smoke test 與必要的 SDF gate-level simulation，不以 GLS 取代 RTL regression。
- [ ] IC Compiler II flow 執行 floorplan、placement、CTS、routing、post-route QoR 與 netlist/SDF 輸出。
- [ ] 建立 RTL、synthesis、post-route 各階段的明確 pass/fail gate，禁止以單一 simulation pass 或無 error log 代表 signoff。

### 移除舊 FPGA Verification

- [ ] 刪除 Vivado `Script.tcl`、`.xdc` 與 Vivado-specific simulation/project generation flow。
- [ ] 刪除 `Verify_Script.py`、`Golden_Result.py`、`Instr_Transfer.py` 與 `.coe` conversion flow。
- [ ] 刪除舊 `TestCase*.dat`、`RF.out`、`RF.golden`、`DM.out`、`DM.golden` 及其他舊 generated test data。
- [ ] 刪除舊 FPGA-specific processor/cache testbench，使用新的 VCS testbench、ACT tests、directed tests 與 SVA 取代。
- [ ] 移除 RTL 中的 Vivado/FPGA-specific BRAM attribute、absolute path 與 project dependency，改接 ASIC SRAM wrapper/model。

## RV32I 指令完整性

- [ ] 加入 `MISC-MEM` opcode decode，辨識 RV32I `FENCE`，並將 `FENCE.TSO` 與 reserved configuration 保守地視為完整 `FENCE`。
- [ ] `FENCE` 必須等待所有較早的 load/store 與 outstanding memory transaction 完成，再允許較新的 memory operation 繼續。
- [ ] 在 `SYSTEM` opcode、`funct3 = 3'b000` 下辨識 `ECALL`，於目前單一 Machine mode 設定 `mepc`、`mcause = 11`，並 redirect 至 `mtvec`。
- [ ] 在 `SYSTEM` opcode、`funct3 = 3'b000` 下辨識 `EBREAK`，設定 `mepc`、`mcause = 3`，並 redirect 至 `mtvec`。
- [ ] 為 `ECALL`、`EBREAK` 建立 precise trap control：取消 younger instruction、禁止錯誤的 register/memory side effect，並加入 directed test。

## Phase 1: Unified SRAM

- [ ] 建立 Unified SRAM module，初步容量規劃為 64 KiB。
- [ ] Port A 提供 instruction-side read，Port B 提供 data-side read/write。
- [ ] 將目前分離的 instruction/data memory image 合併成單一 `.mem` 或 `.coe`。
- [ ] 設定 reset vector，第一版暫定為 `0x0000_0000`。
- [ ] 在 SPEC 定義 dual-port same-address read/write collision 的限制。

## Phase 2: Decoupled Frontend、Elastic Pipeline 與 I-Cache

### Core Pipeline

- [ ] 將 CPU Core 劃分為 frontend 與 backend；frontend 包含 PC、BHT/BTB、I-Cache、Fetch Queue，backend 包含 ID、EX、MEM、WB/Retire。
- [ ] 以 Fetch Queue 輸出至 Decode 作為邊界，定義 ready-valid instruction packet，至少攜帶 PC、instruction、prediction metadata、fault 與 epoch。
- [ ] 為 IF/ID、ID/EX、EX/MEM、MEM/WB 建立 explicit valid/ready control；bubble 以 `valid=0` 表示，不再依賴 NOP 代表無效 instruction。
- [ ] 將 stall 改為 local backpressure：I-Cache wait 只阻塞 frontend；MEM/MDU wait 由所在 stage 向 upstream 傳遞。
- [ ] 定義 branch/trap redirect、younger-instruction kill 與 WB/Retire commit semantics，維持 single-issue、in-order execution。

### I-Cache 與 Frontend

- [ ] 將 CPU/cache interface 改成完整的 request/response ready-valid handshake。
- [ ] 讓 I-Cache hit path 可以每 cycle 接受一筆 sequential fetch request。
- [ ] response 攜帶 PC、instruction、prediction metadata、fault 與 epoch。
- [ ] 加入至少 2-entry fetch queue，降低 frontend 與 pipeline 的耦合。
- [ ] 加入 I-Cache hit、miss 與 refill-cycle performance counters。

## Phase 3: `Zifencei`

- [ ] ISA 宣告加入 `Zifencei`，完整名稱暫定為 `RV32IM_Zicsr_Zifencei`。
- [ ] decode `FENCE.I`，opcode 為 `MISC-MEM`，`funct3` 為 `3'b001`。
- [ ] 執行 `FENCE.I` 前等待 outstanding D-side store 完成。
- [ ] 第一版採用 whole I-Cache invalidation，並清除 pending fetch response。
- [ ] flush frontend/fetch queue，從 `FENCE.I` 下一個 PC 重新 fetch。

## Phase 4: SoC 基礎功能

- [ ] 定義完整 memory map 與每個 region 的 R/W/X、cacheable、MMIO attribute。
- [ ] 加入 Boot ROM 或 debugger program-loading path。
- [ ] 加入 UART、timer 與 interrupt controller。
- [ ] 將 SRAM 與 MMIO 接到 address decoder/interconnect。
- [ ] 保留未來接外部 AXI SRAM、DDR 或 DMA 的擴充介面。

## 實作優先順序

1. **固定 architecture contract：**建立 `core-microarchitecture.md`，定義 `rv32im_core`、Cache 與 SoC 的 module hierarchy，以及 I-side/D-side ready-valid interface、pipeline packet、redirect/flush/kill priority、precise trap 與 retire/commit semantics。
2. **建立 ASIC project skeleton：**建立 `rtl/`、`dv/`、`syn/`、`gate/`、`pnr/` 與共用 `file.f`/run script；先讓 `rv32im_core` skeleton 通過 VCS compile、基本 smoke simulation 與 Design Compiler elaborate，再移除舊 FPGA/Vivado verification flow。
3. **重建 RV32IM Core：**先以簡單 instruction/data behavioral memory model 驗證 Core，從 elastic ID/EX/MEM/WB backend、RV32I、precise exception/CSR/FENCE 開始，再加入 iterative MDU 與 RV32M；同步建立 commit trace，依序通過 ACT 4.0 RV32I 與 RV32M regression。
4. **完成 decoupled frontend：**加入 ready-valid Fetch Queue、local backpressure、branch/trap redirect、epoch/kill、BHT/BTB 與 frontend performance counters，並以 directed tests、SVA、coverage 及隨機 latency 驗證 pipeline hazard 和 flush 行為。
5. **整合 Cache、SoC 與 physical flow：**重構 `ip/CACHE` 的 Core-facing interface 與 ASIC SRAM wrapper，完成 Unified dual-port SRAM、AXI/interconnect、`FENCE.I`、boot、MMIO 與 interrupt；最後執行 DC synthesis、Formality、必要的 GLS、ICC2 PnR 與 post-route QoR/signoff checks。

## 待決定參數

- [ ] Unified SRAM 容量是否維持 64 KiB。
- [ ] CPU/cache 之間保留 AXI4，或改用較精簡的 native ready-valid interface。
- [ ] Unified SRAM 使用 vendor BRAM primitive，或撰寫可推導 true dual-port BRAM 的 portable RTL。
- [ ] 第一版是否只用 `.mem/.coe` 初始化，暫不加入 Boot ROM。
- [ ] `FENCE.I` 是否與 Unified SRAM 第一版一起實作。
