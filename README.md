# LoongArch 乱序超标量 CPU

基于 **LoongArch 32 位指令集** 的 RISC 风格处理器，采用 **双发射、乱序执行（Out-of-Order）、分支预测、多级 Cache 与 TLB** 的完整流水线设计，面向 Xilinx FPGA 综合实现。源码使用 Verilog 编写。

---

## 1. 项目简介

本项目实现了一个功能完整的 LoongArch 处理器核心：

- **指令集**：LoongArch 32 位（整数基础指令），支持算术逻辑、乘除法、访存（含 LL/SC 原子）、分支跳转、`lu12i`/`pcaddu12i`、CSR 特权指令、TLB 指令、Cache 操作（`cacop`/`preld`）、`ertn`/`idle`/`cpucfg` 等。
- **微架构**：双发射 + 乱序执行。取指/译码/重命名/分发/发射均为每周期 2 条，提交为每周期 1 条。
- **前端**：8B 对齐双指令取指，两级分支预测（BHT+PHT）、BTB 与 RAS 返回地址栈。
- **后端**：RMT 重命名 + ROB + IQ 发射队列 + 2×ALU / MUL / DIV / LSU 执行单元，LSQ 存储队列，CDB 双写回。
- **存储层次**：8KB ICache、8KB DCache（写回）、32 项 TLB（4KB/4MB 页）、DMW 直映射窗口。
- **外部接口**：AXI4 总线接口，8 位硬中断输入，可扩展 DIFFTEST 差分测试接口。

---

## 2. 目录结构

```
lzu2026/
├── README.md                    # 本文件
├── .gitignore
├── agent_workspace/             # Agent 本地私有工作区（已 gitignore）
└── src/
    ├── cpu_top.v                # 顶层模块 core_top
    ├── LoongArch.vh             # 指令宏定义头文件
    ├── axi_bridge.v             # AXI4 总线桥
    ├── csr.v                    # 控制与状态寄存器
    ├── dcache.v                 # 数据缓存（写回，2 路组相联）
    ├── grf.v                    # 通用寄存器堆（32×32）
    ├── stop_control.v           # 流水线停顿/清空控制
    ├── tlb.v                    # TLB（32 项）
    ├── counter.v                # 计时器（rdcnt / 随机源）
    ├── frontend/                # ── 取指前端 ──
    │   ├── if_stage.v           #   取指流水级
    │   ├── per_if_stage.v       #   预取指级（含 TLB/异常处理）
    │   ├── icache.v             #   指令缓存（底层）
    │   ├── icache_top.v         #   指令缓存（顶层）
    │   └── branch_predict/      #   分支预测子系统
    │       ├── branch_predict.v
    │       ├── branch_target_buffer.v
    │       ├── branch_history_table.v
    │       ├── pattern_history_table.v
    │       └── return_address_stack.v
    ├── backend/                 # ── 乱序执行后端 ──
    │   ├── id_stage.v           #   译码级（双发）
    │   ├── decoder.v            #   译码器
    │   ├── extend.v             #   立即数扩展
    │   ├── dispatch.v           #   分发
    │   ├── exe.v                #   执行级（含访存地址计算）
    │   ├── lsq.v                #   Load/Store 队列（SQ 8 + LQ 1）
    │   ├── lsu.v                #   Load/Store 单元
    │   └── ooq/                 #   乱序核心
    │       ├── RMT.v            #     重命名映射表
    │       ├── ROB.v            #     重排序缓冲（8 项）
    │       ├── IQ.v             #     指令队列（8 项）
    │       ├── issue_top.v      #     发射逻辑
    │       ├── retire.v         #     退役
    │       └── commit.v         #     提交
    ├── execute/                 # ── 运算执行单元 ──
    │   ├── alu.v                #   整数 ALU
    │   ├── cla.v                #   超前进位加法器
    │   ├── csa.v                #   进位保存加法器
    │   ├── full_adder.v         #   全加器
    │   ├── mul.v                #   乘法器（DSP，3 周期）
    │   └── div/                 #   除法器（radix-4 SRT）
    │       ├── div.v
    │       ├── div_lut.v
    │       ├── div_sel.v
    │       ├── normalizer.v
    │       ├── q_convert.v
    │       └── qcoor.v
    └── xilinx_ip/               # Xilinx IP（bank/tag_tab/mult_gen）
```

---

## 3. 核心参数

| 类别 | 参数 | 数值 |
| ---- | ---- | ---- |
| 指令集 | ISA | LoongArch 32 位（整数） |
| 数据位宽 | 寄存器/数据通路 | 32 位 |
| 取指宽度 | 每周期 | 2 条（8B 对齐） |
| 发射宽度 | 每周期 | 2 条 |
| 提交宽度 | 每周期 | 1 条 |
| 架构寄存器 | GRF | 32 × 32 位，4 读 1 写 |
| 重命名表 | RMT | 32 项（映射到 ROB） |
| 重排序缓冲 | ROB | 8 项 |
| 指令队列 | IQ | 8 项 |
| 执行单元 | ALU | ×2，1 周期 |
| 执行单元 | MUL | ×1，3 周期（DSP 乘法） |
| 执行单元 | DIV | ×1，radix-4 SRT 迭代 |
| 执行单元 | LSU | ×1 |
| Load/Store 队列 | LSQ | 存储队列 8 项 + 装载队列 1 项 |
| 指令缓存 | ICache | 8 KB，2 路组相联，32 B/行（128 组） |
| 数据缓存 | DCache | 8 KB，2 路组相联，16 B/行（256 组），写回 |
| TLB | 条目 | 32 项（4 组 × 8 项/组），4 KB / 4 MB 页 |
| TLB 搜索口 | 端口 | 2（取指 / 访存各一） |
| 分支预测 | BTB | 512 项（20b tag + 30b 目标） |
| 分支预测 | BHT | 512 × 10 bit 历史 |
| 分支预测 | PHT | 2 × 8192 项 2 bit 饱和计数器（gshare） |
| 分支预测 | RAS | 16 项返回地址栈 |
| 中断 | 硬中断输入 | 8 位 |
| 总线 | 外部接口 | AXI4（读/写通道，4 位 ID） |

---

## 4. 架构概览

### 4.1 总体结构

```mermaid
flowchart LR
    subgraph 前端 Front-End
        PIF[pre_if_stage\n预取指 + TLB s0]
        BHT0[分支预测\nBTB/BHT/PHT/RAS]
        IC[Icache_top / icache\n8KB 2路]
        IF[if_stage\n取指(2条)]
    end
    subgraph 后端 Back-End
        ID[id_stage\n译码(2条)]
        DIS[dispatch\n分发(2条)]
        RMT[RMT 重命名]
        ROB[ROB 8项]
        IQ[IQ 8项]
        ISS[issue_top\n发射(2条)]
        EXE[exe_top\n执行级]
        FU1[ALU ×2]
        FU2[MUL]
        FU3[DIV]
        FU4[LSU + LSQ]
        COM[retire / commit\n提交(1条)]
    end
    subgraph 存储与系统
        DC[dcache\n8KB 写回]
        TLB[TLB 32项]
        CSR[CSR + DMW]
        AXI[axi_bridge\nAXI4]
        GRF[GRF 32×32]
    end

    PIF --> IC --> IF
    BHT0 --> PIF
    IF --> ID --> DIS
    DIS --> RMT
    DIS --> ROB
    DIS --> IQ
    RMT --> IQ
    IQ --> ISS
    ISS --> EXE
    EXE --> FU1 & FU2 & FU3 & FU4
    FU1 & FU2 & FU3 & FU4 --> ROB
    FU4 <--> DC
    DC --> AXI
    TLB <--> EXE
    CSR --> EXE
    ROB --> COM
    COM --> GRF
    COM --> CSR
```

### 4.2 流水线

采用「前端顺序、后端乱序」的多级流水线：

```mermaid
flowchart LR
    A[预取指 pre_if] --> B[取指 if_stage]
    B --> C[译码 id_stage]
    C --> D[分发 dispatch]
    D --> E[RMT 重命名]
    E --> F[IQ 排队 + ROB 分配]
    F --> G[发射 issue]
    G --> H[执行 ALU/MUL/DIV/LSU]
    H --> I[写回 CDB]
    I --> J[退役 retire]
    J --> K[提交 commit]
```

- **分支预测**与取指并行，每周期预测 2 条指令的跳转方向与目标。
- **重命名**（RMT）以 ROB 条目充当物理寄存器：每条写架构寄存器的指令分配一个 ROB 条目，从而消除 WAR/WAW 伪相关；源操作数经 RMT 查询其最新映射（ROB 索引），未就绪时等待该 ROB 条目经 CDB 广播写回，从而解决 RAW 真相关。
- **发射**由 IQ 根据源就绪状态与功能单元空闲情况（`fu_ready`）选择指令，送入对应执行单元。
- **执行结果**通过 CDB 总线（每周期 2 个）广播写回，并送入 ROB 打包写回。
- **提交**为每周期 1 条，按序提交到 GRF / CSR；异常、`ertn`、`idle` 在提交级统一处理并冲刷流水线。

### 4.3 分支预测

- 指令类型分类：`may b` / `must b` / `call`（`bl`/`jirl`）/ `ret`（`jirl`）。
- **BTB**（512 项，Block RAM）缓存指令类型、目标地址与 tag。
- **BHT**（512×10 bit，分布式 RAM）记录每条分支的历史模式。
- **PHT**（2×8192 项 2 bit 饱和计数器，Block RAM）：采用 gshare 风格，用「PC 索引 ⊕ BHT 历史」作为表地址，预测跳转方向。
- **RAS**（16 项）支持调用/返回栈，带 checkpoint 恢复。
- 预测结果会分别在取指（IF）与退役/提交阶段与实际执行信息比对校验；预测错误时刷新 BTB/BHT/PHT/RAS（含 checkpoint 恢复）、冲刷流水线，并由 `per_if_stage` 从正确 PC 重新取指。

### 4.4 乱序执行核心（backend/ooq）

| 模块 | 作用 |
| ---- | ---- |
| `RMT` | 架构寄存器 → ROB 条目的映射，分发时分配、提交时释放，2 路并行查询 |
| `ROB` | 8 项，记录 PC/目的寄存器/分支信息/异常，打包写回，按序提交 |
| `IQ` | 8 项发射队列，记录源就绪与所需 ROB 索引，被 CDB 唤醒后发射 |
| `issue_top` | 根据功能单元空闲与源就绪仲裁发射（每周期 2 条） |
| `retire` | 退役，通知 LSQ 发送已退休的存储操作 |
| `commit` | 提交到 GRF/CSR，处理异常/中断/`ertn`/`idle` |

执行单元：
- **ALU**（×2）：加减、逻辑、移位、比较，1 周期；同时处理分支、`lu12i`/`pcaddu12i`、CSR 读写、`syscall`/`break`/`ertn`/`idle`/`cpucfg` 等。
- **MUL**（×1）：32×32 有/无符号乘法，拆分为 16×16 部分积，基于 DSP（`mult_gen` IP），3 周期。
- **DIV**（×1）：radix-4 SRT 除法（商数字集 {−2,−1,0,1,2}），由 CSA/CLA、商查找表（`div_lut`）、归一化（`normalizer`）、商/余校正（`q_convert`/`qcoor`）组成，支持 `div`/`mod`/`divu`/`modu`。
- **LSU**（×1）+ **LSQ**：存储队列 8 项 + 装载队列 1 项，实现 store-to-load 转发、`cacop` 冲突阻塞、未退休存储不提前发往 DCache。

### 4.5 存储层次与系统

- **ICache / DCache**：均为 8 KB、2 路组相联；ICache 行 32 B（4×64 bit bank），DCache 行 16 B（4×32 bit bank）。DCache 带 dirty 位，采用**写回**策略，含写缓冲。缺失时通过 AXI 按行填充，替换策略使用 **PLRU**（伪 LRU）。
- **TLB**：32 项（4 组 × 8 项/组），支持 4 KB / 4 MB 页、ASID、双搜索口（取指 s0 / 访存 s1），实现 `tlbsrch`/`tlbrd`/`tlbwr`/`tlbfill`/`invtlb`。
- **CSR**：LoongArch 系统寄存器（CRMD/PRMD/ERA/EENTRY/ECODE/BADV/ASID/TLB 相关等），支持异常入口、`ertn` 返回、`idle`、硬中断（8 位）与 **LLbit**（LL/SC 原子）。
- **MMU**：支持 DA（直接地址）/PG（页式）模式切换，以及 **DMW0/DMW1** 直映射窗口。
- **AXI 总线桥**：将 ICache/DCache 的访存请求转换为标准 AXI4 读写事务，连接外部存储。

### 4.6 外部接口（顶层 core_top）

- AXI4：`ar/aw/w/b/r` 五通道，4 位 ID，支持突发。
- 中断：8 位 `intrpt`。
- 调试：`break_point`、`infor_flag`、`reg_num`、`ws_valid`、`rf_rdata` 等；`debug0_wb_*` 写回观测端口；GRF 支持 `DIFFTEST_EN` 差分测试导出。

---

## 5. 构建与仿真说明

> 说明：整理目录后，`if_stage.v`、`icache_top.v`、`branch_predict.v` 中的 `` `include "LoongArch.vh" `` 需要把 `src/` 加入 include 搜索路径（Vivado 的 Include Directories 或 `+incdir+src`）。在 Vivado 环境中通常不受影响。

- **综合/实现**：Vivado（工程需重新添加 `src/` 下的 `.v` 源文件与 `xilinx_ip/` 中的 IP）。
- **仿真**：Verilog 仿真器（VCS / XSim / Verilator 等），顶层测试对象为 `core_top`。
- **差分测试**：可通过 `DIFFTEST_EN` 宏开启与参考模型（如 qemu/NEMU）的差分对比。

---

## 6. 项目质量评价

> **说明：本节评价由 AI（GitHub Copilot）基于对源代码的静态阅读自动生成，仅供作者参考，不代表作者观点，也可能存在误判。**

**优点：**

- **架构完整性高**：覆盖了乱序执行所需的关键组件（重命名、ROB、发射队列、CDB、退役/提交），并且将取指前端、分支预测、存储层次、特权系统完整打通，作为课程/体系结构项目而言功能覆盖相当全面。
- **模块划分清晰、命名规范**：代码大量使用「数据包」（如 `o_2_exe_466`、`i_if_to_id_data_170`）集中传递信号，模块间接口较规整；注释（尤其是中文注释）较丰富，便于阅读与维护。
- **工程组织良好**：源码按功能模块分类（`frontend` / `backend` / `execute`），文件职责单一，可读性好。
- **分支预测、乘除法等部件实现较有深度**：gshare 风格 PHT、RAS checkpoint、radix-4 SRT 除法、DSP 乘法等体现了对微架构细节的思考。
- **可测试性设计**：预留了 DIFFTEST 接口与调试观测端口，方便验证。

**不足与风险：**

- **参数硬编码较多**：ROB/IQ/LSQ 深度等多处写死（如注释提到“有些地方用参数不好写故直接写死了”），扩展性或配置化较弱，改容量需谨慎。
- **接口以位宽拼接为主**：超宽数据包（170~466 bit）虽然减少了连线数量，但位域含义依赖注释与顺序，改动时容易出错、可维护性一般。
- **缓存/队列的时序与冲突处理较复杂**：DCache 写缓冲、LSQ 的 cacop 冲突阻塞、ICache 行填充等逻辑分支较多，缺少统一的状态机封装，存在潜在的边界时序风险（未实测无法定论）。
- **未提供测试平台与构建脚本**：仓库中暂无 testbench 与自动化编译/仿真脚本，回归验证需要自行搭建。
- **部分文件编码/注释出现乱码**（如 `exe.v`、`lsu.v`、`div.v` 中个别注释），说明存在编码不一致问题，建议统一为 UTF-8 并清理。

**总体评价**：这是一个**结构完整、功能丰富、实现有深度的乱序 CPU 设计**，作为课程设计或研究原型质量较好；但在**参数化、可维护性、测试支撑**方面仍有改进空间。

---

## 7. 作者分析

> （此部分留空，供作者填写设计思路、实现心得、性能分析、改进方向等内容。）
