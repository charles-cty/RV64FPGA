# Vivado xsim 流程

`xvlog`、`xelab`、`xsim` 是 Vivado `bin` 目录下的独立程序，不能作为 `vivado -mode batch` Tcl 命令调用。

## Windows 本地 staging

WSL 脚本将 RTL、testbench、镜像复制到 Windows 本地临时目录。PowerShell 负责从 `VivadoBat` 参数通过 `Split-Path` 推导 `bin`，避免 WSL 反斜杠路径误解析。

仓库的 `scripts/run-xsim.ps1` 是 xsim 驱动，`scripts/run-xsim.sh` 负责从 WSL 调用它。
驱动会把 RTL 和 testbench 复制到 Windows 本地临时目录，运行 `xvlog`、`xelab`、`xsim`，
然后将 `sim.log` 回传到 `build/xsim/<test>/`；它不会调用综合或实现流程。

## 标准步骤

```text
xvlog --nolog <rtl> <tb>
xelab --nolog --debug typical --snapshot tb_snap <tb_top>
xsim --nolog --runall --log sim.log tb_snap
```

仿真必须以 `$finish` 结束，并在日志中写出 `SIM PASS`。退出码为 0 不能单独证明 assertion 通过。

## 测试台规则

- 对同步 reset 在时钟边沿实际施加并释放。
- 初始化 128 位 bundle 时，slot 0 放在最低 32 位。
- 长消息 task 使用至少 512 位输入。
- 每个测试设置 timeout、seed、版本和期望结果。

当前 ALU 回归：

```bash
./scripts/run-xsim.sh alu
```

译码器、寄存器堆、立即数、核心、核心 CSR、核心原子、CSR 和原子单元回归分别使用
`./scripts/run-xsim.sh decoder`、`./scripts/run-xsim.sh regfile`、`./scripts/run-xsim.sh imm`、
`./scripts/run-xsim.sh core`、`./scripts/run-xsim.sh core_csr`、`./scripts/run-xsim.sh core_atomic`、
`./scripts/run-xsim.sh csr` 和 `./scripts/run-xsim.sh atomic`。这些回归均要求日志出现
`SIM PASS`，并在发现 `SIM FAIL` 时返回失败。

`./scripts/run-xsim.sh core_alignment` 验证普通 load/store 和 A 扩展 LR/AMO 的自然对齐
trap，包含未对齐 load 与 `data_fault` 同周期时的异常优先级，以及无寄存器、内存或
reservation 副作用的检查。

`./scripts/run-xsim.sh soc` 验证 `rv64_bram_soc` 的 LED 地址映射；它与 `core` 回归
使用相同的 Windows staging 规则。

`./scripts/run-xsim.sh clint` 验证 CLINT 的计数器、字节写掩码以及 timer/software
interrupt 边界。

`./scripts/run-xsim.sh plic` 验证 PLIC 的优先级仲裁、claim/complete 和 threshold。

`./scripts/run-xsim.sh mmu` 验证独立 Sv39 walker 的三级页表遍历、4 KiB/2 MiB/1 GiB
映射、R/W/X/U/A/D 权限、S-mode SUM、非规范虚拟地址、无效 PTE、超页对齐、Bare
直通、小型 TLB 命中和按地址 `SFENCE.VMA`。该回归覆盖 MMU 单元本身；SoC 接入另由
`soc_mmu` 回归验证，数据 cache 由独立 `cache` 回归验证。

核心的 `csr` 回归另外验证 M/S/U 委派 trap、`sret` 和动态 trap vector；取指 `ready`
握手在无 MMU 的核心单元回归中固定为 1；翻译停顿和完成保持由 `soc_mmu` 回归覆盖。

`./scripts/run-xsim.sh soc_irq` 验证 SoC 中 CLINT timer 到核心 trap/handler/MRET 的路径。

`./scripts/run-xsim.sh soc_mmu` 验证 SoC 双 MMU 的 Sv39 取指和数据翻译、S-mode `mret`
切换、虚拟 store/load、物理 BRAM 写入以及翻译完成握手。

`./scripts/run-xsim.sh soc_mmu_fault` 验证 S-mode 对 execute-only 页 load 时触发
精确 load page fault，并保存 `mepc`、`mcause`、`mtval` 和 MPP 后跳转至 M-mode handler。

`./scripts/run-xsim.sh soc_mmu_fault_diff` 导出上述 fault 场景的扩展提交 trace；
`./scripts/run-soc-mmu-fault-diff.sh` 以独立 Sv39 walker/ISS 比较无效取指页、execute-only
数据页的 fetch/load/store 故障提交，以及普通提交的 `trap_cause`、`trap_value` 和提交后的
privilege。

`./scripts/run-xsim.sh soc_mmu_diff` 导出基础 Sv39 SoC 的 RTL 提交 trace；
`./scripts/run-soc-mmu-diff.sh` 以独立 PTE walker 和 ISS 生成并比较 15 条提交。

`./scripts/run-xsim.sh cache` 验证直映写通数据 cache 的读 miss 填充、读 hit、写 hit 和
字节写掩码更新。

`./scripts/run-xsim.sh soc_cache_diff` 导出 cacheable BRAM SoC 的 RTL 提交 trace；
`./scripts/run-soc-cache-diff.sh` 再以独立 ISS 生成并比较完整期望 trace。

`./scripts/run-xsim.sh uart` 与 `./scripts/run-xsim.sh soc_uart` 分别验证 UART 8N1
发送器和 SoC `0x1000_0000` MMIO 接线；它们不证明板上存在可用 UART 管脚。
