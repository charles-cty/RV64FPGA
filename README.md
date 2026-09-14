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

## 当前状态

仓库已完成文档和 Git 初始化；尚未开始 RTL、仿真工程或 Vivado 综合。任何综合、实现、下载和 flash 编程都必须先满足上板前确认门。
