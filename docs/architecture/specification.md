# RV64IMA 架构规格（v0.1）

## 执行模型

- XLEN=64，little-endian。
- RV64I、M、A；暂不承诺 F/D/C/V。
- 支持 M、S、U 特权级；实现 Linux 所需的机器模式、监管者模式和用户模式状态。
- 顺序提交；任何异常或中断必须精确到提交边界。
- x0 永远读为零，写入被丢弃。

## 流水线基线

默认采用 `IF -> ID/EX -> MEM/WB` 三级结构，必要时扩展为五级。多周期乘除法和原子操作阻塞流水线。分支预测首版关闭，分支决策后冲刷错误路径。

## 指令和边界行为

- 覆盖 RV64I 全部基础整数指令，包括 W 类指令。
- M 扩展覆盖乘法、高半乘法、除法和余数；除零与有符号溢出遵循 RISC-V Unprivileged ISA 定义。
- A 扩展覆盖 LR/SC 和 AMO；所有原子访问必须按自然对齐宽度执行。
- 未实现编码产生 illegal-instruction 异常。
- 指令地址和数据地址的对齐、访问宽度、符号扩展必须由测试明确覆盖。

## CSR、陷阱和中断

首版至少实现：`mstatus`、`misa`、`mtvec`、`mepc`、`mcause`、`mtval`、`mie`、`mip`、`mideleg`、`medeleg`、`sstatus`、`stvec`、`sepc`、`scause`、`stval`、`sie`、`sip`、`satp`、`time/timeh`。

陷阱入口保存发生指令 PC；`mret/sret` 恢复特权级和中断使能。异常优先级、delegation 和中断抢占规则必须在 ISS 与 RTL 中分别实现并比较。

## 虚拟内存

- 采用 Sv39，三级页表，39 位虚拟地址。
- 支持 R/W/X/U/A/D 权限检查、页大小 4 KiB/2 MiB/1 GiB。
- `satp` 写入后按架构要求处理 TLB 失效；实现 `SFENCE.VMA`。
- 首版 TLB 可采用小容量全相联结构；正确性优先。

## 复位和时钟

外部复位由顶层同步到 `clk_50` 域。SpinalHDL 生成的 `.init(0)` 寄存器按同步复位验证，测试台必须在时钟边沿实际拉高 reset 后再释放。
