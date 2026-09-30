# Differential Testing 设计

## 参考模型

编写独立 RV64IMA ISS（Python 或 C++），不得复用 RTL 解码器、执行函数或状态更新代码。ISS 每条指令输出 PC、指令、下一 PC、寄存器写回、CSR 写回、内存事务、特权级和 trap 信息。

## RTL trace

仿真顶层导出：`commit_valid`、`commit_pc`、`commit_insn`、`commit_rd`、`commit_rd_value`、`commit_csr_write`、`commit_mem_access`、`trap_valid`、`trap_cause`、`privilege_mode`。比较器在首个差异处停止并保存前后上下文、流水线状态、cache/TLB 状态和内存事务。

## 测试生成

- 手写汇编边界测试。
- 官方 ISA 测试二进制。
- 结构化随机指令流：控制流、CSR、异常、中断、内存别名和原子操作分别加权。
- 由 Linux 启动阶段产生的真实 trace。

## 判定

只有逐条 trace 完全一致才算通过。允许 RTL 和 ISS 在未提交的内部时序上不同，但提交顺序、架构状态和可见内存事务必须一致。

## 当前工具

`tools/differential/compare_trace.py` 使用 UTF-8 JSON Lines 作为稳定的提交记录格式。
每行必含 `pc`、`instruction`、`next_pc`、`rd` 和 `rd_value`；取指 fault 没有解码出的
指令时，`instruction` 为 `null`、`rd` 为 `0`。trap 场景还可包含 `trap_cause`、`trap_value`
和提交后的 `privilege`。比较器在第一个不同提交或长度不一致处失败。该工具不导入 RTL 包
或解码表，后续 CPU testbench 可直接导出同一格式接入门禁。

`rv64_core` 当前是单周期顺序执行原型，先用于验证架构状态和 BRAM 事务；它不是最终
的三级流水线实现。三级流水线将在该提交契约稳定后替换，避免将内部时序差异混入
differential 判定。

`scripts/run-core-diff.sh` 已将核心 smoke program 接入完整流程：xsim testbench 导出
`build/xsim/core/rtl_trace.jsonl`，独立 ISS 生成 `iss_trace.jsonl`，再由比较器逐条检查
`pc`、指令、下一 PC、目的寄存器和写回值。该 trace 目前仍不包含 CSR/trap 字段；
CSR 已进入核心，但带 CSR/trap 的提交格式和独立 ISS 对照仍列为后续工作。

`run-core-random-diff.sh` 使用固定 seed `0x52563634` 生成 96 条结构化随机 RV64IMA
整数、乘除、余数和访存指令，xsim 从生成的 hex 装载同一程序，独立 ISS 生成期望 trace
后逐条比较。该回归覆盖随机寄存器依赖、移位边界、M 扩展边界和 64 位对齐访存；
cache 交互已由 SoC 随机回归覆盖；`mmu_random` 已覆盖 MMU 单元的 Sv39 TLB
交互并输出命中、walk、`SFENCE.VMA`、`satp`、超页和 fault 摘要。

`run-soc-random-diff.sh` 将同一程序装载到 BRAM SoC，覆盖随机读写和原子事务，再比较
完整提交 trace；它覆盖延迟 miss、hit、write-through，并验证 BRAM 原子访问直通路径。
DDR3 模型路径的原子 read-modify-write 由 `soc_ddr3_atomic` 验证；最终 SoC MIG
top-level 仍需接入同等事务端点并进行硬件验证。

`ddr3_mig_atomic_path` 回归现已验证该 MIG CDC/AXI 包装器的 LR/SC/AMO 串行读-改-写，
包括 reservation 成功/失败和失败 SC 的无事务行为。

`scripts/run-soc-cache-diff.sh` 在 cacheable BRAM SoC 中运行包含 write miss、read miss、
read hit、分支和可见内存写入的程序，再将 RTL 提交 trace 与独立 ISS 比较。

`scripts/run-soc-ddr3-diff.sh` 使用独立 ISS 运行同一程序的 `0x8000_0000` DDR3 地址窗口，
覆盖 64 位地址构造、DDR3 write-through、延迟 miss、后续 hit 和可见内存写入。

该回归使用 Bare 物理地址访问，证明 cache 造成的内部等待不改变提交顺序；它不替代
Sv39 翻译、页故障或特权 CSR 的 differential 覆盖。

`scripts/run-soc-mmu-diff.sh` 使用独立 PTE walker、最小 CSR/MRET 状态和同一程序的
RTL trace 比较 M-mode 配置、进入 S-mode 后的 Sv39 取指及虚拟数据读写。

`scripts/run-soc-mmu-fault-diff.sh` 以独立 Sv39 PTE walker 和 ISS 生成无效 S-mode
取指页，以及 execute-only 数据页上的 S-mode `ld`/`sd` fault trace，并逐条比较 M-mode
配置、`mret`、故障提交的 `mepc`、fetch/load/store-page-fault cause、`mtval`、trap vector
与返回特权级，同时确认 store 没有可见内存副作用。

`scripts/run-soc-mmu-sum-diff.sh` 使用 supervisor-only 代码页和 user R/W 数据页：先
比较 `SUM=0` 的 load page fault，再比较 `SUM=1` 对同一地址的成功 load 和返回值。

`scripts/run-soc-mmu-user-diff.sh` 在 user executable 代码页运行 U-mode `ld`：先对
supervisor-only 数据页比较 load page fault，再将同一数据页设为 user 并比较成功 load。
该场景同时证明 U-mode 取指需要 U 权限，并比较 S-mode 对同一 U 页取指的 instruction page
fault；该拒绝路径不受 SUM 影响。

`scripts/run-soc-mmu-tlb-diff.sh` 在完整 SoC 运行独立 ISS 对照的 S-mode 程序：初始
load 填充 data TLB，程序通过已映射页表页重写目标 PTE，再执行按虚拟地址的
`SFENCE.VMA` 并验证 load 改为新物理页值；最后切换 `satp` 到第二套页表并验证指令、数据
翻译均切换到第三个值。三次不同的 load 值使遗漏 write-through、地址失效或 `satp`
失效的实现错误可分别观测。

运行入口：

```bash
./scripts/run-core-diff.sh
```
