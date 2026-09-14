# 里程碑与交付物

| 阶段 | 结果 | 进入条件 | 退出条件 |
|---|---|---|---|
| M0 | 工程骨架和规格 | 范围冻结、板卡资料初盘 | 文档、目录、构建约定齐全；UART/DDR 待测项登记 |
| M1 | RV64I+BRAM | ISS 可执行 | 指令和 trace 全部一致 |
| M2 | CSR/异常 | M1 通过 | 精确 trap 与 delegation 通过 |
| M3 | M/A | M2 通过 | 边界和随机测试通过 |
| M4 | cache/TLB/Sv39 | M3 通过 | 页表、权限、flush 通过 |
| M5 | UART/CLINT/PLIC/DDR | M4 通过 | SoC xsim 启动通过 |
| M6 | FPGA bring-up | 用户确认 `CONFIRM_SYNTH` | LED、UART、JTAG-AXI、DDR 实测通过 |
| M7 | Linux | M6 通过 | 进入 shell 并完成压力测试 |
| M8 | PCIe/XDMA | Linux 稳定 | 主机 warm reboot 后链路和 DMA 实测通过 |

每个里程碑交付 RTL、testbench、ISS/differential 结果、覆盖率、脚本、波形/日志和已知限制。

当前 M4 已有独立 `rv64_mmu` Sv39 walker 及 xsim 回归，但页表刷新、TLB/cache、核心接入
和 differential 覆盖仍未完成，因此尚未满足 M4 退出条件。
