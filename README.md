# RV64FPGA

自研 RV64IMA FPGA SoC 项目，目标器件为 YPCB-00338-1P1（Xilinx Kintex-7 XC7K480T）。

本项目的硬件 CPU、互连和外设 RTL 均自行实现，不复制或集成开源 CPU/SoC RTL。Linux、GCC/binutils 和 OpenSBI 是否采用上游版本，见 [范围与决策](docs/project/scope-and-decisions.md)。

## 文档入口

- [项目范围与决策](docs/project/scope-and-decisions.md)
- [架构规格](docs/architecture/specification.md)
- [地址图与平台接口](docs/architecture/platform.md)
- [DDR3 memory fabric contract](docs/architecture/ddr3-memory-fabric.md)
- [验证规范](docs/verification/verification-plan.md)
- [Differential testing 设计](docs/verification/differential-testing.md)
- [Vivado xsim 流程](docs/verification/xsim-flow.md)
- [FPGA bring-up 与用户确认门](docs/bringup/bringup-plan.md)
- [MIG C0 generation recipe](docs/bringup/mig-ch0-recipe.md)
- [板卡资料盘点](docs/bringup/board-inventory.md)
- [LC480T 原始资料审计](docs/bringup/source-audit.md)
- [Linux 启动与验收](docs/bringup/linux-acceptance.md)
- [里程碑与交付物](docs/project/milestones.md)

## 开发入口

```bash
uv run python -m unittest discover -s tests
./scripts/run-xsim.sh alu
./scripts/run-core-diff.sh
./scripts/run-core-random-diff.sh
./scripts/run-soc-random-diff.sh
./scripts/run-xsim.sh mmu_random
./scripts/run-xsim.sh uart_rx
./scripts/run-xsim.sh soc_uart_irq
./scripts/run-soc-cache-diff.sh
./scripts/run-soc-mmu-diff.sh
./scripts/run-soc-mmu-fault-diff.sh
./scripts/run-soc-mmu-sum-diff.sh
./scripts/run-soc-mmu-user-diff.sh
./scripts/run-soc-mmu-tlb-diff.sh
./scripts/run-soc-ddr3-diff.sh
./scripts/build-boot-image.sh
make jtag-smoke-image
./scripts/run-xsim.sh soc_jtag_smoke
./scripts/run-m4-regression.sh
./scripts/run-m5-model-regression.sh
make dts
make vivado-project-check
```

`run-xsim.sh` 只会调用 Vivado xsim：它把所需文件复制到 Windows 本地临时目录后执行
`xvlog`、`xelab`、`xsim`，并检查日志中的 `SIM PASS`。它不会运行综合、实现、下载或
flash 编程。

`make vivado-project-check` 只创建临时 Vivado 工程，导入顶层 RTL、XDC 和生成的 MIG
XCI，并更新编译顺序和顶层端口检查；它明确不调用综合、实现、bitstream、JTAG 或 flash。

可用的 xsim 回归名为 `alu`、`decoder`、`regfile`、`imm`、`core`、`core_random`、`core_csr`、`core_atomic`、`core_alignment`、`core_supervisor_irq`、`core_privilege`、`core_fence`、`soc`、`soc_random`、`soc_uart`、`soc_uart_irq`、`soc_irq`、`soc_sbi`、`soc_mmu`、`soc_mmu_fault`、`soc_mmu_fault_diff`、`soc_mmu_sum_diff`、`soc_mmu_user_diff`、`soc_mmu_tlb_diff`、`soc_cache_diff`、`soc_mmu_diff`、`soc_ddr3_model`、`soc_ddr3_mmu`、`soc_pte_write`、`soc_ddr3_fault`、`soc_ddr3_diff`、`soc_ddr3_instruction`、`soc_ddr3_atomic`、`soc_init_files`、`soc_boot_image`、`soc_jtag_smoke`、`ddr3_arbiter`、`ddr3_mig_shared_path`、`csr`、`atomic`、`cache`、`clint`、`plic`、`uart`、`uart_rx`、`mmu`、`mmu_random`、`ddr3_model`、`ddr3_axi_adapter`、`async_memory_bridge` 和 `ddr3_mig_path`。`run-core-diff.sh`
会在 `core` xsim 完成后生成独立 ISS 期望 trace，并运行 RTL↔ISS 比较器。

`ddr3_mig_atomic_path` 额外验证最终 MIG CDC/AXI 包装器上的 LR/SC/AMO 串行读-改-写。
`jtag_axi_loader` 验证 JTAG AXI loader 的 DDR3 32-bit lane 映射、MIG-ready 门控、AXI error
propagation、incrementing bursts and CPU-reset release rule.
`run-core-random-diff.sh` 使用固定 seed 生成结构化随机 RV64IMA 程序，运行独立 ISS 与 `core_random` xsim，再逐条比较 trace。
`run-soc-random-diff.sh` 将同一程序接入完整 BRAM SoC，覆盖 cache miss/hit、write-through 和原子访存后的提交 trace。
执行 `soc_boot_image` 前先运行 `scripts/build-boot-image.sh` 生成 boot ROM hex。
执行 `make linux-handoff` 可生成 ROM/DDR3 payload 镜像并运行 ROM→DDR3 handoff smoke test。

## 当前状态

Linux 6.12 + OpenSBI 1.6 + BusyBox 已在 XC7K480T 实板启动，并通过
`USERSPACE_CHECK_PASS proc sysfs tmpfs sleep fork exec wait`。干净重启再次进入
U-mode，后续捕获到正常定时器处理。最新位流仅在 SRAM，尚未写入 Flash。
实体 UART RX 尚未接通；JTAG 字符终端已于 2026-10-03 通过实板交互验收。
可在 Windows 原生 PowerShell 中运行 `.\scripts\jtag-terminal.ps1` 交互操作，
无需调用 WSL；shell 功能自检、多行输入和断开重连均通过。长期稳定性尚未验收。

新构建已补齐 BusyBox 常用文件、文本、系统状态和终端工具，详见
[命令清单与验证范围](docs/bringup/maintained-workflow.md#busybox-常用命令)。
2026-10-04 新软件镜像已上板，17 个新增命令、原 shell 自检及重连全部通过，
独立记录见 [BusyBox 工具实板验收](verification/busybox-tools-pass-20261004.json)。
当前构建进一步扩展为 401 个 BusyBox 命令，已通过实板哈希核对和扩展功能自检；
[完整命令集验收记录](verification/busybox-full-pass-20261004.json)。配置、自检及运行限制见
[完整 BusyBox 命令集](docs/bringup/busybox.md)。

[JTAG 字符终端使用说明](docs/bringup/jtag-console.md) 包含连接命令、限制及证据。
本次还修复了启动流程中 ECC 内存初始化不完整的问题：装载 Linux 前先初始化全部
512 MiB DDR，避免读取新分配内存时出现总线错误。

当前源码、位流及软件身份保存在
[当前成功基线](verification/jtag-console-pass-20261003.json)；
[2026-09-30 历史基线](verification/linux-userspace-pass-20260930.json) 保留不变。

- [正式构建、预检及实板验收](docs/bringup/maintained-workflow.md)
- [本机依赖清单](docs/project/local-dependencies.md)
- [历史实板证据](docs/bringup/linux-acceptance.md)

```bash
make check-linux-baseline
make test
# 仅预检本地成功产物，不触碰硬件
python3 tools/run_linux_acceptance.py
# 实际重新配置 SRAM、完整验收并留 Linux 运行
python3 -u tools/run_linux_acceptance.py --run --output build/acceptance-new
```

环境包版本进一步锁定、从干净环境完整重建暂未处理，不承诺位流二进制级可重复。
