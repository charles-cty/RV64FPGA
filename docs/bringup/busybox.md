# BusyBox 命令集

构建使用固定 BusyBox 1.36.1 的 `defconfig` 为基础，完整配置保存在
[`sw/linux/busybox.config`](../../sw/linux/busybox.config)，
全部 401 个命令入口保存在 [`sw/linux/busybox.applets`](../../sw/linux/busybox.applets)。
`make linux-stack` 校验整份安装清单；缺失或意外新增命令均使构建失败。

## 配置与兼容性

相对上游默认配置，启用 `CONFIG_STATIC`，关闭 `CONFIG_TC` 及其从属
`CONFIG_FEATURE_TC_INGRESS`。`tc` 是本次唯一因编译不兼容而跳过的默认命令：
BusyBox 1.36.1 的实现引用 CBQ 类型，而 Linux 6.12 导出的头文件已经没有这些定义。
保留上游默认关闭的 PAM、SELinux 等特殊配置，不使用 `allyesconfig`。

继续使用 `-march=rv64ima -mabi=lp64`、musl 静态链接及 `__linux__` 定义，
不依赖目标板上的动态库，不引入 C/F/D 指令扩展。最终指令属性须随构建核对。

## 编入不等于运行条件齐全

- 文件、文本、压缩、校验、编辑及进程工具整体保留，例如 `find`、`sed`、`awk`、
  `tar`、`gzip`、`bzip2`、`xz`（解压）、`sha256sum`、`vi`、`top`。
- 网络工具也已编入，但当前内核 `CONFIG_NET=n`，不能据此使用网络通信。
- `insmod/modprobe` 及命名空间相关操作仍受 `CONFIG_MODULES=n`、
  `CONFIG_NAMESPACES=n` 限制。
- 磁盘、I²C、RTC、MTD 等命令需要对应设备和驱动；账户和服务类命令需要账户文件、
  配置目录或服务启动步骤。编入 `init`、`getty`、`crond` 等不会自动启动它们。
- `/init` 保持原有挂载、自检及交互 shell 流程；未将系统切换到 BusyBox init。
  新配置启用 shell 作业控制功能，但实板 shell 提示没有控制终端，作业控制仍关闭。
- 全命令 `--help` 检查仅证明入口可启动，不能替代逐项功能验收。

## 功能自检

镜像内提供显式运行的 `busybox-selftest`，不在启动时自动执行：

```sh
busybox --list
busybox-selftest
```

自检覆盖文件复制/移动/符号链接/查找，排序、去重、sed、浮点 awk、bc、xargs，
归档和 gzip/bzip2/xz 解压，base64、校验和、进程与内存查询；板上另检查
`dmesg` 中的启动自检标记，以及 `/dev/ttyS0` 回显设置的修改、读回与恢复。
测试数据仅放在独立 `/tmp/busybox-check.*` 目录，退出时清理。

主机上可用 QEMU user-mode 运行同一组功能检查（跳过板上日志和终端检查）：

```bash
BUSYBOX_TEST_RUNNER=/path/to/qemu-riscv64 \
BUSYBOX_TEST_BINARY="$PWD/build/linux/busybox" \
  bash sw/linux/busybox-selftest --host
```

这不是全部 401 个命令及其所有选项的功能验收，尤其不验证重启、格式化、挂载新设备、
网络及服务管理等操作。发布的 `busybox.config`、`busybox.links`、
`busybox-selftest` 与镜像一起记录在 `build/linux/SHA256SUMS` 中。

## 2026-10-04 实板结果

[`verification/busybox-full-pass-20261004.json`](../../verification/busybox-full-pass-20261004.json)
记录本次独立成功清单；软件归档为 `build/linux-full-20261004/`。
BusyBox 大小 2,115,704 字节，板上 SHA-256 与归档匹配，命令入口数为 401。
完整 DDR 初始化、镜像回读、U-mode 入口、基础 shell 自检及断开重连均通过。
上面的六组扩展功能自检全部通过，包括 dmesg 及 stty 属性修改、读回和恢复。
主机侧全部入口/帮助检查和 53 项 Python 回归通过。

首次扩展检查超过主机 600 秒等待期限。随后重新连接，收到了保留输出中的全部
自检通过行、匹配的二进制哈希和原随机标记，并验证了新的重连随机标记。
此间没有复位或重新装载；超时日志与恢复输出均保留在清单中。
全文件 SHA-256 在当前软核上耗时较长，重跑此完整检查应增加等待时间。
验收终态为 Linux 运行，Flash 未修改。

```bash
python3 tools/check_linux_baseline.py --manifest verification/busybox-full-pass-20261004.json --artifacts
python3 -u tools/run_jtag_console_acceptance.py \
  --manifest verification/busybox-full-pass-20261004.json --output build/busybox-full-replay --run
```

自动入口重放基础启动验收；连接后运行 `busybox-selftest` 重跑扩展功能检查。
本记录证明上述测试范围，不宣称所有命令及选项都已逐一实板验收。
