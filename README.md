# RV64FPGA

自研 RV64IMA FPGA SoC 项目，目标器件为 YPCB-00338-1P1（Xilinx Kintex-7 XC7K480T）。

本项目的硬件 CPU、互连和外设 RTL 均自行实现，不复制或集成开源 CPU/SoC RTL。Linux、GCC/binutils 和 OpenSBI 是否采用上游版本，见 [范围与决策](docs/project/scope-and-decisions.md)。

## 文档入口

- [项目范围与决策](docs/project/scope-and-decisions.md)
- [架构规格](docs/architecture/specification.md)
- [地址图与平台接口](docs/architecture/platform.md)
- [验证规范](docs/verification/verification-plan.md)
- [Differential testing 设计](docs/verification/differential-testing.md)
- [Vivado xsim 流程](docs/verification/xsim-flow.md)
- [FPGA bring-up 与用户确认门](docs/bringup/bringup-plan.md)
- [板卡资料盘点](docs/bringup/board-inventory.md)
- [LC480T 原始资料审计](docs/bringup/source-audit.md)
- [Linux 启动与验收](docs/bringup/linux-acceptance.md)
- [里程碑与交付物](docs/project/milestones.md)

## 开发入口

```bash
uv run python -m unittest discover -s tests
./scripts/run-xsim.sh alu
./scripts/run-core-diff.sh
./scripts/run-soc-cache-diff.sh
./scripts/run-soc-mmu-diff.sh
./scripts/run-soc-mmu-fault-diff.sh
./scripts/run-soc-mmu-sum-diff.sh
./scripts/run-soc-mmu-user-diff.sh
./scripts/run-m4-regression.sh
```

`run-xsim.sh` 只会调用 Vivado xsim：它把所需文件复制到 Windows 本地临时目录后执行
`xvlog`、`xelab`、`xsim`，并检查日志中的 `SIM PASS`。它不会运行综合、实现、下载或
flash 编程。

可用的 xsim 回归名为 `alu`、`decoder`、`regfile`、`imm`、`core`、`core_csr`、`core_atomic`、`core_alignment`、`soc`、`soc_uart`、`soc_irq`、`soc_mmu`、`soc_mmu_fault`、`soc_mmu_fault_diff`、`soc_mmu_sum_diff`、`soc_mmu_user_diff`、`soc_cache_diff`、`soc_mmu_diff`、`csr`、`atomic`、`cache`、`clint`、`plic`、`uart` 和 `mmu`。`run-core-diff.sh`
会在 `core` xsim 完成后生成独立 ISS 期望 trace，并运行 RTL↔ISS 比较器。

## 当前状态

M0 工程骨架和 M1/M2/M3/M5 基础增量已建立：RTL ALU、译码、寄存器堆、立即数生成器、单周期
CPU+BRAM 原型、独立 Python ISS、trace 比较器、CSR 单元以及已接入核心的原子访存路径
均已纳入版本控制，CLINT/PLIC/UART 已独立完成 xsim 回归，UART/LED 和 CLINT/PLIC
MMIO 已接入 BRAM SoC，timer trap 已通过 xsim。三级流水线、完整异常/delegation、
PLIC 外部源接线、DDR3 及板级工程尚未实现；双 MMU 与直映 write-through 数据 cache
已接入 BRAM SoC 并通过 xsim 集成回归，cacheable BRAM 数据路径已有 RTL↔ISS
differential；基础 Sv39/MMU 核心 differential 已覆盖；execute-only 数据页的 S-mode
fetch/load/store page fault 已有独立 Sv39 walker↔RTL 精确 trap differential，S-mode
SUM、U-mode 和 S-mode 对 U/S 页的权限边界已由 SoC differential 覆盖。
任何综合、实现、下载和 flash 编程都必须先满足上板前确认门。
