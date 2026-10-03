# 里程碑与交付物

| 阶段 | 结果 | 进入条件 | 退出条件 |
|---|---|---|---|
| M0 | 工程骨架和规格 | 范围冻结、板卡资料初盘 | 文档、目录、构建约定齐全；UART/DDR 待测项登记 |
| M1 | RV64I+BRAM | ISS 可执行 | 指令和 trace 全部一致 |
| M2 | CSR/异常 | M1 通过 | 精确 trap 与 delegation 通过 |
| M3 | M/A | M2 通过 | 边界和随机测试通过 |
| M4 | cache/TLB/Sv39 | M3 通过 | 页表、权限、flush 通过 |
| M5 | UART/CLINT/PLIC/DDR | M4 通过 | SoC xsim 启动通过 |
| M6 | FPGA bring-up | 用户确认 `CONFIRM_SYNTH` | LED、UART、JTAG-AXI、DDR 实测通过 |
| M7 | Linux | M6 通过 | 进入 shell 并完成压力测试 |
| M8 | PCIe/XDMA | Linux 稳定 | 主机 warm reboot 后链路和 DMA 实测通过 |

每个里程碑交付 RTL、testbench、ISS/differential 结果、覆盖率、脚本、波形/日志和已知限制。

当前 M4 已满足退出条件：独立 `rv64_mmu` Sv39 walker、小型 TLB 及 xsim 回归，并已完成双 MMU
接入 BRAM SoC 的 Sv39 取指/数据集成回归。直映 write-through/no-write-allocate 数据
cache 已接入 BRAM 数据路径，有独立回归及 bare-mode RTL↔ISS differential。基础 Sv39
配置、MRET、取指和数据访问已有 RTL↔ISS differential；无效取指页以及 execute-only 数据
页的 fetch/load/store page fault 已检查 `mepc`、`mcause`、`mtval` 和目标特权级；S-mode
对 U 页的 `SUM=0/1` data access 已有 differential，execute-only 页的 `MXR=0/1` load 权限、A/D 自动写回和 M-mode `MPRV/MPP` 数据权限已有回归；U-mode 对 U/S 页的 fetch/load 权限
以及 S-mode 对 U 页取指拒绝已覆盖。核心和 BRAM SoC 已有固定 seed 的结构化随机 RV64IMA 算术/访存 differential；
新增固定 seed 的 `mmu_random` 回归覆盖 TLB 命中/失配、`SFENCE.VMA`、`satp` 切换、超页和 fault，
并输出覆盖率摘要。DDR3 模型路径和独立 MIG 原子端点均已有 LR/SC/AMO read-modify-write
回归；完整 SoC TLB differential 已覆盖 PTE write-through、按地址 `SFENCE.VMA` 和 `satp`
切换。最终 SoC MIG top-level 接入仍是后续缺口。

M5 的 DDR3 路径已有 CPU-side/MIG-side contract、行为模型、cache/fault xsim 验收项和高地址
SoC RTL↔ISS differential，也已
固定可审计的 C0 MIG 配置输入与生成配方。实际 MIG IP、CDC/AXI wrapper、SoC 顶层约束、
校准和板级压力测试仍不存在。因此 M5 的行为模型增量已通过回归，但 M5 硬件退出条件仍未满足。

当前已生成并检查 C0 `mig_7series` IP，并加入 `rv64_mig_soc_top` 及已知时钟/LED 约束；
顶层已通过 Vivado `xvlog`/`xelab` 结构展开（含 Xilinx 仿真库）。这证明端口和模块可展开，
不证明综合时序、DDR3 校准或板级运行。UART 管脚仍待确认，综合门仍保持关闭。

用户已于 2026-09-15 提供 `CONFIRM_SYNTH`。Vivado 2026.1 已完成 C0 MIG OOC 和
`rv64_mig_soc_top` 的综合，二者均为 0 error / 0 critical warning；综合顶层使用
48,279 LUT、18,321 FF 和 51 DSP。产物位于 `build/vivado-synth`，包括 checkpoint、
资源、时序、时钟交互和 DRC 报告。该结果不允许进入 implementation：综合态 WNS 为
`-100.642 ns`、TNS 为 `-198623.875 ns`，并有 `LUTLP-1` 组合环；MIG 的 `sys_clk_p`
域还有一项 `-0.006 ns` hold 违例。`reset`、`uart_rx` 和 `uart_tx` 仍触发 `NSTD-1` /
`UCIO-1`，没有位置或电气标准。未运行 implementation、`write_bitstream`、JTAG 或 flash。

`soc_ddr3_external` 已新增并通过延迟外部事务端点回归，确认 SoC 的写穿、读 miss refill
和后续 cache hit 使用外部返回数据；该结果仍不替代 MIG 校准、时序和板级压力证据。

新增的 `soc_ddr3_mmu` 回归验证了 DDR3-backed Sv39 页表读取及 A/D 写回，但仍属于行为模型
证据，不改变 M5 尚未完成的硬件状态。

`soc_linux_handoff` 回归已证明 ROM 可以在 DDR3 行为模型中跳转并执行预加载 payload，
同时保留 RISC-V `a0/a1` 启动参数；这推进了 Linux 启动链，但尚未构成 OpenSBI 或 Linux
内核启动证据。

## 当前状态摘要（2026-09-26）

以上段落按时间顺序保留；以本节为准。

- M5 硬件：CH0 MIG 修正 `sys_rst` 极性后，板级校准完成，256-word 读写诊断通过（2026-09-16）。
  `rv64_mig_soc_top` 经过多轮实现，时序全部收敛（CSR mask 版本 WNS `0.057 ns`，WHS `0.053 ns`）。BPI Flash
  冷启动配置已验证。UART 管脚仍未确认，因此 M5 的 UART 项和板级长时间 DDR3 压力测试仍未完成。
- M6：JTAG 识别、JTAG-AXI loader、完整 payload 装载与抽样校验，以及 ILA 调试通道均已在板上实测通过。
  LED 参考映像的观察结果仍待用户反馈。
- M7：Linux 已在板上进入 S-mode Sv39，并运行到 `kernel_init_freeable` 中的 `workqueue_init()`，
  但尚未观察到用户态入口 `PC=0x100b0`，因此未通过。
  最新发现：`mip` 的整字写入会把 CLINT 的硬件 MTIP 锁存为软件 pending 位，RTL 已修复并有 xsim 回归，
  已重建并在 SRAM 上板复测，用户态和 `workqueue_init()` 返回触发均未命中，故该修复没有解决启动阻塞。
  2026-09-26 后续 JTAG 读取确认 CPU0 clockevent 已初始化，处于 ONESHOT 状态，下一事件为 4 ms。
  修复了 Windows Tcl 32 位有符号解析导致的诊断地址错误，Linux tclsh 与 Windows Vivado 测试均通过。
  当前源码树为 7.3-rc3，板上归档 payload 为 6.12，须按归档二进制和 v6.12 结构解释现场。
  详见 [Linux 启动与验收](../bringup/linux-acceptance.md) 末节。
- 2026-09-27：板上诊断已确认未实现 CSR 不产生异常，导致 OpenSBI 误报 `SSTC=1`、`SMAIA=1`。
  有限 SBI timer 请求到达但绕过 CLINT 写入，故没有定时器中断记录。CSR 实现范围检查已修复，
  40 个缺失 CSR 检查与 7 项相关回归通过；修复版 routed WNS `0.148 ns`、WHS `0.044 ns`，DRC 无错误。
  原始 payload 完整装载校验通过；修复版已越过 workqueue 停点，并完成耗时约 179 秒的
  `jent_mod_init`。随后在 `xor_8regs_2+0x14` 读取 `ffffffd601a80000` 时触发页故障，
  PID 1 退出并 panic。保留页表显示该地址具有有效内核 R/W/A/D 映射；独立 XOR 仿真通过，
  新故障尚未定位，正在重新加载以捕获故障前后执行记录。仍未观察到用户态入口。
- 正常 BusyBox 镜像已独立构建并检查 initramfs 内容，包含 `/proc`、定时等待与子进程执行检查。
  首次上板已通过 XOR 校准与后续 initcall，达到 `Run /init as init process`，但没有用户态自检标记。
  原先 XOR-PC 捕获在该镜像下命中的是 MTIP，不是页故障，已收紧故障触发条件。
  已修复 initramfs 缺少初始 `/dev/console`、`/dev/null` 的问题并独立构建、验证最终镜像内容。
  MMU 观测版时序通过（WNS 0.035 ns、WHS 0.039 ns），已捕获 BusyBox 在 U-mode 提交入口 `0x10144`，但后续自检未完成。
- 下一步：定位正常镜像在 init exec 路径中的停点，验证 BusyBox 自检和实际 Linux 功能。
  先捕获运行态，再 re-arm 读取 DDR；re-arm 会复位 CSR/CLINT，不能用复位后的值推断此前状态。
  既有 `CONFIRM_SYNTH CONFIRM_FLASH` 授权已从原始对话确认；最新 CSR mask 版本尚未写入 Flash。

- 2026-09-27 深夜：确认页表 A/D 写回应答会被同一 MMU 的下一次读取误用。
  旧 RTL 在有效跨页映射上复现 cause 12/13；读应答排除写事务后，两条路径均通过。
  新增 `soc_pte_write` 回归，另三项 MMU/用户态/handoff 回归通过。修复位流正在构建，
  尚不能认定它解决了 Linux 停点；板上正用补齐 console/null 的镜像做对照启动。

- 2026-09-28：PTE 修复位流完成，WNS 0.029 ns、WHS 0.050 ns、DRC 无错误。
  对照镜像已确认 PID 1 主动 exit(2) 后 panic；QEMU 复现其 BusyBox 实际只有 sh。
  原因为生成配置头时间戳领先，编译沿用旧配置。已强制刷新并校验 applet 清单；
  新 BusyBox 的解析、读取、睡眠和 fork/exec/wait 检查通过，最终镜像内容验证通过。
  正在以修复 RTL + 新镜像上板验收，尚无板上 USERSPACE_CHECK_PASS。

## 最新 Linux 验收结果（2026-09-30）

- SC/AMO 页故障误报 cause 13 已修复为 cause 15，LR 仍为 cause 13。
  旧核在新增 22 项中失败 20 项，修复后全部通过，另三项相关回归通过。
- 新位流 WNS 0.158 ns、WHS 0.036 ns，DRC 无错误，已在 SRAM 上板。
- 正常 BusyBox 镜像在实板输出
  `RV64FPGA USERSPACE_CHECK_PASS proc sysfs tmpfs sleep fork exec wait`。
  已验证文件系统挂载、定时器前进、tmpfs 读写和四轮子进程执行/等待。
  保存的 printk 中未发现 panic 或自检失败。M7 的 Linux 用户态启动与功能自检已通过。
- 读取验收日志会复位并保持 CPU；正在重新完整装载并启动，使板卡恢复运行。
  证据与哈希见 [Linux 启动与验收](../bringup/linux-acceptance.md) 末节。
  最新修复尚未写入 Flash；物理 UART 输入和长期稳定性仍未验证。

- 2026-09-30 16:45（Vivado 时间）：最终干净重启已完成。24,028,232 字节完整装载、
  回读与最终抽样校验通过；再次捕获 U-mode 入口 `0x10144`，数分钟后的快照显示
  时间更新、高精度定时器处理及下一事件计算。CPU 已保持运行，未再次复位读取日志。
  用户态完整自检标记来自相同位流/镜像的首轮实板验收。


## 工程收尾（2026-09-30）

- 主 RTL/约束/IP 配置对齐成功位流输入，建立文件 SHA-256 基线；主顶层恢复为成功 MMU ILA 布局。
- 源码、脚本、测试、IP 配置和软件输入统一纳入 Git，生成物忽略；shell 执行权限补齐。
- 本机工具、外部板卡配置和归档产物依赖明确列于 `local-dependencies.md`。
- 正式构建/验收入口见 `../bringup/maintained-workflow.md`，不再依赖 build 下的临时编排脚本。
- 本次验证：46 项 Python 测试通过，core_atomic/soc_pte_write xsim 回归通过，
  PowerShell 语法检查、实际 Vivado 包装入口参数传递、Tcl 符号解析和地址测试通过；
  历史首次自检及最终运行快照通过正式校验器重放，源码/产物哈希预检通过。
- 未重新综合或重跑整套实板装载；未进一步锁定工具包版本，未做干净环境重建。

## 2026-10-02：JTAG 字符通道实现

独立字符寄存器、双向 FIFO、UART 连接、主机终端和随机标记 smoke 入口已实现。
主机侧 mock 测试通过；Windows interop 被当前受限环境阻止，新增 RTL 仿真、综合和
实板交互尚未验证。旧成功基线不变，未下载新位流。见 `../bringup/jtag-console.md`。

- 2026-10-02 后续：Windows PowerShell 7.6.4 调用恢复。Vivado 2026.1 xsim 的
  jtag_console、jtag_axi_loader、uart、uart_rx、soc_uart_irq 五项回归全部通过，
  日志位于 `build/jtag-console-check-20261002/`；尚未综合/下载新的字符通道位流。


## 2026-10-03：JTAG 交互验收通过

- 新位流 WNS 0.085 ns、WHS 0.045 ns，JTAG 字符通道已在实板提供 BusyBox shell。
- 从实板 ILA 和直接读写定位启动故障：未初始化 DDR 的 ECC 导致总线读错误，
  经 CPU 现有故障接口表现为 cause 13。全 512 MiB 初始化现已纳入正式装载流程。
- 用户态入口、shell 的 proc/sysfs/tmpfs/sleep/四次子进程自检及断开重连均通过。
- 初始化程序正常/写错误两条 xsim 路径通过，53 项 Python 测试通过。
- 新成功清单 `verification/jtag-console-pass-20261003.json` 保留源码和产物身份；
  旧成功清单不变。证据：`build/jtag-console-scrub-board-20261003/`。
