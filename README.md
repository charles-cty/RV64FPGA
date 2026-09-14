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
```

`run-xsim.sh` 只会调用 Vivado xsim：它把所需文件复制到 Windows 本地临时目录后执行
`xvlog`、`xelab`、`xsim`，并检查日志中的 `SIM PASS`。它不会运行综合、实现、下载或
flash 编程。

可用的 xsim 回归名为 `alu`、`decoder`、`regfile` 和 `imm`。

## 当前状态

M0 工程骨架和首个 M1 增量已建立：RTL ALU、独立 Python ISS、ISS 单元测试和 xsim
ALU 回归均已纳入版本控制。CPU 流水线、存储器、CSR/MMU、DDR3 及板级工程尚未实现。
任何综合、实现、下载和 flash 编程都必须先满足上板前确认门。
