# 构建与 Linux 验收入口

## 基线与范围

已验收基线为 `verification/linux-userspace-pass-20260930.json`。
主 `rtl/`、约束和 IP 配置已与成功构建的冻结输入逐字节对齐，包括 MMU ILA 接线。
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
pwsh.exe -WorkingDirectory 'C:\Windows\Temp' \
  -File "$(wslpath -w "$PWD/scripts/build-rv64-bitstream.ps1")" \
  -SourceRoot "$(wslpath -w "$PWD")" \
  -OutputRoot "$(wslpath -w "$PWD/build/hardware")" \
  -BoardConfig 'C:\My\Projects\FPGA\LC480T\vivado 板卡文件\ypcb_00338_1p1_hack-main\ypcb003381p1\1.0\mig_0.prj'
```

硬件入口从主源码综合、实现，检查时序，再写 bit/ltx/mcs；不下载、不写 Flash。
IP 输入纳入 Git，派生产物由 Vivado 生成。外部 MIG 配置必须显式传入且哈希匹配。
正常 Linux 镜像使用 BusyBox `/init`；`RV64FPGA_MINIMAL_INIT=1` 仅用于诊断。

## 已验收镜像的自动实板验收

默认只做预检，不访问硬件；`--run` 才会重新配置 FPGA SRAM、复位 CPU 和装载 DDR。
当前默认 manifest 对应已成功运行的本地归档，绝不自动换用 `build/linux` 的最新输出。

```bash
python3 tools/run_linux_acceptance.py
python3 -u tools/run_linux_acceptance.py --run --output build/acceptance-new
```

流程：检查源码与全部产物哈希 → 编程 SRAM → 完整装载/回读 → 从 BusyBox ELF
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
