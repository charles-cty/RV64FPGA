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
- `FENCE` 和 `FENCE.I` 已实现；`FENCE.I` 使指令 cache 失效，保证后续取指重新访问后端。
- `WFI` 已实现为可提交的等待提示指令；当前实现不停止时钟，便于仿真和后续中断接入。
- UART 提供 16550 风格的 RX holding register、LSR/IIR 状态和 RX 中断；RX 中断接入 PLIC source 1。
- 指令地址和数据地址的对齐、访问宽度、符号扩展必须由测试明确覆盖。普通 load/LR 的未对齐访问产生 load-address-misaligned（cause `4`），普通 store/SC/AMO 产生 store/AMO-address-misaligned（cause `6`）；`mtval` 保存有效地址，且不得发起数据事务、写回目的寄存器或改变 reservation。

## CSR、陷阱和中断

首版至少实现：`mvendorid`、`marchid`、`mimpid`、`mhartid`、`mstatus`、`misa`、`mtvec`、`mepc`、`mcause`、`mtval`、`mie`、`mip`、`mideleg`、`medeleg`、`sstatus`、`stvec`、`sepc`、`scause`、`stval`、`sie`、`sip`、`satp`、`time/timeh`；`cycle/cycleh` 映射到同一单调计数器。M-mode 置位 `mstatus.MPRV` 时，数据访问特权级取 `mstatus.MPP`，取指仍使用当前特权级。

陷阱入口保存发生指令 PC；`mret/sret` 恢复特权级和中断使能。异常优先级、delegation 和中断抢占规则必须在 ISS 与 RTL 中分别实现并比较。
CSR 访问按地址编码执行特权级和只读检查；不合法访问产生 illegal-instruction 异常。
访问未实现的 CSR 同样产生 cause `2`，`mtval` 保存故障指令，且不得写回目的寄存器；
这适用于全部六种 CSR 指令，包括 `rd=x0` 的只写操作和 `rs1/uimm=0` 的只读操作。
`riscv_pkg::csr_implemented` 列出当前实现范围，必须与 `rv64_csr` 同步维护。
特别是未实现的 `stimecmp`、AIA 和 state-enable CSR 不能返回伪造的零值，
否则 OpenSBI 的异常探测会误报硬件扩展。依据
[RISC-V 特权规范 CSR 访问规则](https://riscv.org/wp-content/uploads/2017/05/riscv-privileged-v1.10.pdf)。
机器级中断使用 `MSIP/MTIP/MEIP` cause `3/7/11`，委派到 S-mode 后分别呈现为 `SSIP/STIP/SEIP` cause `1/5/9`。
`mip` 中 `MSIP/MTIP/MEIP` 由 CLINT/PLIC 驱动，对软件只读；`mip` 写入仅改变 `SSIP/STIP/SEIP`，`sip` 写入仅改变已委派的 `SSIP`。`csrs/csrc mip` 的读-改-写不得把硬件 pending 位锁存进软件状态。

## 虚拟内存

- 采用 Sv39，三级页表，39 位虚拟地址。
- 支持 R/W/X/U/A/D 权限检查、页大小 4 KiB/2 MiB/1 GiB。
- 叶级 PTE 的 A 位在成功访问时自动置位，store/AMO 成功访问还自动置位 D 位；更新后的 PTE
  写回片上页表存储，TLB 在 A/D 未满足时重新遍历页表。
- `satp` 写入后按架构要求处理 TLB 失效；实现 `SFENCE.VMA`。
- 首版 TLB 可采用小容量全相联结构；正确性优先。

首版数据 cache 为小容量直映、8-byte line、write-through/no-write-allocate；MMIO 访问
绕过 cache。其命中、miss、写回和冲突替换必须以独立 xsim 回归覆盖。cache response
保持到上层显式确认，允许指令响应在较慢的数据 miss 期间保持有效。

当前核心已暴露取指 `ready` 停顿接口、`satp/SUM/privilege` 状态和 `SFENCE.VMA` 事件，
并暴露 `mstatus.MXR` 供 MMU 权限检查；MXR 置位时，数据 load 可读取仅具 X 权限的页，
取指与 store 规则不变。
核心已支持 CSR 层的 M/S/U 委派 trap。BRAM SoC 已接入独立的取指/数据 MMU，完成 Sv39
取指、数据访问和翻译故障反馈；完整异常/中断 delegation、cache 交互仍需继续验证。

## 复位和时钟

外部复位由顶层同步到 `clk_50` 域。SpinalHDL 生成的 `.init(0)` 寄存器按同步复位验证，测试台必须在时钟边沿实际拉高 reset 后再释放。
