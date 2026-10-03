# JTAG 字符终端（实板验收通过）

## 状态与结构

2026-10-02：Windows interop 已恢复，Vivado 2026.1 xsim 的 `jtag_console`、
`jtag_axi_loader`、`uart`、`uart_rx`、`soc_uart_irq` 五项回归全部通过。
日志保存在 `build/jtag-console-check-20261002/`。主机侧 53 项 Python 测试已通过。
新位流综合/实现已完成（WNS 0.085 ns、WHS 0.045 ns），已下载到 SRAM，
2026-10-03 已通过实板 shell 自检与断开重连。2026-09-30 成功位流不包含此通道。
当前基线为 `verification/jtag-console-pass-20261003.json`，旧成功基线保留原值。

2026-10-03 诊断：新位流的完整 payload 装载/读回通过，JTAG 终端确实读取了
4096 字节启动输出，但 shell 自检超时。保留 printk 显示内核在
`xor_8regs_2+0x14` 对 `ffffffd601a80000` 发生 cause 13 页故障，随后 PID 1
退出并 panic；不能将定时器路径仍在执行解释为启动成功。复位保留 DDR 后读取的
页表包含合法叶项 `0x206800e7`。
证据：`build/jtag-console-board-20261002/{manual-selftest.log,state/}`、
`build/jtag-console-debug-20261003/walk.log`。诊断复位后须完整重载软件再启动。

同日重现的 ILA 在采样 3071、4004 显示翻译成功、`buserr=1`。MIG 启用 ECC；
对 PA `81a80000`、`81a83000` 的直接 JTAG 读取也返回 SLVERR，写满所在 64 字节
后读取成功（`ecc-check.log`）。启动流程原先只初始化镜像及 DTB 工作区，不能保证
Linux 新分配内存的 ECC 有效。加入全 DDR 初始化后，同一位流与 Linux 镜像通过完整实板验收。

装载前先执行 `make ddr-scrub-image`（使用已有 Linux builder 容器）。正式装载脚本
先写入并校验 64 KiB 初始化程序区，再由 M-mode 程序写零其余 DDR，覆盖总计
512 MiB。捕获完成 PC 并抽查通过后，重新保持 CPU 复位，再装载 Linux；失败不会
进入 Linux 装载阶段。无需重新生成 FPGA 位流。`ddr_scrub` xsim 覆盖完整写序列及
总线写错误不能报告成功；主机模拟测试覆盖初始化未完成时停止装载。

```text
Windows PowerShell / WSL 终端 → 文件队列 → Windows Vivado 持久 Tcl → JTAG AXI
                                                  ↓
                                 独立字符寄存器 / RX、TX FIFO
                                                  ↓
                         原有 16550 MMIO → ttyS0 → BusyBox sh
```

无新增 FPGA 管脚，无 Linux 驱动或设备树修改。顶层启用 `JTAG_CONSOLE=1`；普通
UART/SoC 仿真默认仍使用实体串行收发。原串行 TX 继续用于 ILA 观察。
字符访问不使用 DDR 通路、不写 loader 控制，不复位 CPU。

## Windows 原生 PowerShell 连接（无需 WSL）

在 Windows PowerShell 7.4+ 中执行：

```powershell
Set-Location C:\My\Projects\RV64FPGA
.\scripts\jtag-terminal.ps1
```

默认使用已验收位流对应的 `.ltx`，并自动建立带时间戳的 session 目录。
需要指定另一份匹配的探针文件时使用 `-Probes 'C:\path\rv64_mig_soc_top.ltx'`。
连接后按回车，输入 `cat /proc/uptime` 等 Linux 命令。`Ctrl-]` 断开连接并保持
Linux 运行；`Ctrl-C` 发送给 Linux。该入口只调用 Windows PowerShell 和 Vivado，
不调用 `wsl.exe`、`wslpath` 或 Python。日志和原始字节保存在输出的 session 目录。

非交互实板检查：`.\scripts\jtag-terminal.ps1 -Smoke`，要求 shell 返回完整随机标记。
原生键盘输入使用 Windows Console API；需要 Windows Terminal 等真正的交互终端。

## 寄存器协议 v1

基址 `0x7ffffe00`，与 loader 控制 `0x7fffff00` 分离。
只支持对齐、32 位、单拍 INCR 事务；写需 `WSTRB=0xf`、`WLAST=1`。
无效访问返回 SLVERR，不修改 FIFO。读应答被阻塞时不会重复弹出字节。

| 偏移 | 读 | 写 |
|---|---|---|
| `00` | `0x4a544331`（JTC1） | 禁止 |
| `04` | RX 可写字节数（CPU 复位时为 0） | 禁止 |
| `08` | TX 待读字节数 | 禁止 |
| `0c` | 弹出一个 TX 字节；bit31=有效，低 8 位=字节；空队列返回 0 | 低 8 位入 RX 队列；满/CPU 复位返回 SLVERR |
| `10` | 离线丢弃的 TX 字节数，32 位饱和计数 | 禁止 |
| `14` | bit0：主机已连接 | 1=连接并启用 TX 背压；0=断开；其他值拒绝 |

RX 深度 256 字节，TX 深度 4096 字节；参数需为至少 2 的二次幂。
RX 满时主机按可写数量等待。连接时 TX 满会令 UART THRE 清零，Linux 等待主机读出。
无主机时不阻止 Linux 启动；TX 满则丢弃新输出并计数，终端显示累计丢失量。
默认 50 MHz 时钟下，5 秒无 JTAG 字符寄存器访问自动解除背压。
CPU 复位清空队列、连接状态和丢失计数，不保留跨启动输入。

Tcl 持久会话限制每轮发送 32 字节、读取 128 字节，通过文件心跳检测前端退出，
不使用 Windows/WSL 间可能有偏差的时钟值互相比较。终端异常退出后，后端在批次边界
检测心跳停止并断开；若后端本身停住，RTL 租约自动释放背压。任一时刻只允许一个
终端/Hardware Manager 会话访问目标板。

## 验证与构建

```bash
python3 -m unittest discover -s tests
./scripts/run-xsim.sh jtag_console
./scripts/run-xsim.sh jtag_axi_loader
./scripts/run-xsim.sh uart
./scripts/run-xsim.sh uart_rx
./scripts/run-xsim.sh soc_uart_irq
```

`jtag_console` 联合实例化 AXI loader、FIFO 和 UART，检查运行时访问、DDR 隔离、
非法事务、应答背压、输入顺序、DLAB、FIFO 满/空、输出背压、失联租约及复位清空。
Python/Tcl mock 测试验证主机协议和错误处理，不能替代 RTL 或实板验收。

按 [正式构建流程](maintained-workflow.md) 用主源码重新生成 bit/ltx。
完整 Linux 功能验收需要为新产物建立独立 manifest，禁止覆盖原成功基线。
沿用成功 payload 即可，不需要为字符通道重新编译 Linux。

先用现有 `program-jtag-bitstream.tcl` 编程 SRAM，`load-rv64-linux-jtag.tcl` 完整装载，
再以 `capture-rv64-linux-entry.tcl` 释放并捕获 U-mode 入口；这三步仍按正式流程执行。
CPU 保持复位时终端会拒绝连接，不会偷偷释放 CPU。关闭其他 Vivado 调试会话后连接：

```bash
python3 tools/jtag_terminal.py \
  --probes build/hardware/bitstream/rv64_mig_soc_top.ltx \
  --session build/terminal-001
```

在交互式 WSL 终端运行，session 必须是 Windows 盘上的新目录。等待连接成功，按回车
获取新提示符。`Ctrl-]` 退出本地主机程序；`Ctrl-C` 字节发送到 Linux，其终端信号行为
取决于控制终端配置，当前不承诺作业控制。输入/输出原始字节、Vivado 日志保存在 session。

一次性真实 shell 执行检查（非交互命令行亦可）：

```bash
python3 tools/jtag_terminal.py --smoke --timeout 120 \
  --probes build/hardware/bitstream/rv64_mig_soc_top.ltx \
  --session build/terminal-smoke-001
```

该命令生成随机 nonce，发送 `echo` 命令，只认可完整的 nonce 输出行，不能仅凭命令回显
判成功。成功输出 `JTAG_CONSOLE_SMOKE_PASS`，失败退出非零。首次上板还需验证
`cat /proc/uptime`、多行输入、断开重连，及完整 Linux 自检无回归；通过前不可称作交互已验收。

当前 BusyBox 仅含 sh/ash、cat、mount、sleep；没有 ls/stty，也未启用 ash 作业控制。
JTAG 字符通道针对低速 bring-up 使用，不作高吞吐串口或网络终端。


## 通过实际 shell 重跑用户态检查

`--selftest` 包含随机标记，并检查 `/proc/uptime` 随 sleep 前进、`/sys/kernel`、
`/tmp` 文件读写及四次子 shell 执行/等待。执行完保留原交互 shell。

```bash
python3 tools/jtag_terminal.py --selftest --timeout 180 \
  --probes build/jtag-console-hardware-20261002/bitstream/rv64_mig_soc_top.ltx \
  --session build/terminal-selftest-001
```

端到端自动入口（默认仅哈希预检，加 `--run` 才编程 SRAM）：

```bash
python3 -u tools/run_jtag_console_acceptance.py \
  --manifest verification/jtag-console-pass-20261003.json \
  --output build/jtag-console-new-run --run
```

执行编程 → 完整装载/校验 → U-mode 入口 → shell 功能自检 → 断开/重新连接并验证新随机标记。
成功后写 `result.json`，CPU 保持运行；不通过复位 CPU 读取 printk，避免破坏当前终端。
失败保留对应阶段日志，不宣称成功。候选 manifest 必须关联匹配的源码、bit/ltx 和软件产物。

## 实板证据（2026-10-03）

- `build/jtag-console-scrub-board-20261003/result.json`：`JTAG_CONSOLE_ACCEPTANCE_PASS`。
- `load.log`：512 MiB 初始化、镜像分块读回与最终抽样通过；`user.csv` 捕获 U-mode 入口。
- `selftest.log`：实际 shell 完成 proc/sysfs/tmpfs、sleep、四轮子进程检查并返回随机标记。
- `reconnect.log`：关闭后重新连接，新的随机标记得到正确响应。
- `build/jtag-console-interactive-20261003b/`：真实 PTY 连续输入 `cat /proc/uptime` 和 `echo JTAG_MULTILINE_20261003`，收到 uptime 与完整回显；`Ctrl-]` 正常退出，Linux 保持运行。
- SRAM 位流 SHA-256：`7de263a8d4056f2596e3cafdf2d99878e40226b12be2be92d4a20450a4aed61f`。

连接前的启动输出超过 4096 字节 FIFO 时会丢弃并计数；本次接入时记录 6957 字节已丢弃。
这不代表当前命令丢失。需要完整启动记录时使用保留 printk；常规终端操作不复位 CPU。
实体 UART RX、作业控制和长期稳定性仍不在本次通过范围，Flash 未写入。

### Windows 原生终端验证

`scripts/jtag-terminal.ps1` 已通过 Windows PowerShell 实板 `-Smoke` 检查。
Windows ConPTY（psmux 3.3.4）中连续输入 `cat /proc/uptime` 和
`echo NATIVE_PWSH_INTERACTIVE_PASS`，收到 uptime 与完整标记；`Ctrl-]` 正常退出。
证据：`build/native-pwsh-smoke-20261003.log`、
`build/native-pwsh-interactive-20261003/{input.bin,output.bin,pane.txt}`。
psmux 仅用于本次自动测试，日常使用无需安装。
