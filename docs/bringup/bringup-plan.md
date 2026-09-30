# FPGA Bring-up 与上板确认门

## 强制人工确认

仿真、differential testing、assertion 和覆盖率全部通过后，自动流程暂停并要求用户输入 `CONFIRM_SYNTH`。确认前不得执行 Vivado 综合、实现、bitstream 下载或 flash 编程。

`make vivado-project-check` 可在确认前创建临时 Vivado 工程，校验顶层 RTL、XDC、MIG XCI
和编译顺序；该检查不执行综合、实现、下载或 flash。

确认信息必须列出 Git commit、目标器件、约束文件、仿真日志摘要和预计耗时。用户负责提供 LED、UART、VIO、JTAG-AXI、DDR3 的实际反馈。

## Authorization record (2026-09-16)

The user supplied `CONFIRM_SYNTH` for the current loader-enabled SoC candidate.
This authorizes synthesis, implementation, bitstream generation, volatile SRAM
JTAG configuration, and the JTAG AXI/ILA smoke sequence. It does not authorize
BPI Flash erase, programming, boot, or any other unspecified destructive action.

Subsequent hardware-stage approvals use the same token, `CONFIRM_SYNTH`. Each
approval request must still state its concrete scope, candidate identity, and
expected hardware effect; the token is not blanket authorization for an
unrequested Flash operation.

## 硬件顺序

1. JTAG 识别。
2. LED 心跳和复位指示（`P30/M30/N30`，active-high）。
3. `clk_50` 域 VIO。
4. JTAG-AXI + BRAM 读写。
5. BRAM bare-metal 程序；UART 仅在用户提供 TX/RX 管脚后启用。
6. MIG DDR3 初始化与压力测试。
7. CLINT/PLIC/异常。
8. MMU/cache。
9. Linux。
10. PCIe/XDMA（需要主机 warm reboot 才能验证链路）。

## 板卡注意事项

- 目标 part 为 `xc7k480tffg1156-2`。
- 50 MHz `clk_50` 是无主机条件下可靠的 free-running clock。
- XDMA 升级后检查 `CONFIG.axilite_master_en=true`、`M_AXI_LITE` 和 `axi_smc1/S00_AXI` 连接。
- BPI flash 编程必须先加载 JTAG↔BPI bridge，再执行 `program_hw_cfgmem`，最后用 `boot_hw_device` 验证。
- Word 板卡资料展示的配置器件为 `mt28gu512aax1e-bpi-x16`；配置前仍需确认 Vivado 检测到的实际 flash part。

## 证据规则

仿真结果和硬件结果分开记录。只有实际观察到的 LED/UART/VIO/JTAG-AXI/DDR/PCIe 结果才能写为硬件通过。

## 最新实现门状态（2026-09-15）

- MIG 生成流程已固定关闭 `DIFF_TERM_SYSCLK`，顶层 XDC 也显式设置 `DIFF_TERM FALSE`；`PORTPROP-2` 已消失。
- 最新综合 checkpoint：`build/vivado-synth-final-20260915/reports/rv64_mig_soc_synth.dcp`。组合环为 0，内部未约束端点为 0，WNS 为 `0.618 ns`。
- 最新实现 checkpoint：`build/vivado-impl-final-20260915/rv64_mig_soc_routed.dcp`。WNS `0.059 ns`、WHS `0.052 ns`、TNS/THS 均为 0，报告确认所有用户时序约束满足。
- DRC 无错误；`CFGBVS-1` 仍因缺少 Bank 0 电压/strap 证据而保留，MIG `REQP-1709` 为固有提示。两者未被猜测性修改。
- 板卡 `board.xml` 已确认配置 Flash 为 Micron `MT28GU512AAA1EGC`，512 Mbit BPI NOR；仍需确认实际芯片丝印与板卡 revision 一致。
- 在用户明确接受 `CFGBVS-1` 残余风险前，因未完成硬件级 DDR3 I/O delay/校准证据，不执行 flash 编程。

## Flash/JTAG 实际结果（2026-09-15）

- 已按授权使用 `CFGBVS=GND`、`CONFIG_VOLTAGE=1.8` 生成 `BPIx16/64MB` 映像。JTAG 识别到 `xc7k480t_0`；临时配置返回 `End of startup status: HIGH`。JTAG↔BPI bridge 加载成功，Vivado 报告 Flash 制造商 ID 原始值为 `89`；Flash 擦除、Program/Verify 和 `boot_hw_device` 均成功，后者返回 `Done pin status: HIGH`。
- 初始映像经物理断电再上电后的只读 JTAG 刷新报告 `DONE status = 0`，因此该映像未完成冷启动；四个 LED 常亮不能作为配置成功证据。
- 对照板卡已验证的 `LC480T/led.bit`，最终映像保持非压缩，并显式设置 `BITSTREAM.CONFIG.CONFIGRATE=12`。该值已写入 `constraints/rv64_mig_soc_top.xdc` 和 `scripts/write-rv64-mig-bitstream.tcl`。
- 修正后的映像已擦写、Program/Verify 和 `boot_hw_device` 成功；用户完整物理断电再上电后，`scripts/check-rv64-mig-jtag-boot.tcl` 的只读检查报告器件“is programmed with a design”，即 FPGA 已从 Flash 重新配置，DONE 为高。
- 已验证产物为 `build/vivado-bitstream-configrate12-20260915/rv64_mig_soc_top.bit`、`build/vivado-bitstream-configrate12-20260915/rv64_mig_soc_top.mcs` 和同目录 `SHA256SUMS`。这只证明 BPI 冷启动配置正常；尚未证明 DDR3 校准、CPU 软件执行或 PCIe 功能。

## DDR3 诊断映像（2026-09-16）

- 独立 `rv64_mig_ddr3_diag_top` 已完成综合、实现和 bitstream 生成；实现时序为 WNS `0.548 ns`、WHS `0.051 ns`、TNS/THS `0`，DRC 无错误。
- 已将 `build/vivado-bitstream-ddr3-diag-20260916/rv64_mig_ddr3_diag_top.bit` 通过 JTAG 下载到 SRAM；最近一次重下载于 2026-09-16 12:46，Vivado 返回 `End of startup status: HIGH`。该映像没有 VIO/ILA/JTAG debug core，JTAG 只能确认配置状态，不能读取诊断寄存器。
- 原始 DDR3 诊断的颜色判据：红灯表示校准完成，绿灯表示诊断完成，黄灯表示诊断失败；红绿亮、黄灭表示校准完成且全部测试通过。必须由用户实际观察红、绿、黄灯后才能登记板级 DDR3 结果。
- 原始 DDR3 诊断映像不是 RV64 Linux 映像；在 LED 结果和真实 RV64 OpenSBI/Linux/kernel/DTB/initramfs 到位前，不执行 Linux 板级验收或写入 Flash。当前 SRAM 映像见下节的状态诊断记录。

## DDR3 校准阻塞诊断（2026-09-16）

- 用户观察到原始 DDR3 诊断映像 LED 为 `000`，因此 `init_calib_complete=0`，板级 DDR3 不能判定通过，Linux 验收继续阻塞。
- `000` 不能从原有 LED 定义中区分复位持续有效与 MIG 系统时钟/MMCM 未锁。新增只读状态顶层 `rv64_mig_ddr3_status_top` 并已完成实现（WNS `0.548 ns`、WHS `0.059 ns`、TNS/THS `0`、DRC 仅 `REQP-1709`），于 2026-09-16 通过 JTAG 下载到 SRAM，返回 `End of startup status: HIGH`；未写入 Flash。
- 新 status 映像的颜色含义为：红灯 = 复位已释放，绿灯 = MIG MMCM 已锁，黄灯 = DDR3 校准完成。红灭表示复位未释放；仅红亮表示 MMCM 未锁；红绿亮而黄灭表示 MMCM 已锁但校准未完成；三灯全亮表示校准完成。读取时须保持复位按钮未按下至少 30 秒。
- 板卡 `part0_pins.xml` 将 `AH27/AH28` 的 200 MHz 时钟标为 `LVDS`，而当前顶层 XDC 约束为 `DIFF_SSTL15`。若 status 映像为 `001`，该约束差异将成为首先验证的根因；在观测结果返回前不猜测性修改。
- 后续复核发现 Vivado 对 `LVDS` 标签回落为 `DEFAULT`；器件/实现最终采用并接受 `DIFF_HSTL_II_18`。HSTL 版本 routed DRC 已无 `NSTD-1`，bitstream 已于 2026-09-16 重新通过 JTAG 下载，未写入 Flash。等待新的红、绿、黄状态反馈。
- 复核 routed checkpoint 后，Vivado 将 AH27/AH28 实际解析为 `DIFF_HSTL_II_18`；`LVDS` 在该器件上落为 `DEFAULT` 并触发 `NSTD-1`。已将顶层约束固定为 `DIFF_HSTL_II_18`，生成 bitstream 前 DRC 为 0 错误，并于 2026-09-16 重新下载到 SRAM；Flash 未写入。请用户等待 30 秒后反馈红、绿、黄三灯状态。
- 用户于 2026-09-16 要求停止该实验并回退。已删除未完成的时钟探针和 status 顶层构建入口，顶层 XDC 恢复为此前已验证的 `DIFF_SSTL15`。已对 `build/vivado-bitstream-configrate12-20260915/SHA256SUMS` 完成哈希校验，并将 `rv64_mig_soc_top.bit` 成功重新下载到 SRAM；Flash 内容未改动，仍为同一已验证冷启动映像。

## CH0 极性资料复核（2026-09-16）

- 用户提供的表格把 CH0 标为 P=`AH28`、N=`AH27`。按该方向实施后，Vivado 在 routed checkpoint 中报 `Vivado 12-1411`：`AH28` 是器件差分负端，`AH27` 是正端，因此 `sys_clk_p=AH28`/`sys_clk_n=AH27` 不可放置，并引发 `UCIO-1`。该映像未生成、未下载。
- 已恢复唯一可由 FPGA 合法放置的约束：`sys_clk_p=AH27`、`sys_clk_n=AH28`，保留 `DIFF_SSTL15` 和 `DIFF_TERM FALSE`。资料表的 P/N 标注与 FPGA package 的 P/N 命名存在矛盾；必须以原理图/实际网名确认时钟源、是否存在板级交换或时钟源未使能，不能再以交换 XDC 端口作为修复手段。
- 已生成并通过 JTAG 下载纯硬件时钟探针 `build/vivado-bitstream-ddr3-clock-probe-20260916/rv64_ddr3_clock_probe_top.bit`；该映像不实例化 MIG、DDR3 或 CPU，DRC 无错误且未写 Flash。最近一次 SRAM 重下载于 2026-09-16 12:44（Vivado 报 `End of startup status: HIGH`）。颜色含义：红=复位释放，绿=在 50 MHz 域可靠检测到 CH0 200 MHz 的分频翻转，黄=约 1.34 秒观察窗口完成。用户观察为红绿黄均常亮，故 CH0 的 200 MHz 时钟已在 FPGA 中被稳定检测到；该结果不等价于 DDR3 校准通过。
- 在 CH0 时钟确认后，DDR3 诊断映像于 12:46 重新下载，用户在等待 30 秒后观察红绿黄全灭。这只证明 `init_calib_complete=0`，尚不能区分复位、MIG MMCM 未锁或 DDR3 校准未完成。已在 13:15 下载经 SHA-256 校验的 `build/vivado-bitstream-ddr3-status-20260916/rv64_mig_ddr3_status_top.bit`（`End of startup status: HIGH`，Flash 未改）；其红/绿/黄依次显示复位释放、MIG MMCM 锁定、DDR3 校准完成，等待用户新读数。
- 用户观察状态映像仅红亮，故复位已释放而 MIG MMCM 未锁。原始时钟探针只验证输入在跳变，不能确认频率。新增 `rv64_ddr3_clock_frequency_probe_top`：在 50 MHz 参考下用 Gray-code 跨时钟计数约 0.67 秒，绿色仅在 CH0 为 190.7--208.6 MHz 时点亮，红色表示复位已释放，黄色表示测量完成。Vivado xsim 分别验证 200 MHz 输出红绿黄全亮、100 MHz 输出红黄亮绿灭。实现 WNS `16.218 ns`、WHS `0.128 ns`、TNS/THS `0`、DRC 无错误；bitstream 于 13:27 通过 JTAG 下载（`End of startup status: HIGH`），Flash 未改，等待颜色反馈。
- 频率探针显示红绿黄全亮，严格确认 CH0 输入为 190.7--208.6 MHz 范围内的 200 MHz；时钟存在与频率均被排除为 MMCM 未锁的根因。检查 MIG 生成源码 `rv64_mig_ch0_mig.v` 发现其 `sys_rst` 默认低有效，而诊断顶层和 SoC 顶层此前错误地连接高有效的 `reset`；因此板上复位释放后 MIG 被持续复位，正好解释仅红亮。两个顶层现均将 `sys_rst` 正确连接至低有效 `reset_n`。修复后的 DDR3 诊断完成重新综合、实现和 bitstream：WNS `0.520 ns`、WHS `0.007 ns`、TNS/THS `0`，所有用户时序约束满足；routed DRC 仅有原有 `REQP-1709` 警告，bitstream 前 DRC 为 0 错误。SHA-256 为 `b585e22c1e84ab8a244442825128bc7f8132e32a7125c42e63fbfb7f8e127817` 的 `build/vivado-bitstream-ddr3-diag-reset-polarity-20260916/rv64_mig_ddr3_diag_top.bit` 已于 18:17 通过 JTAG 下载，Vivado 返回 `End of startup status: HIGH`；Flash 未改。等待 30 秒后读取红、绿、黄。
- 用户在修复映像下载后等待 30 秒，观察红绿亮、黄灭。按诊断定义，这证明 MIG 已完成校准，且四组共 256 个 64-bit word 的写入/读回模式测试全部通过；CH0 DDR3 的时钟、复位、训练和基本 AXI 路径均已完成板级验证。该结果不等价于 CPU、Linux、PCIe 或 Flash 中映像通过；下一硬件阶段为用相同修复重建 SoC 并建立可观察的软件启动通道。

## LED 物理连通性复核（2026-09-16）

- 已将板卡参考映像 `C:\My\Projects\FPGA\LC480T\led.bit` 通过 JTAG 下载到 SRAM，Vivado 返回 `End of startup status: HIGH`；未写入 Flash。
- 四个 LED 的实际亮灭/闪烁观察结果待用户反馈，本步骤只验证 LED 测试映像和 JTAG 下载链路。

## Linux handoff 仿真（2026-09-16）

- `make linux-handoff` 已通过，日志哨兵为 `XSIM_PASS soc_linux_handoff`；这只证明 ROM→DDR3 行为模型 payload handoff，不等价于 Linux 启动。
- `make linux-stack` 已在容器中成功生成固定版本的 RV64IMA Linux v6.12、OpenSBI v1.6、BusyBox/musl initramfs 和模型 DTB；发布工件为 `build/linux/linux/arch/riscv/boot/Image`、`build/linux/rv64fpga-model.dtb`、`build/linux/rv64fpga-fw_payload.bin` 与 `build/linux/SHA256SUMS`。
- 这些工件尚未构成真实启动证据：SoC 顶层现已准备 JTAG AXI loader、DDR3 读回抽样、可控 CPU
  reset 与 `clk_50` ILA probes，但尚未综合或加载这个新映像，且 UART TX/RX 的板卡管脚仍未得到
  确认。下一硬件门必须先取得用户 `CONFIRM_SYNTH`，随后在 SRAM 上以 JTAG loader 的 DDR3
  round-trip、payload sample readback 和 ILA startup trace 逐项建立证据；不得猜测 UART XDC
  约束或写入 Flash。
