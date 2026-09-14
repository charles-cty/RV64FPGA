# 项目范围与决策记录

## 目标

实现单核、顺序发射 RV64IMA SoC，在 YPCB-00338-1P1 上运行 Linux。第一版优先可验证性和正确性，不以高性能为目标。

## “不使用开源硬件和 CPU”的解释

- CPU、cache、TLB、MMU、总线、外设和 FPGA 顶层 RTL 必须由本项目编写。
- 不使用 Rocket、BOOM、CVA6、PicoRV、VexRiscv 等开源 CPU/SoC RTL。
- 可使用 Verilog/SystemVerilog/SpinalHDL 等 HDL 工具和 Vivado IP（工具/IP 不等于 CPU RTL）。
- Linux 内核本身是开源软件；若要求所有软件也不得使用开源代码，则必须另行批准自研内核、SBI 和工具链，当前计划不包含该扩展。
- ISS、测试生成器和参考工具可使用独立实现；不得把任何开源 CPU RTL 放入综合设计。

## 硬件目标

- 器件：`xc7k480tffg1156-2`。
- 板卡：YPCB-00338-1P1。
- 板载自由时钟：50 MHz `clk_50`。
- 第一阶段输出：LED 心跳和 UART 日志。
- DDR3、PCIe/XDMA 在最小 SoC 稳定后接入。

## 关键决策

1. 单核、顺序、单发射，三级或五级流水线由 RTL 原型评估后冻结。
2. 先实现 BRAM 内存模型，再接 MIG DDR3。
3. 先实现物理地址访问，再实现 cache、TLB 和 Sv39。
4. 所有 CPU 指令以独立 ISS trace 做逐条 differential compare。
5. 未收到用户明确确认，不执行综合、实现、bitstream 下载或 flash 编程。

## 已确认决策

- 允许使用 Linux、OpenSBI、GCC/binutils 和开源测试工具；限制仅适用于综合设计中的 CPU/SoC 硬件 RTL。
- CPU 采用单核、顺序发射、三级流水线，正确性优先。
- Linux 首版直接从 DDR3 启动；BRAM 仍用于 ROM、早期 bootloader 和仿真模型。
- PCIe/XDMA 不作为 Linux 首版启动条件，Linux 稳定后单独接入。

## 板卡资料结论

资料目录 `C:\My\Projects\FPGA\docs\LC480T` 已检查：

- `default_50mhz_clk0`：单端 50 MHz，`AA28`，LVCMOS18。
- `default_200mhz_clk1/2`：差分 200 MHz，分别位于 `AH27/AH28` 和 `G25/G26`。
- 用户 LED：`P30/M30/N30`，红/绿/黄，LVCMOS18，active-high。
- DDR3：存在 `MEMORY_CH0.ucf` 和 `MEMORY_CH1.ucf`，每组包含 `ddr3_dq[0:71]`；`mig_01.prj` 声明两个 DDR3 controller，器件为 `MT41K256M8XX-125`，15 行地址、3 位 bank；Word 资料截图标注 4GB DDR3 memory components。当前按 4GB 总容量规划，最终仍以 MIG 初始化和压力测试为准。
- 找不到 UART 专用引脚、连接器定义或 UART XDC；首版不假定板载 UART。

## 暂定接口（待实测确认）

- LED 作为第一阶段唯一板级可见输出。
- UART 默认使用外接 FPGA 管脚/转接板；波特率暂定 `115200 8N1`，生成 XDC 前必须提供具体 TX/RX 管脚和电气标准。
- 若暂时没有 UART，使用 JTAG-AXI、VIO 和 LED 完成 bring-up，Linux console 先保留为待定接口。
- 用户仍需提供 LED 观察结果、JTAG-AXI/VIO 读数，以及 DDR3 实际容量和初始化反馈。
