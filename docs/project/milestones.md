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

当前 M4 已有独立 `rv64_mmu` Sv39 walker、小型 TLB 及 xsim 回归，并已完成双 MMU
接入 BRAM SoC 的 Sv39 取指/数据集成回归。直映 write-through/no-write-allocate 数据
cache 已接入 BRAM 数据路径，有独立回归及 bare-mode RTL↔ISS differential。基础 Sv39
配置、MRET、取指和数据访问已有 RTL↔ISS differential；无效取指页以及 execute-only 数据
页的 fetch/load/store page fault 已检查 `mepc`、`mcause`、`mtval` 和目标特权级；S-mode
对 U 页的 `SUM=0/1` data access 已有 differential；U-mode 对 U/S 页的 fetch/load 权限
以及 S-mode 对 U 页取指拒绝已覆盖。随机化、覆盖率摘要和更广泛的 cache/TLB 交互仍未完成，
因此尚未满足 M4 退出条件。

M5 的 DDR3 路径已有 CPU-side/MIG-side contract、行为模型和 cache/fault xsim 验收项，也已
固定可审计的 C0 MIG 配置输入与生成配方。实际 MIG IP、CDC/AXI wrapper、SoC 顶层约束、
校准和板级压力测试仍不存在；此外 M4 的退出条件尚未满足。故这些 M5 增量不能将 M5 标记为
已进入或完成。
