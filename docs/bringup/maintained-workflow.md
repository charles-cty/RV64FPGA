# 构建与 Linux 验收入口

## 基线与范围

当前已验收基线为 `verification/jtag-console-pass-20261003.json`，包含 JTAG 字符通道、
匹配 bit/ltx、原成功 Linux 软件和 DDR ECC 初始化程序；实板 shell 自检及重连通过。
`verification/linux-userspace-pass-20260930.json` 保留为历史基线，当前源码与其不一致。
文件级 SHA-256 用于防止误把修改后的源码称作该位流的输入。
不承诺不同工具版本生成相同 bitstream，不宣称完成了干净环境重建。

```bash
python3 tools/check_linux_baseline.py             # 仅源码/IP，与机器无关
python3 tools/check_linux_baseline.py --artifacts # 再核对本地成功产物
uv run python -m unittest discover -s tests
./scripts/run-m4-regression.sh  # 包含 core_atomic / core_privilege
./scripts/run-m5-model-regression.sh # 包含 soc_pte_write
```

关键缺陷：未实现 CSR 必须报非法指令；PTE 写回应答不可完成读请求；
SC/AMO 页故障必须为 cause 15，LR 为 cause 13。维护相关 RTL 时必须运行这些回归。

## 构建

先满足 [本机依赖](../project/local-dependencies.md)。在仓库根目录执行：

```bash
make boot-image
make linux-stack
make ddr-scrub-image
pwsh.exe -WorkingDirectory 'C:\Windows\Temp' \
  -File "$(wslpath -w "$PWD/scripts/build-rv64-bitstream.ps1")" \
  -SourceRoot "$(wslpath -w "$PWD")" \
  -OutputRoot "$(wslpath -w "$PWD/build/hardware")" \
  -BoardConfig 'C:\My\Projects\FPGA\LC480T\vivado 板卡文件\ypcb_00338_1p1_hack-main\ypcb003381p1\1.0\mig_0.prj'
```

硬件入口从主源码综合、实现，检查时序，再写 bit/ltx/mcs；不下载、不写 Flash。
IP 输入纳入 Git，派生产物由 Vivado 生成。外部 MIG 配置必须显式传入且哈希匹配。
正常 Linux 镜像使用 BusyBox `/init`；`RV64FPGA_MINIMAL_INIT=1` 仅用于诊断。

### BusyBox 常用命令

当前构建已扩展为 401 个命令，完整配置、例外和自检入口见
[BusyBox 命令集](busybox.md)。下述 17 项记录对应此前的精简版实板验收。
401 命令版本也已通过实板自检，当前软件验收清单为
`verification/busybox-full-pass-20261004.json`；旧软件记录重放前需匹配其归档源码。

正常构建保留 `sh、mount、sleep、cat`，并包含
`ls、pwd、mkdir、rm、cp、mv、echo、ps、uname、dmesg、free、df、du、head、tail、grep、stty`。
命令由 BusyBox 提供，安装到 `/bin` 或 `/usr/bin`，已包含在 `/init` 的 PATH 中。
支持 `ls -la`、`ls -R`、`df -h`、`du -sh`、`head -n N`、`tail -n N` 等常用选项；
`free` 使用精简版默认输出。`ps` 和 `free` 依赖已挂载的 `/proc`，
`stty` 可用 `stty -F /dev/ttyS0 -g` 读取可恢复的终端设置；`-a` 的窗口尺寸查询
可能产生提示，终端属性读取、修改和恢复已通过实板检查。

执行 `make linux-stack` 后，新镜像为 `build/linux/rv64fpga-fw_payload.bin`；
`busybox.config`、`busybox.links` 和 `SHA256SUMS` 同目录发布。
构建检查全部必需命令的安装清单，缺失时失败。裸机 GCC 通过 musl 构建 Linux
用户态时显式定义 `__linux__`，使 `free` 等命令包含正确的 Linux 接口头文件。

本次构建已完成，并核对 BusyBox 及全部命令链接进入 initramfs、initramfs 进入
Image、Image 进入 OpenSBI payload。BusyBox SHA-256 为
`1e35387629c7a1b8d0e2fac132cf732915a531bc24383f1a9c4ea29412d805d9`。
QEMU user-mode 下上述新增命令中 16 项功能检查通过，包含伪终端上的 `stty` 读取及修改；
`dmesg` 的 `klogctl` 在 QEMU 中返回 `Invalid argument`。
本地检查结果为 `build/busybox-tools-check.json`。

2026-10-04 新镜像实板验收通过：完整 DDR 初始化、装载回读、U-mode 入口、原 shell
自检、断开重连及全部 17 个命令均通过；`dmesg` 读到了内核的 `USERSPACE_CHECK_PASS`。
`stty` 在 `/dev/ttyS0` 上关闭回显、读回确认及恢复原配置通过。Linux 留在运行状态，
Flash 未写入。软件归档为 `build/linux-tools-20261004/`，独立成功清单为
`verification/busybox-tools-pass-20261004.json`。重放命令如下：

```bash
python3 tools/check_linux_baseline.py --manifest verification/busybox-tools-pass-20261004.json --artifacts
python3 -u tools/run_jtag_console_acceptance.py \
  --manifest verification/busybox-tools-pass-20261004.json --output build/busybox-tools-replay --run
```

该入口重放启动与 shell 基础验收；逐命令及 stty 验证脚本、输入输出与哈希记录在
新清单的 `evidence` 中。默认基线仍指向原归档镜像，重放旧基线不会自动装载新命令。

## JTAG 字符终端验收（推荐）

```bash
python3 tools/check_linux_baseline.py --artifacts
python3 tools/run_jtag_console_acceptance.py \
  --manifest verification/jtag-console-pass-20261003.json --output build/jtag-acceptance-new
# 加 --run 执行 SRAM 编程、全 DDR 初始化、装载、shell 自检和断开重连。
```

详见 [JTAG 字符终端](jtag-console.md)。`make ddr-scrub-image` 生成装载前必需的
初始化程序；全 DDR 写入、完成指令捕获和读回抽查均通过后才开始装载 Linux。
单独调用 `load-rv64-linux-jtag.tcl` 也执行此步骤；第五参数可显式指定 scrub binary。

## 已验收镜像的自动实板验收

默认只做预检，不访问硬件；`--run` 才会重新配置 FPGA SRAM、复位 CPU 和装载 DDR。
当前默认 manifest 对应已成功运行的本地归档，绝不自动换用 `build/linux` 的最新输出。

```bash
python3 tools/run_linux_acceptance.py
python3 -u tools/run_linux_acceptance.py --run --output build/acceptance-new
```

流程：检查源码与全部产物哈希 → 编程 SRAM → 全 DDR ECC 初始化 → 完整装载/回读 → 从 BusyBox ELF
取得 U-mode 入口并捕获 → 运行快照 → 保持 CPU 复位并读取 printk → 验证完整
`USERSPACE_CHECK_PASS` 且无失败/panic → 再次干净装载/启动 → 检查运行轨迹 → 留 CPU 运行。
预计数十分钟，逐阶段日志和 `result.json` 写入新目录，拒绝覆盖旧目录。
失败返回非零；读取日志后的自检失败会保留 CPU 复位现场。其他阶段失败时查看对应日志，
不要假定 CPU 状态。脚本没有自动后台守护；若终端被关闭，先检查实际进程和日志再重试。

诊断地址取自匹配 `System.map`，缓冲区大小取自 `CONFIG_LOG_BUF_SHIFT`。
目前支持本平台 Linux 6.12 静态 printk 环形缓冲区与固定内核加载地址。
更换内核布局/动态 printk 配置需重新检查这些假设。ASCII 提取用于检测确切自检标记，
不是完整 printk 记录解析；尾部重复字节不能解释为新的消息。
ILA 快照只证明观察窗口内执行，不能证明长期稳定。

重放历史验收证据（不访问硬件）：

```bash
python3 tools/verify_linux_acceptance.py build/atomic-fault-boot-20260930 \
  --symbols build/linux-applets-20260928/System.map
```

新的镜像应建立新的 manifest，保留旧基线。更新产物路径/哈希、对应源码哈希及证据，
运行新验收后再标记成功，禁止只更新哈希就宣称通过。全套产物路径键见基线 JSON。

## 版本控制与维护

源码、约束、IP customization、容器配方、脚本、测试、文档和小型验收清单进入 Git。
`build/`、Vivado 派生 IP、二进制和日志不进入 Git；归档另外保管。
每次改动记录修复原因、针对性回归及硬件证据；文档当前状态放 README，
历史故障过程保留在 `linux-acceptance.md`，使用本页的正式命令代替历史临时命令。

用户态通过标记来自首轮读出的 printk；读取会复位 CPU。第二轮负责证明干净重启和
持续执行，避免为了再读取日志而永远循环复位。验收终态为运行，Flash 未修改。
