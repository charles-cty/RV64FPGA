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
