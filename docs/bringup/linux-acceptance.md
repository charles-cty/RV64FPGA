# Linux 启动与验收

## 启动阶段

1. ROM 进入 M-mode bootloader。
2. 初始化栈、UART 和 DDR3。
3. 初始化 timer、PLIC 和 SBI 接口。
4. 构造 Sv39 页表并进入 S-mode。
5. 加载 Linux、DTB 和 initramfs。
6. 进入 UART console shell。

## 验收标准

- 完整内核早期日志可保存。
- timer tick 和外部中断计数持续增长。
- 用户态程序可执行，`/proc` 可挂载。
- 内存、系统调用、进程创建和 UART 长时间压力测试通过。
- Linux 启动和压力测试期间无 ISS/RTL 已知差异、cache/TLB 错误或复位循环。

## 软件边界

默认允许上游 Linux、OpenSBI、GCC/binutils。若用户要求软件也完全自研，应在进入本阶段前重新估算范围和工期。
