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

CI 顺序为 lint → 单元 xsim → SoC xsim → ISS differential → 覆盖率摘要。任何 assertion、timeout、trace mismatch 或 `SIM FAIL` 都阻止进入综合。

## 高风险独立检查

- 重新推导 `mepc`、异常优先级、LR/SC reservation、Sv39 权限，和 RTL/ISS 结果交叉核对。
- 用随机程序测试流水线冲刷和 cache/TLB 交互。
- 对 DDR3 接口先做行为模型压力测试，再做板上长时间测试。

当前独立 MMU 回归已覆盖 4 KiB、2 MiB、1 GiB 页、权限/特权级、SUM、A/D、规范地址、
无效 PTE，以及小型 TLB 命中和按地址 `SFENCE.VMA`。直映 write-through 数据 cache
已验证读 hit/miss、写 hit/miss、字节掩码和冲突替换，并接入 SoC。基础 cache 与 Sv39
核心 differential 已通过；SoC 无效取指页和 execute-only 数据页的 fetch/load/store page
fault 已以独立 Sv39 walker/ISS 逐条比较精确 CSR trap 状态与 store 无内存副作用。S-mode
对 U 页的 SUM load 允许/拒绝已作 differential；U-mode 对 U/S 页的取指和 load 权限，以及
S-mode 对 U 页取指拒绝已覆盖。随机化和 cache/TLB 交互 differential 仍待补齐。

`scripts/run-m4-regression.sh` 是当前 M4 的可复现门禁：它只运行 MMU/cache 单元 xsim、
核心与 SoC differential，以及 Python 单元测试；不会调用综合、实现、下载或 flash 流程。

`ddr3_model` xsim 回归验证 M5 行为 DDR3 endpoint 的延迟、字节写掩码、读后写顺序、
未校准 error 和 pending reset。它不替代 MIG 或板级 DDR3 验证。

`core_alignment` xsim 回归覆盖未对齐的 `lw`、`sw`、`lr.w` 和 `amoadd.w`。它还使未对齐
load 与同时到达的 `data_fault` 相遇，以确认 load-address-misaligned 的优先级，并检查
`mcause`、`mtval`、`mepc`、trap vector、寄存器/内存副作用和 LR reservation。独立 ISS
以 `MisalignedAddress` 拒绝未对齐普通 load/store 并保留架构状态；带 trap trace 的
RTL↔ISS differential 场景仍是后续覆盖项。
