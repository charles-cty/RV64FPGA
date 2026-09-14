# YPCB-00338-1P1 板卡资料盘点

来源：`C:\My\Projects\FPGA\docs\LC480T` 下的 board files、约束、器件资料和唯一的 Word 文档；详细检查记录见 [原始资料审计](source-audit.md)。本文件只记录已观察到的资料，不替代原始约束文件。

| 功能 | 观察结果 | 当前用途 |
|---|---|---|
| 系统时钟 | 50 MHz 单端，`AA28`，LVCMOS18 | CPU/BRAM/bench 默认时钟 |
| 差分时钟 1 | 200 MHz，`AH27/AH28` | MIG 候选输入 |
| 差分时钟 2 | 200 MHz，`G25/G26` | MIG 候选输入 |
| 用户 LED | 红 `P30`、绿 `M30`、黄 `N30`，active-high | 心跳、状态编码 |
| DDR3 CH0/CH1 | 两份 `.ucf`，各含 `ddr3_dq[0:71]`；单通道 `mig_0.prj` 为 C0：`MT41K256M8XX-125`、一个 `ddr3_cs_n[0]`、2 GiB、72-bit ECC、15/10 行/列地址、3 位 bank、200 MHz `AH27/AH28`；双通道 `mig_01.prj` 为 4 GiB | Linux 首版固定 C0 2 GiB，见 `mig-ch0-recipe.md`；仍须 MIG 校准和内存压力测试确认 |
| PCIe refclk | `J8/J7`（P/N） | PCIe/XDMA 后续阶段 |
| UART | 未在资料中找到专用管脚或约束 | 暂不作为固定板级接口 |
| JTAG | 14 针 JTAG-HS3：偶数脚为 `VREF/TMS/TCK/TDO/TDI/SRST`，奇数脚为 GND | Vivado Hardware Manager 下载和 VIO/JTAG-AXI |
| 配置 Flash | Word 资料截图选择 `mt28gu512aax1e-bpi-x16` | 后续 BPI 固化和启动验证 |

## 必须补充的硬件事实

- DDR3 C0 在目标 Vivado 版本中的实际校准结果、可用容量和长时间错误率；机器配置中的单一 chip-select 是一 rank 设计输入，但不是硬件通过证据。
- 可连接 USB-UART/示波器的 TX/RX 管脚及电平。
- LED 是否存在反相器或板级电流限制；board.xml 描述为 active-high，但首次下载仍需实测。
- 200 MHz 时钟是否实际连接到目标 MIG 通道。
