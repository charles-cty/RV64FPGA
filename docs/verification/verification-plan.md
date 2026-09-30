# 验证计划

## 验证层次

1. 单元：译码、ALU、CSR、乘除法、原子单元、TLB、cache、UART、CLINT、PLIC。
2. 子系统：CPU+BRAM、CPU+MMU/cache、CPU+外设、中断和 DMA 适配器。
3. SoC：bootloader、DDR3 模型、S-mode、Linux 早期启动。
4. 硬件：JTAG、LED、VIO、JTAG-AXI、UART、DDR3、Linux。

## 覆盖率目标

- RV64IMA 每条指令至少一个定向测试和一个随机测试。
- 操作数边界：0、全 1、最小/最大有符号数、移位边界、除零、非对齐地址。
- 异常、CSR、M/S/U、页表权限、TLB miss、cache miss、定时器和外部中断全覆盖。
- 每个失败样例自动固化为回归用例。

## 自动门禁

CI 顺序为 lint → 单元 xsim → SoC xsim → ISS differential → 覆盖率摘要。任何 assertion、timeout、trace mismatch 或 `SIM FAIL` 都阻止进入综合。M5 还包含 `soc_ddr3_external`，用延迟独立端点验证 SoC 外部 DDR3 事务接线。

## 高风险独立检查

- 重新推导 `mepc`、异常优先级、LR/SC reservation、Sv39 权限，和 RTL/ISS 结果交叉核对。
- 用随机程序测试流水线冲刷和 cache/TLB 交互。
- 对 DDR3 接口先做行为模型压力测试，再做板上长时间测试。

当前独立 MMU 回归已覆盖 4 KiB、2 MiB、1 GiB 页、权限/特权级、SUM、MXR、A/D 检查与自动写回、规范地址、
无效 PTE，以及小型 TLB 命中和按地址 `SFENCE.VMA`。直映 write-through 数据 cache
已验证读 hit/miss、写 hit/miss、字节掩码、冲突替换和响应保持握手，并接入 SoC。基础 cache 与 Sv39
核心 differential 已通过；SoC 无效取指页和 execute-only 数据页的 fetch/load/store page
fault 已以独立 Sv39 walker/ISS 逐条比较精确 CSR trap 状态与 store 无内存副作用。S-mode
对 U 页的 SUM load 允许/拒绝已作 differential；U-mode 对 U/S 页的取指和 load 权限，以及
S-mode 对 U 页取指拒绝已覆盖。核心和 BRAM SoC 结构化随机 differential 已接入 M4 门禁；
`mmu_random` 以固定种子随机化页表访问、TLB 命中/失配、地址/全量 `SFENCE.VMA`、`satp` 切换、
超页和权限故障，并输出覆盖率摘要，同时用独立参考 walker 检查每次物理地址和 fault 结果。

`scripts/run-m4-regression.sh` 是当前 M4 的可复现门禁：它只运行 MMU/cache 单元 xsim、
核心与 SoC differential，以及 Python 单元测试；其中 SoC TLB differential 覆盖 PTE
write-through、按地址 `SFENCE.VMA` 和 `satp` 切换。该门禁不会调用综合、实现、下载或 flash 流程。

`ddr3_model` xsim 回归验证 M5 行为 DDR3 endpoint 的延迟、字节写掩码、读后写顺序、
未校准 error 和 pending reset。它不替代 MIG 或板级 DDR3 验证。

`ddr3_axi_adapter` xsim 回归验证单请求 8-byte cache memory contract 到 512-bit
MIG AXI beat 的地址、lane、写掩码、response error 和 reset 行为；它不包含 CDC 或
厂商 MIG IP。

`async_memory_bridge` xsim 在非整比 CPU/UI 时钟下验证 one-request CDC mailbox、
backpressure、response error 和共同异步 reset 中止行为。

`ddr3_mig_path` xsim 将 CDC mailbox 与 512-bit AXI adapter 组合验证，覆盖 CPU
read/write、AXI error 和未校准拒绝。

`soc_ddr3_model` xsim 回归将该 endpoint 接入 cache 外部内存端口，验证 write-through、
延迟 read miss 和后续 cache hit 的架构结果。

`soc_ddr3_mmu` xsim 回归进一步把 Sv39 页表放入 DDR3 模型，覆盖 PTE master 仲裁、延迟
页表遍历、DDR3-backed 虚拟页访问以及 A/D 自动写回。

`soc_ddr3_atomic` xsim 回归验证 DDR3 模型窗口中的 LR/SC/AMO 读-改-写顺序、缓存失效和
最终内存可见性；它是未来 MIG 原子事务桥的模型级门禁。

`soc_sbi` xsim 回归覆盖 S-mode SBI-shaped ecall 的 M-mode trap、`mepc` 修正和返回路径；
它不替代完整 OpenSBI/Linux 验收。

`soc_ddr3_fault` xsim 回归验证未校准 DDR3 endpoint 转化为精确 load access fault，且没有
寄存器写回。

`soc_init_files` xsim 回归验证 SoC 的 `BOOT_ROM_INIT_FILE` 和
`DDR3_MODEL_INIT_FILE` 参数实际装载 ROM 指令与 DDR3 初始数据，并确认 ROM 指令可执行。

`core_supervisor_irq` xsim 回归验证 delegated timer interrupt 在 S-mode 使用
`mstatus.SIE/sie`，使用标准 S-mode timer cause `5`，进入 `stvec` handler 后由 `sret` 返回。
该回归同时覆盖 OpenSBI 风格的 MTIP→STIP 转交，并检查 M handler 的 `csrs mip` 不会把物理 MTIP
锁存为软件 pending；`csr` 回归检查 `mip`/`sip` 的可写位掩码。

`uart_rx` xsim 回归验证 16550 风格 RX 帧、LSR/IIR、溢出和帧错误；
`soc_uart_irq` 进一步验证 UART RX interrupt 经 PLIC source 1 产生 pending/claim。

`core_fence` xsim 回归验证 `FENCE`/`FENCE.I`/`WFI` 不产生非法指令 trap，且 `FENCE.I`
触发指令 cache 失效；ISS 同步接受这些指令。

`core_privilege` xsim 回归验证 U-mode 访问 M-mode CSR 时产生精确
illegal-instruction trap，并确认不发生寄存器写回。

`csr` xsim 回归验证 M-mode `mstatus.MPRV` 与 `MPP=S/U` 组合只改变数据访问特权级，
当前取指特权级保持 M-mode。

`soc_boot_image` 在执行 `scripts/build-boot-image.sh` 后验证生成的 boot ROM
hex 已由 SoC 的 `BOOT_ROM_INIT_FILE` 装载；它不等价于 Linux 启动证据。

`soc_linux_handoff` 使用同一脚本生成的 ROM 和 DDR3 payload，验证真实的 ROM→DDR3
取指跳转、启动参数传递和 payload 的 LED MMIO 标记；它仍不替代 OpenSBI/Linux 验收。

`scripts/run-soc-ddr3-diff.sh` 在 `0x8000_0000` DDR3 模型窗口运行独立 ISS/RTL 程序，逐条
比较高地址构造、write-through、延迟 miss、cache hit、分支和可见 DDR3 内存写入。

`scripts/run-m5-model-regression.sh` 聚合上述 M5 行为模型、cache 集成、指令取指和
unavailable fault xsim 回归；它不生成 MIG IP，也不调用综合或硬件流程。

`core_alignment` xsim 回归覆盖未对齐的 `lw`、`sw`、`lr.w` 和 `amoadd.w`。它还使未对齐
load 与同时到达的 `data_fault` 相遇，以确认 load-address-misaligned 的优先级，并检查
`mcause`、`mtval`、`mepc`、trap vector、寄存器/内存副作用和 LR reservation。独立 ISS
以 `MisalignedAddress` 拒绝未对齐普通 load/store 并保留架构状态；带 trap trace 的
RTL↔ISS differential 场景仍是后续覆盖项。
