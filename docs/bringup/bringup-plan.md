# FPGA Bring-up 与上板确认门

## 强制人工确认

仿真、differential testing、assertion 和覆盖率全部通过后，自动流程暂停并要求用户输入 `CONFIRM_SYNTH`。确认前不得执行 Vivado 综合、实现、bitstream 下载或 flash 编程。

确认信息必须列出 Git commit、目标器件、约束文件、仿真日志摘要和预计耗时。用户负责提供 LED、UART、VIO、JTAG-AXI、DDR3 的实际反馈。

## 硬件顺序

1. JTAG 识别。
2. LED 心跳和复位指示（`P30/M30/N30`，active-high）。
3. `clk_50` 域 VIO。
4. JTAG-AXI + BRAM 读写。
5. BRAM bare-metal 程序；UART 仅在用户提供 TX/RX 管脚后启用。
6. MIG DDR3 初始化与压力测试。
7. CLINT/PLIC/异常。
8. MMU/cache。
9. Linux。
10. PCIe/XDMA（需要主机 warm reboot 才能验证链路）。

## 板卡注意事项

- 目标 part 为 `xc7k480tffg1156-2`。
- 50 MHz `clk_50` 是无主机条件下可靠的 free-running clock。
- XDMA 升级后检查 `CONFIG.axilite_master_en=true`、`M_AXI_LITE` 和 `axi_smc1/S00_AXI` 连接。
- BPI flash 编程必须先加载 JTAG↔BPI bridge，再执行 `program_hw_cfgmem`，最后用 `boot_hw_device` 验证。
- Word 板卡资料展示的配置器件为 `mt28gu512aax1e-bpi-x16`；配置前仍需确认 Vivado 检测到的实际 flash part。

## 证据规则

仿真结果和硬件结果分开记录。只有实际观察到的 LED/UART/VIO/JTAG-AXI/DDR/PCIe 结果才能写为硬件通过。
