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
每行包含 `pc`、`instruction`、`next_pc`、`rd` 和 `rd_value`；比较器在第一个不同提交
或长度不一致处失败。该工具不导入 RTL 包或解码表，后续 CPU testbench 可直接导出同一
格式接入门禁。

`rv64_core` 当前是单周期顺序执行原型，先用于验证架构状态和 BRAM 事务；它不是最终
的三级流水线实现。三级流水线将在该提交契约稳定后替换，避免将内部时序差异混入
differential 判定。

`scripts/run-core-diff.sh` 已将核心 smoke program 接入完整流程：xsim testbench 导出
`build/xsim/core/rtl_trace.jsonl`，独立 ISS 生成 `iss_trace.jsonl`，再由比较器逐条检查
`pc`、指令、下一 PC、目的寄存器和写回值。该 trace 目前不包含 CSR/trap 字段；这些
字段会在 CSR 实现进入核心后加入格式并保持向后不兼容地升级。

运行入口：

```bash
./scripts/run-core-diff.sh
```
