# 项目概况

自研 RV64IMA FPGA SoC，目标板为 YPCB-00338-1P1（XC7K480T）。RTL 使用 SystemVerilog；Linux 软件在 WSL 构建，Vivado 2026.1 在 Windows 运行。
Linux 6.12、OpenSBI 1.6、BusyBox 已通过实板用户态自检；UART 输入与长期稳定性尚未验收。

## 文档导航

- [README](README.md)：项目入口与当前状态。
- [构建与验收流程](docs/bringup/maintained-workflow.md)、[本机依赖](docs/project/local-dependencies.md)：开发和上板的正式入口。
- [范围与决策](docs/project/scope-and-decisions.md)、[里程碑](docs/project/milestones.md)：目标与进展。
- [架构规格](docs/architecture/specification.md)、[平台地址图](docs/architecture/platform.md)、[DDR3 接口约定](docs/architecture/ddr3-memory-fabric.md)：硬件设计。
- [验证规范](docs/verification/verification-plan.md)、[xsim 流程](docs/verification/xsim-flow.md)、[差分测试](docs/verification/differential-testing.md)：测试入口。
- [Linux 验收记录](docs/bringup/linux-acceptance.md)、[ILA 布局](docs/architecture/ila-layout.md)：实板证据与调试；历史记录中的临时命令以正式流程为准。
- [板卡资料](docs/bringup/board-inventory.md)、[MIG 配置](docs/bringup/mig-ch0-recipe.md)：板级依赖。
- [成功基线清单](verification/linux-userspace-pass-20260930.json)：源码及产物哈希。
