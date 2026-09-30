# 平台接口与地址图（v0.1）

## 地址图

| 区域 | 起始地址 | 大小 | 说明 |
|---|---:|---:|---|
| Boot ROM | `0x0000_0000` | 64 KiB | 复位入口和早期 bootloader |
| CLINT | `0x0200_0000` | 64 KiB | `mtime`/`mtimecmp` |
| PLIC | `0x0C00_0000` | 1 MiB | 外部中断控制器 |
| UART | `0x1000_0000` | 4 KiB | 轮询和中断串口（TX/LSR 兼容 16550 常用寄存器） |
| GPIO/LED | `0x1000_1000` | 4 KiB | 板级生命信号 |
| DDR3 | `0x8000_0000` | 按实测容量 | 主存 |

地址图必须由单一源生成 RTL 常量、DTS、链接脚本和测试程序头文件。

## 总线

首版定义简单 ready/valid 请求-响应总线：请求包含地址、读写、字节使能、写数据、特权属性；响应包含读数据、错误和完成。适配器负责连接 BRAM、MIG、UART、CLINT 和 PLIC。后续如接入 XDMA，单独定义 AXI-Lite/AXI 桥，不让 PCIe 时钟域成为 CPU 启动依赖。

## 板卡时钟和 LED

- 50 MHz 单端系统时钟：`AA28`，LVCMOS18。
- 两组 200 MHz 差分时钟：`AH27/AH28`、`G25/G26`，用于 MIG 等需要差分参考的逻辑。
- 用户 LED：红/绿/黄分别为 `P30/M30/N30`，LVCMOS18、active-high。
- 板卡资料未提供可直接使用的 UART 引脚；UART 须在取得实际连接器/管脚信息后加入约束。

## 时钟域

- `clk_50`：CPU、BRAM、VIO/JTAG-AXI bench 逻辑。
- MIG 用户时钟：DDR3 控制器和必要的跨域 FIFO。
- PCIe `axi_aclk`：仅在 PCIe 链路训练后保证运行；不能用于无主机生命信号。

## 可观测性

仿真专用 commit trace 不进入功能路径。综合版本提供 LED 心跳、UART 状态和可选 VIO probes。JTAG-AXI bench 使用 `clk_50` 域 BRAM 往返验证总线。

当前 `rtl/rv64_bram_soc.sv` 将核心、双 Sv39 MMU、片上指令/数据 BRAM、UART
(`0x1000_0000`) 和 `GPIO/LED` (`0x1000_1000`) 连成可运行的仿真顶层；
`rtl/rv64_mig_soc_top.sv` 另提供 MIG/DDR3 板级候选顶层，并由
`constraints/rv64_mig_soc_top.xdc` 约束已确认的时钟和 LED 管脚。两者都尚未经过综合、
实现或实际板级验证。

`rtl/rv64_clint.sv` 的单核 MMIO 偏移遵循标准布局：`msip=0x0000`、`mtimecmp=0x4000`
和 `mtime=0xbff8`；timer/software interrupt 已连接到核心，SoC xsim 已验证 timer trap。

`rtl/rv64_plic.sv` 提供单 hart、31 个外部源的优先级/pending/enable/threshold/claim
寄存器与仲裁，并同时接受 M-mode context `0x200000` 和 S-mode context `0x201000`；PLIC
已接入 SoC MMIO，UART RX 已接到 source 1；其余外设源仍保留为零。
