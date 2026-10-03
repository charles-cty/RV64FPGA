# 本机依赖清单

本页明确列出当前构建、测试和实板验收所需依赖。暂不锁定容器 digest、
APT 包版本，也不宣称已完成全新机器验证。

| 依赖 | 用途及当前约定 |
|---|---|
| Windows + WSL2，启用 Windows interop | Linux 构建在 WSL；Vivado/JTAG 在 Windows。工程放在 Windows 本地盘，当前 `C:\My\Projects\RV64FPGA` |
| PowerShell 7.4+ | `pwsh.exe` 在 WSL PATH 中；当前实测 7.6.4 |
| Vivado 2026.1，支持 xc7k480tffg1156-2 的许可 | 当前 `C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat`；新构建/验收入口可传 Vivado 路径 |
| Vivado hw_server、Digilent USB/JTAG 驱动 | 已供电 YPCB-00338-1P1；当前探针序列号 `210251A08870`。验收期间仅连接目标板，禁止其他程序同时访问 JTAG |
| 原始板卡 MIG 配置 | 当前 `C:\My\Projects\FPGA\LC480T\vivado 板卡文件\ypcb_00338_1p1_hack-main\ypcb003381p1\1.0\mig_0.prj`；以 `-BoardConfig` 显式传入 |
| MIG 配置身份 | SHA-256 `baed6883dac282367f835cd71dd312d307bd0efbc786cf6f4a2a5a0909c4e23c`，脚本强制检查；不要替换为其他通道或近似配置 |
| WSL Bash、Git、GNU Make/coreutils、Python ≥3.12、uv、tclsh | 构建入口、Python 测试、Tcl 地址测试；`uv.lock` 已存在 |
| WSL clang-18、llvm-objcopy-18 | boot ROM 构建；可用 `RISCV_CLANG` / `LLVM_OBJCOPY` 覆盖 |
| WSL Podman 及容器构建/运行权限 | `make linux-stack`；需要拉镜像、访问 Debian 包源和上游 Git。`make ddr-scrub-image` 复用该 builder 镜像中的 RISC-V GCC/binutils，为实板装载构建 ECC 初始化程序 |
| 容器工具链 | `containers/linux-builder/Containerfile` 列出完整包清单，含两套 RISC-V GCC、dtc、make、Python、内核构建依赖；当前 Debian bookworm-slim，版本未进一步锁定 |
| 上游源码 | `scripts/fetch-linux-sources.sh` 固定 Linux 6.12、OpenSBI 1.6、BusyBox 1.36.1、musl 1.2.5 的 commit；默认缓存 `$HOME/.cache/rv64fpga/sources`，可传 `RV64FPGA_SOURCE_ROOT` |
| 构建缓存 | 默认 `$HOME/.cache/rv64fpga/build/linux`，可传 `RV64FPGA_LINUX_BUILD_ROOT`；输出发布到仓库 `build/linux/` |
| 已验收产物（重放基线验收时需要） | manifest 内列明本地 bit/ltx/boot ROM/payload/System.map/config/BusyBox 路径及 SHA-256。产物不放入 Git，须另外保留；源码检查不要求它们存在 |

QEMU 是之前 BusyBox 主机侧诊断用的可选工具，不是当前实板验收入口的依赖。
实体 UART 输入尚未接通；JTAG 终端通过 Windows Vivado 提供交互。Linux 配置禁用网络，验收不依赖实体串口接收、SSH 或 PCIe 主机。
