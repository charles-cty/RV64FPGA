# Linux 启动与验收

> 当前正式入口见 [维护流程](maintained-workflow.md)。以下按时间保留的历史命令和待办可能已被后续结果取代。

## 启动阶段

1. ROM 进入 M-mode bootloader。
2. 初始化栈、UART 和 DDR3。
3. 初始化 timer、PLIC、16550 串口（含 RX 中断）和 SBI 接口。
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

在实际 MIG 接入前，xsim 可通过 SoC 的 `BOOT_ROM_INIT_FILE` 和
`DDR3_MODEL_INIT_FILE` 参数加载 bootloader/kernel 镜像；这只证明镜像装载与取指路径，
不构成 Linux 启动或硬件 DDR3 证据。

`sw/boot/boot.S` 提供最小 M-mode 跳转 stub：它构造 `0x8000_0000` DDR3 入口，按
RISC-V 启动约定设置 `a0=0`（hartid）和 `a1=0x8001_0000`（DTB），再跳转到预加载
payload。`sw/boot/linux-handoff.S` 是一个最小的 DDR3 payload，用于读取 `a1`、校验 FDT magic 并通过
LED MMIO 标记已完成跳转。`scripts/build-boot-image.sh` 使用可配置的 `RISCV_CLANG`
和 `LLVM_OBJCOPY` 同时生成 `build/boot/boot_rom.hex` 与
`build/boot/linux_payload.hex`；`make linux-handoff` 将两者装载到 xsim，并验证 ROM
确实执行到 DDR3 payload。该 smoke test 不生成或装载真正的 Linux/OpenSBI 映像。

`make linux-stack` 从固定版本的 Linux v6.12、OpenSBI v1.6、BusyBox 1.36.1 和 musl
v1.2.5 生成 RV64IMA/LP64 的静态 initramfs、内核 `Image`、DTB 及 OpenSBI
`fw_payload.bin`。构建在 WSL 原生文件系统执行，最终发布到：

- `build/linux/linux/arch/riscv/boot/Image`
- `build/linux/rv64fpga-model.dtb`
- `build/linux/rv64fpga-fw_payload.bin`
- `build/linux/SHA256SUMS`

这证明软件工件可构建，仍不证明它们已写入物理 DDR3，或已经从真实硬件 UART 输出。

The OpenSBI build uses `FW_PAYLOAD_FDT_OFFSET=0x10000000`. The DTB is embedded
in the firmware read-only section and OpenSBI relocates it to `0x90000000`
before entering Linux; this is a relocation destination, not a file offset
that the JTAG loader must populate separately. The payload binary therefore
must be loaded contiguously from `0x80000000` without a second DTB write.

`sw/dts/rv64fpga-model.dts` 现提供 xsim 首版的 OpenSBI/Linux 设备树输入，包含单核
RV64IMA、Sv39、CLINT、PLIC、轮询 UART 和 512 MiB DDR3 模型窗口。生成的 DTB 仍需由
OpenSBI/Linux 镜像流程显式装载到 DDR3；板上实际容量确认后再调整 memory 节点大小。
在没有安装 `dtc` 的开发环境中，`make dts` 使用 `tools/build_model_dtb.py` 生成等价的
FDT v17 二进制，并由 Python 单测校验头部、节点和内存大小。

`./scripts/run-xsim.sh uart_rx` 验证 16550 风格 RX 的中心采样、LSR/IIR 状态、溢出和帧错误；
该测试不替代实际 UART 管脚、电气时序或 Linux 长时间串口压力测试。

`./scripts/run-xsim.sh soc_linux_handoff` 验证 ROM 到 DDR3 payload 的实际取指、延迟等待、
`a0/a1` 启动参数保留和 LED MMIO 结果。它是 Linux/OpenSBI 装载前的 handoff smoke test，
不等价于 Linux 内核启动。

该回归还覆盖了慢速 DDR3 数据 miss 与指令响应并行等待的情况；cache response 保持握手
避免核心在两类事务完成时发生响应丢失或复位循环。

`./scripts/run-xsim.sh soc_sbi` 验证 S-mode ecall 进入 M-mode handler、按 SBI 约定推进
`mepc` 并通过 `mret` 返回；它是 OpenSBI 接入前的 trap/ABI smoke test，不等价于 Linux 启动。

## JTAG DDR3 loader preparation

`rv64_mig_soc_top` contains a 32-bit AXI4 JTAG loader which holds the CPU in
reset after FPGA configuration. A 256-cycle `clk_50` startup reset initializes
the loader even when the board reset input is already inactive during FPGA
configuration. Its control register is at `0x7fff_ff00`:
bit 0 is the CPU reset hold, bit 1 reports a synchronized MIG calibration
status, and bit 2 reports that the CPU has been released. DDR3 transactions are
rejected until bits 0 and 1 are set. While the hold is set, the loader
exclusively owns the DDR3 request path. A write of zero to bit 0 releases the
CPU, sets bit 2, and permanently rejects later control or DDR3 JTAG writes
until the next FPGA reset, preventing CPU/JTAG memory contention.

The loader accepts 32-bit aligned AXI4 INCR bursts of up to 256 words. Each
word is serialized through the existing 64-bit DDR3 transaction contract;
addresses ending in `0x0` select the low lane and addresses ending in `0x4`
select the high lane. `./scripts/run-xsim.sh jtag_axi_loader` verifies the
default reset hold, calibration-unavailable rejection, DDR3 response error,
both lanes, two-word read/write bursts, malformed burst rejection and the
post-release access rejection.

The generated JTAG AXI IP has explicit read and write transaction queue depths
of 16. The Hardware Manager loader submits at most 16 transactions per queue;
the IP setting and Tcl batching limit must be changed together.

The SoC DDR arbiter and behavioral DDR model use offsets relative to
`0x80000000`, while the external MIG endpoint uses full physical addresses.
`rv64_bram_soc` adds the DDR base exactly once at that boundary. The
`soc_ddr3_external` regression checks the asymmetric base case explicitly:
an internal offset of zero must appear as `0x80000000`, never zero, at the
external endpoint.

`scripts/load-rv64-linux-jtag.tcl <payload.bin> <debug-probes.ltx> ?sample-count?`
is a Hardware Manager action script for a previously configured loader bitstream
and matching debug probes. Every Hardware Manager session supplies the matching
`.ltx` explicitly, sets `PROBES.FILE`, and refreshes probe metadata before it
discovers the ILA. It selects the probe named `cpu_reset` (ILA port `probe1`). It
performs a
four-word DDR3 round trip at `0x8ff00000`, writes
`build/linux/rv64fpga-fw_payload.bin` at `0x80000000` using 256-word bursts,
uniformly samples the payload back, arms an ILA low-level trigger on `cpu_reset`,
and only then releases the CPU. It waits for the ILA trigger and saves the
capture as `rv64-linux-cpu-startup.csv` beside the payload. The script reports
success only when Hardware Manager returns a capture object and the CSV contains
at least one sample row; a timeout, empty upload, or header-only CSV is a hard
failure. Vivado interprets `wait_on_hw_ila -timeout` in minutes, so the loader
uses a one-minute hardware timeout. It must not be run before a user explicitly confirms the
synthesis/programming gate.

Before loading Linux, run `make jtag-smoke-image` and use the same loader Tcl
with `build/boot/jtag-smoke.bin`. The payload emits ASCII `J` through the
internal UART and writes LED value `0b101` before looping. A successful ILA
capture is the first board-level proof that JTAG loading, CPU reset release,
DDR3 instruction fetch and UART TX form one working path. It is intentionally
not Linux evidence; only after it passes should the larger OpenSBI payload be
loaded.

When this loader design is built, call `write-rv64-mig-bitstream.tcl` with its
optional `.ltx` argument, then call `program-jtag-bitstream.tcl` with the same
`.ltx` and pass that `.ltx` again to `load-rv64-linux-jtag.tcl`. The loader
refuses to release the CPU if Hardware Manager cannot find both the JTAG AXI
core and the ILA probe metadata.

The generated `rv64_debug_ila` is clocked solely by `clk_50` and uses five
probes, the limit of the available Vivado BASIC debug license. Probe 0 is
`uart_tx`; probe 1 is synchronized `cpu_reset` and supplies the low-level startup
trigger. Probe 2 is `debug_status[5:0]`: bit 0 calibration complete, bit 1 JTAG
CPU hold, bit 2 `reset_n`, bit 3 commit valid, bit 4 commit trap valid, and bit 5
illegal instruction. Probe 3 is `debug_commit_trace[225:0]`: bits 63:0 commit
PC, 95:64 committed instruction, 159:96 trap cause, 161:160 privilege mode,
and 225:162 SATP.
Probe 4 is `debug_memory_trace[129:0]`: bits 63:0 instruction address, bit 64
instruction ready, bits 127:65 CPU-facing DDR request address bits 62:0, bit
128 CPU request ready, and bit 129 CPU request valid. The high physical address
bit is fixed at zero for this DDR window. This keeps the probe license-compatible
while exposing the physical address and handshake needed to diagnose a stalled
cache refill. It does not make
the UART externally observable; the board's TX/RX pinout remains required for
console acceptance.

## Full payload loading status (2026-09-17)

The 28,393,448-byte Linux/OpenSBI payload was not loaded by the first full-size
hardware attempt. The loader tried to queue 16 write transactions while the
generated JTAG AXI IP still had its default write queue depth of one, and Vivado
rejected the queue before the CPU was released. Flash was not modified. The IP
generation script now sets both queue depths to 16 explicitly.

The queue-depth-16 candidate was synthesized and implemented as
`build/vivado-bitstream-linux-loader-queue16-20260917/rv64_mig_soc_top.bit`.
The routed design met timing with setup WNS `0.146 ns`, hold WHS `0.041 ns`,
zero TNS/THS, no unrouted nets, and no DRC errors. The generated artifact
SHA-256 values are:

- bitstream: `d3aefd31becb6d64329fe35d36702e8da3c0589ef5f6bd35f6261960b32b8eb9`
- debug probes: `18f19bdcaa45bea0899b32885ee2aa7c5cb2536da0fc2de3c5c7b4e5062b64e7`
- offline MCS: `a8b19bccc605615a7a3833eaa49fd6021b07716e55f8b512f6b05baff58a63ad`

The bitstream was configured into volatile SRAM only. Hardware Manager reported
DONE high and discovered one ILA plus one JTAG AXI core. The 28-byte smoke test
then observed loader status `0x3`, passed the DDR diagnostic and 7/7 payload-word
readback, observed post-release status `0x6`, and captured 4096 ILA sample rows
after the payload drove `uart_tx` low.

The loader now reads the payload in 1 KiB file chunks instead of repeatedly
slicing one complete Tcl byte string, suppresses the verbose per-transaction
Hardware Manager data dump, and reports write-loop throughput. A 65,536-byte
bounded test covering four full 16-transaction queues passed its DDR diagnostic,
16-point readback, CPU release, and UART ILA capture at `254,015 B/s`.

The complete payload, SHA-256
`4cf3c0178b344b26244237fa42402a72d7df1e3f2f5b8f3f4814f255967d5105`,
was subsequently written in 107.735 seconds at `263,548 B/s`. All 32 uniformly
spaced readback samples matched before CPU release. After release, however, the
UART ILA did not trigger during the five-minute observation window, so Vivado
returned a hard failure and did not create a capture. This proves complete JTAG
DDR loading and sampled data integrity, but it is not OpenSBI or Linux execution
evidence. Flash was not modified during any of these tests.

## LR/SC retirement validation (2026-09-18)

The RTL now retains an LR/SC reservation until the memory operation's
instruction retires (`instruction_commit && !trap_to_machine`). The asymmetric
`core_atomic` simulation covers an SC completion followed by an instruction-ready
stall. Cache line alignment, byte-lane shifting, and MISA S/U exposure are also
included in the current RTL.

The LR/SC checkpoint was synthesized and routed with Vivado 2026.1. Final routed
timing is WNS `0.345 ns`, WHS `0.042 ns`, TNS/THS `0`, with zero combinational
loops and zero DRC errors. The volatile SRAM bitstream downloaded successfully
(DONE high; one ILA and one JTAG AXI core). Artifact hashes are:

- bitstream `60821e0587daa9fb5df1c2149b72a35b5a84a05b881253fa6011fa2f8f7afe8c`
- probes `b3e1eb3a69261291f96fab42c1a6ef0ad550e15d14367f291c4a81fb0fb17345`
- offline MCS `164444e117923935195402a0b61a121335ce88e1a3f105c13f606588345021ba`

The 28,393,448-byte payload was written and all 32 distributed readback samples
matched (`149,941 B/s`). The resulting ILA capture is
`build/linux/rv64-linux-cpu-startup.csv` (SHA-256
`316d47e4df9aa141ab805ffb069acd3cd8c5af213599588357fc5f8a22fc2c7e`). This
capture currently stops in the early boot ROM with the illegal-instruction
status bit set, so it does not yet constitute Linux/OpenSBI acceptance for the
new LR/SC bitstream. Flash was not modified.

## SATP WARL Linux runtime validation (2026-09-18)

The early runtime capture exposed that the CSR accepted an unsupported Sv57
`satp.MODE` probe. The CSR now implements WARL behavior: unsupported modes leave
the entire `satp` value unchanged, while Bare and Sv39 remain writable. The
asymmetric CSR simulation and the complete M4/M5 regression pass.

The corrected design was synthesized, routed, and generated as
`build/vivado-bitstream-linux-satp-warl-20260918/`. Routed timing is WNS
`0.082 ns`, WHS `0.042 ns`, TNS/THS `0`, with zero failed/unrouted/partially
routed nets and zero DRC errors. The bitstream was loaded to volatile SRAM only;
the MCS/PRM are offline artifacts and Flash was not modified.

Hardware Manager reported DONE high with one ILA and one JTAG AXI core. The
28,393,448-byte payload passed DDR3 diagnostics and 32 distributed readback
samples (`JTAG_LINUX_LOAD_PASS`). The runtime ILA capture is
`build/linux/rv64-linux-runtime-satp-warl.csv`: all 4096 samples are in the
Linux high half (`0xffffffff80...`), supervisor mode, with `satp.MODE=8`
(Sv39), no illegal status samples, and no trap status samples. This is reliable
board-level evidence that the Linux kernel execution path reaches S-mode Sv39.
It is not yet a UART shell/init acceptance because the board console pins have
not been observed externally.

## Current Linux panic diagnosis (2026-09-19)

The Linux builder now publishes the exact generated kernel `.config` alongside
`vmlinux`, Image, DTB, and payload, and regenerates `SHA256SUMS` over all of
those artifacts.  The current published payload is
`build/linux/rv64fpga-fw_payload.bin` (SHA-256
`a7e163baf7b9b97ab412e6257b827578c460f5ab766598d3f4de0b1e5789daea`).  Its
configuration has `CONFIG_WQ_WATCHDOG` disabled and
`CONFIG_RCU_CPU_STALL_TIMEOUT=300`.

The payload was loaded into volatile DDR through the existing SRAM bitstream;
DDR diagnostics and 16 distributed readbacks passed.  ILA captures
`build/linux/rv64-linux-rearm-new.csv` and
`build/linux/rv64-linux-rearm-rcu300.csv` both show a stable Linux `panic()` /
`udelay()` loop (`0xffffffff80c98480` and
`0xffffffff80c96db0..0xffffffff80c96e0c`).  A dedicated ILA trigger for the
userspace entry PC `0x100b0` did not fire during a two-minute rearm window.
Therefore this run does not reach PID 1 or a Linux shell.  The RCU timeout
increase did not change the failure, so the cause is not established yet;
timer/SBI/early-kernel panic diagnostics remain the next investigation.

All hardware operations in this diagnosis used volatile SRAM/JTAG/DDR only;
configuration Flash was not written.

## Capture interpretation correction (2026-09-19)

`build/linux/recovered-current.csv` contains 240 committed instructions in
4096 samples, including ten commits at `0xffffffff80c96e04`. The maximum
inter-commit gap is 53 cycles; only eight samples follow the last commit.
The final `instruction_ready=0` therefore does not demonstrate a stalled
refill. The complete capture supports repeated panic/udelay execution.
Status `0x0d` is normal commit, `0x05` is no commit, and bit 4 indicates trap.

The loader rejects control writes after its first release: attempting to
hold the running CPU returned `BRESP=SLVERR`, and status remained `0x6`.
Capture scripts must check BRESP and must not claim a restart from those
writes. To capture panic entry, reconfigure volatile SRAM, load the payload
in `hold` mode, arm the exact `panic` symbol from the matching `vmlinux`,
and release once. Reading the running kernel's printk buffer through the
current loader is also unavailable because post-release DDR access is locked.

A second independent capture bug was observed on Windows Vivado Tcl: `%064b`
formats a 32-bit integer, padding the truncated value to 64 bits. A requested
PC `0xffffffff80c98480` was read back from `TRIGGER_COMPARE_VALUE` as
`0x0000000080c98480`. Use `%064llb` for explicit 64-bit conversion. The
fresh panic-entry attempt using the old formatter timed out, while an
unfiltered commit capture (`current-after-fresh-20260919.csv`) confirms the
same panic/udelay loop. That timeout is not evidence against panic execution.

The explicit-width formatter was verified on the running board:
`build/linux/pc-compare-fixed-20260919.csv` triggered immediately at
`0xffffffff80c98480`, after the 32-bit version timed out on the same loop.
Configure ILA control settings after `reset_hw_ila`, which also resets the
trigger position. The new debug-only build completed synthesis and routing:
WNS `0.320 ns`, WHS `0.039 ns`, zero TNS/THS, and bitgen DRC reported zero
errors. Artifacts are in `build/vivado-bitstream-debug-memory-20260919/`:

- bitstream SHA-256 `eea310d73a4385f45a8ac21672ea56b4679b4196a698513c6b884f8081abf2aa`
- probes SHA-256 `5a577abbf97c65bfebe92c37e4a3ef9af07ec4f1fc9aed6f88f75cad4eefbc84`

This build is not yet the hardware baseline for the DT experiment; that uses
the previously routed SATP WARL bitstream so the software comparison keeps
the FPGA implementation constant.

## ISA device-tree root-cause comparison (2026-09-19)

The baseline kernel disables `CONFIG_RISCV_ISA_FALLBACK`, but its DT exposes
only deprecated `riscv,isa = "rv64ima"`. Linux `riscv_early_of_processor_hartid`
rejects that CPU node, and `setup_smp` hits `BUG_ON(!found_boot_cpu)` at
`arch/riscv/kernel/smpboot.c:151`.

This was independently reproduced under QEMU with the exact baseline payload:

```
CPU with hartid=0 is invalid: this kernel does not parse "riscv,isa"
kernel BUG at arch/riscv/kernel/smpboot.c:151!
setup_smp+0xd8/0x198
Kernel panic - not syncing: Fatal exception in interrupt
```

The DTS and dependency-free DT builder now use `riscv,isa-base = "rv64i"`
and the extension list `i`, `m`, `a`, `zicsr`, `zifencei`. The correction does
not enable the deprecated kernel fallback. The controlled payload lives in
`build/linux-dt-isa-20260919/`; the kernel at offset `0x200000` is byte-identical
to the baseline, and OpenSBI is relinked with the updated embedded DT.
Its SHA-256 is `3afacfd2ed104c429b23be24c81639a53a45d1a4f7e807814bf70345154161b6`.
QEMU then passes CPU enumeration and reaches `Run /init as init process`.
The complete paired log is `build/linux-dt-isa-20260919/qemu-comparison.log`.
The initial-console warning remains: this minimal PID-1 test does not provide
a shell/console acceptance result. FPGA validation of the corrected payload
is still pending at this point.

### Corrected DT: first FPGA comparison

The corrected payload completed JTAG loading and 16 distributed readback
checks on the unchanged SATP WARL bitstream. The CPU was held throughout the
load, then released once after arming a U-mode + commit + `0x100b0` trigger.
The two-minute capture timed out. A subsequent unfiltered commit capture,
`build/linux-dt-isa-20260919/current-after-timeout.csv`, contains 240 commits:
200 in `udelay` and 40 in `panic`, all in S-mode. The decoded companion `.txt`
records the PCs and instructions. Therefore the DT correction alone has **not**
resolved FPGA boot. The QEMU rejected-hart diagnosis must not be presented as
an established explanation of the board's remaining panic. Capture the first
panic entry on a fresh boot to identify its caller.

The matching ELF `/init` is in the Linux-native build cache
`~/.cache/rv64fpga/build/linux/rootfs/init`, with entry `0x100b0` and first
instruction `0x00100513`; the older `build/linux/rootfs/init` is a shell script
and must not be used as the ELF artifact for this payload.

### First panic caller captured on the debug-memory bitstream

The new debug-memory bitstream was programmed into SRAM successfully, then
the same corrected payload passed DDR diagnostics and 16-point readback.
`build/linux-dt-isa-20260919/panic-entry-debug.csv` triggered at sample 4000
on `panic=0xffffffff80c98108`. Its 168 committed instructions establish:

```
die -> make_task_dead -> panic("Attempted to kill the idle task!")
```

The branch at `make_task_dead+0x34` (`0xffffffff8001cd70`) jumps to
`0xffffffff8001ce70`, loading the string at `0xffffffff813dbf38` and calling
panic at `0xffffffff8001ce7c`. This is direct hardware control-flow evidence;
the string was independently checked in matching `vmlinux`. Both
`in_interrupt()` and `panic_on_oops` branches in `die` were not taken.
The initial exception is earlier than this capture. The next trigger should
be `die=0xffffffff800050d0`, using a fresh held payload load.

Use the maintained decoder instead of the former temporary helper:

```
uv run python tools/analyze_ila_capture.py CAPTURE.csv --symbols build/linux/System.map
```

It reports commits, trap samples, inter-commit intervals, and idle tail length.
Trap cause is meaningful only with trap-valid; privilege mode is sampled live
and can reflect the destination privilege on a transition. The 40-test Python
suite passes after adding the decoder regression.

A second fresh boot captured `die` entry in `die-entry-debug.csv` (171 commits).
It proves the caller is `die_kernel_fault+0x64` at `0xffffffff8000c940`;
therefore this is an unrecoverable kernel page fault, not merely an inferred
illegal-instruction trap from the stale cause field. The next earlier trigger
is `die_kernel_fault=0xffffffff8000c8dc`. All captures and their decoded text
are under `build/linux-dt-isa-20260919/`.

`kernel-fault-entry-debug.csv` then captured `die_kernel_fault` entry with
194 commits. `fixup_exception` returned zero; `handle_page_fault+0x34c`
called `no_context.part.0`. Its unsigned branch at `0xffffffff8000c96c`
skipped to `0xffffffff8000c978`. Independent disassembly identifies this
as `bgeu a1,a5`, proving `badaddr >= 0x1000` (paging request). An initial
interpretation reversed this branch; this paragraph records the correction. The original trapping PC still precedes the capture window.
Next capture: first `do_page_fault=0xffffffff80ca9cd8`, preserving prehistory.

`page-fault-entry-debug.csv` finally captured the original trap: sample 1877,
PC `0xffffffff805856e4` (`crc32_body+0x3c`), instruction `0x00452783`
(`lw a5,4(a0)`), cause 13. Samples 1860..1876 show a physical request to
`0x90000680`, ready on sample 1876, followed immediately by trap commit.
The core maps both translation and DDR response errors to cause 13; this
is not yet proof of an MMU permission failure. Investigate DDR response
errors first with held-CPU JTAG boundary reads.

### DDR ECC boundary failure and DTB workspace initialization

With the CPU held after SRAM programming, the independent JTAG boundary test
`build/diagnostic-ddr-20260919/read-boundary.log` reports 96 reads, 32 failures:
blocks at `0x90000680` and `0x900006c0` return SLVERR, while `0x90000000`,
`0x90000600`, `0x90000640`, and the diagnostic region return OKAY. This
reproduces the CRC fault without CPU translation. MIG has ECC enabled.
The relocated FDT has totalsize `0x99e`, but meaningful structure/string data
ends at `0x660`. OpenSBI expands totalsize without writing all padding;
Linux CRC reads the padding, reaching the first untouched block at `0x680`.
Uninitialized ECC is the leading explanation; initialization and a fresh
boot are required to test it.

The Linux JTAG loader now zeros the 64 KiB OpenSBI FDT workspace starting at
`0x90000000`, then reads back the entire region before loading/releasing the
CPU. The mock checks full initialization before the first workspace read and
full verification before release. All 40 Python tests pass. Hardware retry
uses the unchanged corrected payload and debug-memory bitstream; results pending.

The 64 KiB hardware initialization and full readback passed on the first
retry (`load-ecc-init.log`, `JTAG_DTB_WORKSPACE_INIT_PASS`). The generated MIG
`axi_mc_r_channel` connects its read-data FIFO ECC-error bit to SLVERR; the
`axi_mc` instance feeds the OR of `mc_app_ecc_multiple_err` into that bit.
The loader regression also injects corruption in the final workspace word
and checks that verification fails before a success marker or CPU release.

The first initialized-workspace boot still failed the two-minute U-mode entry
trigger. `current-after-ecc-init.csv` shows 264 commits (216 `udelay`, 48
`panic`), no trap commits in that window. Thus this is not a completed boot
fix. The retained cause field is 2 rather than 13, but is not valid exception
evidence without trap-valid. Next experiment: fresh load with workspace
initialization, triggering the first S-mode illegal-instruction exception.

### Second blocker: upper-lane word atomics on the DDR port

The first-S-illegal trigger did not fire after the second fully verified load;
the wait was stopped and `current-after-ecc-second.csv` again showed panic.
After SRAM reconfiguration, without overwriting DDR, JTAG read the static
128 KiB printk buffer at PA `0x81b27dd0` (VA `0xffffffff81927dd0`). Metadata
at PA `0x81b11d20` confirms `prb`, `log_buf_len=0x20000`, and `log_buf` still
refer to the static ring. Artifacts: `build/diagnostic-ddr-20260919/printk.bin`,
`printk-words.txt`, `printk.txt`, `read-printk.tcl`, and `read-printk.log`.
The text extraction is a printable-string view, not a record-aware decoder;
padding can duplicate trailing characters. The complete oops nevertheless
identifies the new failure unambiguously:

```
start_kernel -> init_IRQ -> sbi_ipi_init -> riscv_ipi_set_virq_range
 -> riscv_ipi_enable -> enable_percpu_irq -> ipi_mux_unmask
EPC ffffffff800a40e8, instruction 40e7a02f (amoor.w zero,a4,(a5))
badaddr ffffffd61efee704, cause 13
```

The log has progressed past DT parsing, ISA detection, memory setup, and RCU
initialization. The original CRC failure is therefore bypassed by workspace
initialization. The new address is naturally aligned for a 32-bit AMO but
not for the 64-bit DDR port. `rv64_bram_soc` forwarded atomic addresses without
alignment or lane adjustment; the external adapter rejects address bits
[2:0] != 0. Even the permissive DDR model silently operated on the wrong lane.
The corrected SoC aligns the DDR address, shifts write data and strobes to
the addressed lane, and shifts the returned old data back to the core.

The expanded `soc_ddr3_atomic` test first failed on the old RTL (upper-lane
AMO returned the lower word and corrupted its neighbor), then passed with
the fix. It covers both lanes, negative old values/sign extension, LR/SC,
neighbor preservation, existing 64-bit operations, and aligned DDR requests.
Hardware verification of the RTL fix remains pending.

Independent held-CPU JTAG checks of PA `0x9efee700` and its neighboring
64-byte blocks passed all 48 reads (`read-ipi-boundary.log`); the faulting
word at `0x9efee704` reads zero with OKAY. This distinguishes the new AMO
alignment failure from the earlier ECC failure. The printk descriptor/info
arrays were also read; `printk-decoded.txt` uses each record's explicit text
length and removes the padding artifacts from the initial strings view.
The `core_alignment` xsim regression passed alongside `soc_ddr3_atomic`.

The atomic-lane RTL synthesized and routed successfully in
`build/vivado-synth-atomic-lanes-20260919/` and
`build/vivado-impl-atomic-lanes-20260919/`. Final WNS is 0.298 ns, WHS 0.037 ns,
TNS/THS zero, and all specified timing constraints are met. The two synthesis
clock-group object warnings resolve when MIG is linked: the final clock
interaction report shows `clk_50` and `clk_pll_i` in asynchronous groups in
both directions. Bitstream generation and hardware acceptance are next.

### Third blocker: timer progress during unaligned-access probe

On the atomic-lane bitstream, `userspace-entry-atomic-lanes.csv` did not hit
`0x100b0`. The current commit capture contains 608 commits, all in
`check_unaligned_access`, repeatedly executing the kernel's intentional
`div a4, zero` wait and polling `jiffies`. This is a different state from the
old panic loop: `init_IRQ` and the IPI mux AMO now complete. The next hardware
investigation is CLINT timer delivery/CSR interrupt state; the RTL CLINT
increments `mtime` each CPU clock and compares it with `mtimecmp`, but no
jiffies transition was observed during this probe window. No claim of Linux
userspace entry is made yet.

The timer hypothesis is not yet proven. Existing `soc_sbi` passes, and the
CLINT timer regression reaches its handler, although its `mepc` expectation
is stale by one instruction (`0x18` vs `0x1c`). The hardware trace still shows
no progress beyond the `jiffies` polling loop; inspect OpenSBI timer programming
and the effective CLINT timebase/clock ratio next.

### Minimal Linux configuration for FPGA bring-up

The current bring-up uses a full RISC-V `defconfig`, which enables drivers and
subsystems for hardware that is not present on this single-hart FPGA SoC. A
mini-rv32ima-style configuration is a useful reference for reducing that
surface: disable unaligned-access benchmarking, PMU SBI, CPU frequency/idle,
USB, storage, PCI and networking until the minimal kernel reaches `init`.
The configuration must be adapted to this design rather than copied verbatim:
this core is RV64 with Sv39, DDR3 at `0x80000000`, OpenSBI, CLINT timer, PLIC,
and an NS16550-compatible UART, whereas mini-rv32ima targets RV32 and commonly
has no MMU. The acceptance criterion remains a hardware ILA hit at userspace
entry `PC=0x100b0`; restoring optional subsystems can happen only after that
minimal path is demonstrated.

The latest `minimal2` payload was loaded and verified on the XC7K480T. A 4096-
sample commit capture, resolved against the matching payload `System.map`, reaches
timer interrupt handling and then repeatedly enters the normal single-hart idle
path (`do_idle`, `tick_nohz_idle_stop_tick`, `rcu_preempt_deferred_qs`) with zero
trap samples. A hardware trigger armed for `PC=0x100b0` did not fire during the
observation window. This rules out the earlier unaligned-access loop as the current
stop point, but does not prove a userspace handoff. The UART trigger used in that
check is level-sensitive and fires on the idle UART level, so it is not treated as
userspace evidence.

The mini-rv32ima Linux configuration remains a reference for reducing driver
surface only. Its RV32/no-MMU assumptions cannot be copied to this RV64/Sv39
platform; the minimal configuration must retain MMU, CLINT, PLIC, NS16550,
initramfs and the OpenSBI handoff while removing unrelated device drivers. The
hardware acceptance condition remains an ILA match for the full 64-bit commit PC
`0x00000000000100b0`.

### Fourth blocker: OpenSBI semihosting probe was decoded as illegal

The first capture from the re-arm bitstream and `minimal3` payload found a
repeatable synchronous trap at `PC=0x800189e4`, instruction `0x00100073`
(`ebreak`). The RTL classified this encoding as illegal instruction (cause 2),
so the OpenSBI semihosting probe returned to the same address indefinitely.
The decoder now recognizes `ebreak` as a legal breakpoint exception (cause 3)
and vectors it through the normal delegated trap path. A new bitstream must be
built and tested before judging the remaining Linux handoff.

The rebuilt bitstream reports cause 3 as expected, but the first post-fix
capture still repeats at the `ebreak` PC. To separate this trap-vector issue
from semihosting itself, a matching OpenSBI payload was rebuilt with
`CONFIG_SERIAL_SEMIHOSTING` disabled; that payload is being tested on the same
hardware and Linux configuration.

The no-semihosting capture now reaches the OpenSBI `sbi_ecall_handler` return
path. Its last committed instruction is `PC=0x8000d6e4`, an `sd` in the M-mode
trap context; no later commit is observed. This moves the active diagnosis from
CLINT timer delivery to completion of the corresponding DDR data transaction.
The ILA memory probe is being extended with the live `data_valid` and
`data_address` signals so the next hardware run can identify the exact stalled
request before changing the DDR handshake.

### The apparent M-mode DDR stall was only the end of the capture window

The rebuilt debug-data bitstream exposes `data_valid` and `data_address` in the
ILA. At the `PC=0x8000d6e4` store, the CPU request targets `0x80046fb8`;
`data_valid` remains asserted through sample 4087 and is deasserted at sample
4088. The DDR transaction therefore completed. The earlier trace ended on that
store because the instruction was at the edge of the finite ILA window, not
because the memory fabric was stuck.

The routed debug-data image meets timing with WNS 0.156 ns and WHS 0.042 ns.
After programming it and fully rewriting the no-semihosting payload, a current
commit capture shows Linux in S-mode with Sv39 enabled (`satp=0x80000000000816f6`)
and executing the normal idle path, including `do_idle`,
`tick_nohz_idle_stop_tick`, `ct_idle_enter`, `ct_idle_exit`, and
`rcu_preempt_deferred_qs`. No trap samples occur in that capture. This is direct
evidence of Linux idle-path execution beyond the earlier
`check_unaligned_access` observation. Idle execution alone does not prove CLINT
timer delivery; it still does not satisfy the
userspace acceptance condition.

### Current blocker: completing the init-thread handoff

A clean experiment must rewrite the entire payload before every boot. Linux
decompression and execution modify the DDR image, so merely re-arming the ILA
and releasing the CPU against DDR left by an earlier run is not a valid
from-reset test. The required sequence is: hold the CPU, load and verify the
complete payload, arm the target PC, then release the CPU.

Using that sequence, the hardware trigger reached `kernel_init` at
`0xffffffff809b2b94`. The captured path immediately calls
`wait_for_completion` and `__wait_for_common`, consistent with waiting for
`kthreadd_done`.

A subsequent clean boot armed before CPU release reached `kthreadd` at
`0xffffffff8005e874` in 11 seconds. Its prehistory contains `schedule_tail` and
`ret_from_fork`, followed by the `kthreadd` prologue and `set_task_comm`; there
are no trap samples. Linux completes `kthreadd_done` in `rest_init` before
calling `schedule_preempt_disabled`, rather than from the `kthreadd` thread.
Therefore the observed `kthreadd` entry proves that the completion call has
already executed and corrects the earlier ownership assumption.

Another clean boot triggered at `kernel_init+0x20`, PC
`0xffffffff809b2bb4`, 11 seconds after release. Its trace returns from
`wait_for_completion`, enters `kernel_init_freeable`, and reaches
`smp_prepare_cpus` and `init_cpu_topology` without a trap. This proves that PID
1 is woken and advances beyond `kthreadd_done`; the wait itself is not the
remaining blocker.

The running system subsequently remains in the normal boot-idle accounting
path with no trap samples. A further clean boot did not reach
`run_init_process=0xffffffff8099bf40` during a one-minute hardware trigger
window. The remaining boundary is therefore inside `kernel_init_freeable`,
between `smp_prepare_cpus` and the later initcall/setup sequence that precedes
`run_init_process`. The next diagnostic payload enables `initcall_debug`; its
printk ring can identify the last initcall entered and whether it returned
without requiring one cold boot per candidate function. The userspace
acceptance target remains `0x00000000000100b0` in U-mode.

This evidence also sharpens how the mini-rv32ima example should be used. Its
small Linux configuration is valuable as a checklist for removing unrelated
drivers and optional subsystems. Copying its configuration directly would
discard requirements of this machine: RV64, Sv39, the OpenSBI handoff, the
board's DDR map, CLINT, PLIC, NS16550 UART, and the initramfs. Configuration
reduction is useful only when each retained option follows this platform's DTB
and hardware contract, and every result is still judged by the ILA userspace-PC
acceptance test.

The `initcall_debug` payload did not print any `calling ...` record. The printk
ring contains only about 59 records and has not wrapped, so this is direct
evidence that PID 1 has not reached the first `do_one_initcall()` in
`do_pre_smp_initcalls()`. A clean boot then triggered at
`kernel_init_freeable+0xa0` (`0xffffffff80a017a4`) and captured the return from
`smp_prepare_cpus()`, entry into `workqueue_init()`, and the beginning of
`__kthread_create_worker()` without a trap. This moves the current boundary
from CPU topology setup into workqueue startup.

A further fully rewritten and 32-point-verified boot triggered at
`__kthread_create_on_node+0x144` (`0xffffffff8005cb50`) 11 seconds after CPU
release. The 177 committed instructions show
`wait_for_completion_killable()` returning zero, followed by loading the new
task pointer and freeing the create request; no trap occurred. Therefore the
first workqueue rescuer request is consumed by kthreadd and its new kthread
reaches `complete(done)`. The finite capture ends inside `kfree()`, so it does
not yet prove that every rescuer and initial worker is created or that
`workqueue_init()` returns. The next clean-boot boundary is
`kernel_init_freeable+0xa8` (`0xffffffff80a017ac`), immediately after the
`workqueue_init()` call.

### Timer handoff fix and current hardware artifact

Static task and stack reconstruction showed PID 1 blocked in
`wait_task_inactive()` while creating `kworker/0:0H`. The worker became
`TASK_UNINTERRUPTIBLE` and left the run queue, but its 4 ms relative hrtimer
never woke it. This identifies the remaining blocker as clockevent delivery.

The RTL previously treated the physical CLINT timer input as both MTIP and
delegated STIP, and ignored machine interrupts while executing S-mode. The
fix makes `sie`/`sip` restricted `mie`/`mip` views, routes the physical timer
only to MTIP, and applies the RISC-V cross-privilege priority rule: an enabled
M interrupt can preempt S/U code even when `mstatus.MIE=0`; OpenSBI then clears
MTIE, writes STIP, and returns to S-mode. Directed XSIM regressions pass for
CSR views, CLINT, SoC timer delivery, SBI smoke, privilege checks, and the full
MTIP-to-STIP handoff.

The corresponding hardware build is preserved in
`build/vivado-synth-irq-handoff`, `build/vivado-impl-irq-handoff`, and
`build/vivado-bitstream-irq-handoff`. Routed timing is WNS 0.159 ns and WHS
0.049 ns with zero DRC errors. The board retest below records the first
hardware run of this bitstream.

### IRQ-handoff bitstream: board retest (2026-09-26)

The IRQ-handoff bitstream was programmed into volatile FPGA SRAM over JTAG.
Vivado reported `End of startup status: HIGH` and found one ILA and one JTAG
AXI core with the matching `.ltx`. The complete 24,028,232-byte payload
(`build/linux/rv64fpga-fw_payload.bin`, SHA-256
`43cb537470d48bd3bea5a2caf0d21525ee969f1cc7e61d84656135ae5a4ed92e`)
was rewritten from CPU hold twice. Both loads passed the DDR diagnostic, the
64 KiB DTB ECC workspace initialization/readback, every 1 KiB payload chunk
readback, and 32 distributed payload samples (`JTAG_PAYLOAD_VERIFY_PASS`).

On the first clean boot, an ILA trigger requiring both committed
`PC=0x00000000000100b0` and U-mode (`mode=0`) did not fire within two minutes.
The subsequent current-commit capture showed 194 commits in the Linux S-mode
Sv39 idle path and no trap samples. A separate trap-valid trigger did not fire
within one minute. On the second fully rewritten boot, an ILA trigger at
`kernel_init_freeable+0xa8` (`0xffffffff80a017ac`), immediately after
`workqueue_init()`, did not fire within three minutes. The subsequent current
capture again showed S-mode Sv39 idle execution (200 commits, no trap samples).

The ILA timer field shows that the CLINT comparator was written at address
`0x4000` with all eight byte strobes enabled; its low 32 bits were
`0xffffffff` in both later current captures while `mtime` continued to
increment. The current probe set does not expose the comparator's high 32
bits or MTIP/STIP directly, so these captures do not isolate the interrupt
handoff failure. Board acceptance remains **not passed**: neither the
`workqueue_init()` return boundary nor the userspace PC/mode condition was
observed. The evidence is in `build/vivado-bitstream-irq-handoff/`, including
`program-20260926-retry.log`, `load-hold-20260926.log`,
`userspace-entry-20260926.log`, `current-commit-20260926.csv`,
`current-trap-20260926.log`, `program-boundary-20260926.log`,
`load-boundary-hold-20260926.log`, `workqueue-return-20260926.log`, and
`current-after-boundary-timeout-20260926.csv`.

### Fifth candidate: hardware MTIP latched through `csrs mip` (2026-09-26)

A review of `rv64_csr.sv` after the IRQ-handoff board retest found that CSR
writes to `mip` (0x344) and `sip` (0x144) replaced the whole register. OpenSBI's
M-mode timer handler runs `csr_clear(mie, MTIP)` then `csr_set(mip, STIP)`
while the CLINT MTIP line is still high. The `csrrs` read value includes the
live MTIP bit, so the write-back latched MTIP=1 into the software-writable
`mip` register. After that, MTIP stays pending when the physical comparator
drops and after `mtimecmp` is reprogrammed. The next `sbi_set_timer` enables
MTIE again and gets an immediate spurious machine timer interrupt. This does
not follow the privileged specification: MSIP/MTIP/MEIP are read-only in
`mip`, and through `sip` only a delegated SSIP may be written.

The fix limits `mip` writes to SSIP/STIP/SEIP (`0x222`), and `sip` writes to
SSIP when it is delegated. Two regressions cover it:

- `csr`: writes `0x8a8` to `mip` while MTIP is high and checks that only STIP
  persists after the line drops. It also checks that writing `sip` changes only
  SSIP and preserves STIP.
- `core_supervisor_irq`: after the full MTIP→STIP handoff, checks that MTIP is
  clear once the physical line drops and that STIP remains pending. With only
  the `mip` mask reverted, this check fails (`MTIP=1 STIP=1`). With the fix it
  passes.

`csr`, `core_csr`, `core_supervisor_irq`, `core_privilege`, `core`, `soc_irq`,
`soc_sbi`, `clint`, `soc_uart_irq` and `soc_mmu` pass on the fixed RTL.
`scripts/run-m4-regression.sh` (14 xsim runs plus 40 Python tests) and
`scripts/run-m5-model-regression.sh` (19 xsim runs) also pass.

At the time of the fix, the hardware effect was not established. A latched MTIP would normally give
a machine-timer trap storm. The 2026-09-26 idle captures contain no trap
samples, so this bug does not by itself fully explain the observed hang. It is
a real timer-path defect. The original experiment plan below was subsequently
authorized by `CONFIRM_SYNTH CONFIRM_FLASH` and executed in SRAM; see the
follow-up results below:

1. Rebuild the SoC with the corrected CSR. Keep the IRQ-handoff debug probes
   so the result can be compared with the 2026-09-26 retest.
2. Clean boot (hold, full payload rewrite and verification, arm, release) with
   a trigger at `kernel_init_freeable+0xa8`. Then rerun the U-mode
   `PC=0x100b0` trigger.
3. If `workqueue_init()` still does not return, replace a low-value ILA field
   with `mtimecmp[63:32]`, live MTIP, `mip.STIP` and `mie.MTIE/STIE`. The
   current probe set cannot separate a missing comparator write from a lost
   STIP.

### CSR-mask retest and recovered timer evidence (2026-09-26)

The completed CSR-mask build is in `build/vivado-bitstream-csr-mip-mask/`.
Routed timing meets constraints (WNS 0.057 ns, WHS 0.053 ns). Its SRAM retest
did not reach U-mode `PC=0x100b0` within two minutes or the
`workqueue_init()` return at `0xffffffff80a017ac` within three minutes.
The current-commit capture contains 197 S-mode idle commits. A later trap
trigger did not fire during its two-minute observation window. These results
do not establish whether interrupts occurred earlier in boot. The new image
has not been written to Flash.

The conversation's compact summaries incorrectly inferred that the final
printk message, `Mountpoint-cache hash table entries`, located the hang before
workqueue startup. Earlier clean-boot PC captures and the PID 1 stack instead
place execution inside workqueue startup. The 131072-byte printk dump from
September 26 matches the September 20 dump, and both payloads have SHA-256
`43cb537470d48bd3bea5a2caf0d21525ee969f1cc7e61d84656135ae5a4ed92e`.
Identical logs from the same payload do not independently establish stale
memory or the exact stopping instruction. The forced kernel command line
also explains why the DTB's command line is absent from the log.

The retained DDR snapshot has `jiffies=0x00000000fffedb08`, the initial
32-bit unsigned value widened to 64 bits (4294892296, not signed -75000).
Static per-CPU symbol addresses contain initialization templates; they cannot
be used to conclude that CPU0's timer device is uninitialized.

A fresh read using the corrected scripts passed on hardware and is preserved
in `build/resume-20260926/read-percpu.log` and `percpu-timer.txt`:

| CPU0 field | Observed value |
|---|---|
| `__per_cpu_offset[0]` | `0xffffffd69e3b0000` |
| `riscv_clock_event` live VA / PA | `0xffffffd61efecbc0` / `0x9efecbc0` |
| `event_handler` (+0x00) | `0xffffffff800deff4` = `tick_handle_periodic` |
| `set_next_event` (+0x08) | `0xffffffff8093c5d8` = `riscv_clock_next_event` |
| `next_event` (+0x18) | `4000000` ns (4 ms) |
| state / features (+0x38 / +0x3c) | `3` (ONESHOT) / `2` (ONESHOT capability) |
| `tick_cpu_device.evtdev` | `0xffffffd61efecbc0`, matching the live device |

Periodic ticks may be implemented using a oneshot device; these fields are
consistent with device setup, but do not prove a hardware interrupt arrived.
The saved binary's `riscv_clock_next_event` reads `time`, adds the delta, then
calls `sbi_set_timer`. The next investigation should trace that call through
SBI TIME and the CLINT comparator, rather than assume device initialization
was skipped.

Two diagnostic hazards were corrected or identified:

- Windows Vivado Tcl 8.6.13 uses signed 32-bit `scan %x` and truncating
  `format %x`. Sign extension corrupts a low word with bit 31 set when it is
  ORed into a 64-bit value. The old per-CPU reader accidentally reached the
  correct PA after further 32-bit truncation, while reporting a false VA.
  `rv64-jtag-addresses.tcl` now parses unsigned words, formats full addresses,
  and rejects addresses outside the expected mappings. Regression checks in
  `tests/test_jtag_addresses.tcl` pass under Linux tclsh and Windows Vivado.
- The current `build/sources/linux` and generated build headers are 7.3-rc3,
  while the archived payload/vmlinux are 6.12. For example, the newer
  `clock_event_device` has an additional function pointer before `next_event`.
  The table above uses the locally available `v6.12` header and archived
  binary, not the current source layout. The current and archived September 20
  vmlinux/System.map copies were verified byte-identical by SHA-256.

Finally, loader re-arm asserts `cpu_hold_reset`, which resets the SoC,
including CPU CSRs and CLINT. DDR remains available for inspection, but this
is not a non-destructive CPU halt. Capture timer/CSR state before re-arm, and
fully reload the payload before another boot. Existing ILA probes show only
`mtimecmp[31:0]`; a low word of `0xffffffff` does not prove the full comparator
is all ones, and the sticky write-seen flag already proves at least one write.

### Sixth candidate: absent CSR accesses falsely advertise extensions

Source inspection found that `rv64_core` checked only CSR privilege/read-only
encoding, while `rv64_csr` returned zero for unknown addresses. OpenSBI 1.6
`hart_detect_features()` probes `mcounteren`, `mcountinhibit`, and `menvcfg`
to detect the privileged version, then probes `stimecmp` to detect Sstc.
The old RTL lets all these reads succeed. Its generic platform extension
initialization ORs DTB features into the detected set, so a DTB without Sstc
does not clear this false positive. `sbi_timer_event_start()` then selects
`csrw stimecmp` instead of the CLINT callback, although that write has no
effect in this RTL. This is a concrete candidate for the unchanged CLINT
comparator; board confirmation is pending.

The core now rejects addresses outside `riscv_pkg::csr_implemented`.
`core_privilege` tests absent stimecmp, mtopi, mstateen0, tselect and a custom
CSR across all six operations plus zero-source read-only forms. The initial
six-operation test fails on the old RTL; the fixed version passes all 40
cases and checks cause, epc, tval, trap-handler execution and preservation of
the destination register. Evidence and ongoing boot experiments are in
`build/timer-call-20260926/`; the new FPGA build uses the `csr-exists` suffix.

Matching source trees were subsequently located under
`/home/ubuntu/.cache/rv64fpga/sources/{linux,opensbi}` (6.12 and 1.6), with the
exact original payload also in the corresponding cache build directory.
An optional diagnostic OpenSBI build records timer requests, comparator
readback and M-mode interrupt state in firmware DDR. Its Linux payload bytes
at offset `0x200000` were verified unchanged; it is diagnostic evidence only,
not a replacement for correcting the RTL.

#### Board confirmation of the false Sstc path (2026-09-27)

A clean boot of the instrumented OpenSBI with the unchanged Linux kernel on
the old CSR-mask RTL reached `riscv_clock_next_event` in 11 seconds. After
reset-holding the CPU, the retained firmware records showed six entries:
two `UINT64_MAX` timer requests and one finite request
`0x00000000204a541b`, each followed by the SBI-return record. There were no
CLINT callback records and no machine-timer interrupt records. The finite
request entered at time `0x204756f0` and returned with `mie=0x8a`, `mip=0`.

The same snapshot contained a non-null `timer_dev=0x80042850` and hart
extensions `0x213d`, including **SSTC=1 and SMAIA=1**, despite neither being
implemented in the RTL. Together with the matching OpenSBI branch and
instrumentation, this confirms that firmware skipped the CLINT callback in
favor of the ineffective stimecmp write. Evidence is in
`build/timer-diag-20260927/{records.txt,decoded-records.txt,features.txt}`.

The corrected `csr-exists` FPGA build meets routed timing (WNS 0.148 ns,
WHS 0.044 ns) with no DRC errors. Its bitstream SHA-256 is
`05eeba230b60132c621363f7164d658d3d1d85bb9be76d0584424319b9d38ed4`;
the `.ltx` is byte-identical to the prior CSR-mask probes. A fresh full-load
comparison with the original, uninstrumented minimal payload is running in
`build/csr-exists-boot-20260927/`. Linux acceptance is still pending.

### Normal userspace image preparation (2026-09-27)

The stack builder previously replaced `/init` with the freestanding assembly
loop unconditionally. Normal builds now retain the BusyBox shell script;
`RV64FPGA_MINIMAL_INIT=1` explicitly selects the old diagnostic PID 1 instead.
BusyBox now includes the echo/test shell builtins and sleep/cat applets, which
the previous allnoconfig-based image omitted. The initramfs includes mount
points for devtmpfs, proc, sysfs and tmpfs.

The normal init script mounts these filesystems, verifies that `/proc/uptime`
advances across sleep, then runs four child shells and checks their output
through tmpfs. It writes `USERSPACE_CHECK_PASS` to `/dev/kmsg` and the console
only after all checks pass, then enters the console shell. This marker is
an initial userspace functional check, not proof of long-duration stress or
physical UART RX. Board verification remains required.

The candidate normal image is built separately at
`/home/ubuntu/.cache/rv64fpga/build/linux-normal-20260927`; the archived minimal
payload remains the fixed input for the CSR-existence FPGA comparison.

The normal build has now completed and is separately published in
`build/linux-normal-20260927/`, with payload SHA-256
`48ebb2b53d092165abd6790d4a90b921ae61e9ad7cd0d91999f1220649e9073b`.
Content checks confirmed that its newc archive contains the exact new init
script, BusyBox binary and mount points; that archive's gzip stream is embedded
in the Image; and the Image is embedded at payload offset `0x200000` (followed
by eight zero bytes). Board verification remains pending. Use this image's own
System.map rather than the minimal diagnostic image's symbol addresses.

### Corrected CSR board run: progress and new fault (2026-09-27)

The original payload completed full per-chunk readback and 32 final samples on
`csr-exists`. The two-minute userspace trigger did not fire. A current-commit
capture at approximately three minutes showed 165 committed instructions in
`keccakf_round` / `crypto_sha3_final`, with no trap-valid samples. The retained
printk ring subsequently showed `jent_mod_init` returning successfully after
179,416,265 microseconds. Thus two minutes is insufficient for this build.
The kernel passed the old workqueue startup stop and reached XOR calibration;
retained jiffies was `0xffffb5dc` (the kernel starts jiffies near wraparound).

A new fault occurred at `xor_8regs_2+0x14`, EPC `ffffffff804d9404`, while loading
VA `ffffffd601a80000` (cause 13), followed by the PID-1-exit panic. A read-only
walk of the retained page tables, root PA `816f6000`, found:

- root entry at `816f6ac0`: `0000000027fffc01`;
- level-1 leaf at `9ffff068`: `00000000206800e7`.

That is a valid supervisor R/W/A/D 2 MiB mapping to PA `81a00000`; the faulting
address should map to PA `81a80000`. This snapshot does not establish whether
the fault came from a walk/TLB error or a bus response (the current core reports
both through its page-fault input). A fresh reproduction and targeted capture
are in progress. Linux/userspace acceptance has **not** passed.
Evidence: `build/csr-exists-boot-20260927/{load.log,current.csv,current.txt,walk.log}`
and `state/{jiffies.txt,printk-words.txt,printk-strings.txt}`. The strings extraction
can contain stale alignment bytes after messages; retain the raw words.

The second clean original-payload boot reproduced the same fault. The ILA
captured the first `ld` at `xor_8regs_2+0x14`, then Linux's `new_vmalloc` retry
path including `sfence.vma`, then a second cause-13 trap at the same PC/VA.
No intervening interrupt is present in that capture. Evidence:
`xor-fault.csv`, `xor-fault.txt`, and `state2/` in the same directory.

A separate 4,888-byte board microtest initializes the same root/leaf mappings,
uses the actual XOR machine code and the same virtual stack page, and XORs two
identical 4 KiB buffers. It completed in S-mode and returned via the intended
ECALL (cause 9, EPC `ffffffff804d94a4`); all 1,024 output words were zero.
`build/xor-board-20260927/` contains source, ELF, binary, load and result logs.
The isolated simulation also passes with a vmalloc stack. This rules out a
standalone failure of that code/address combination, but not a fault depending
on earlier Linux state. An isolated staged FPGA build now replaces the timer
probe with live data-MMU PTE/permission/error signals; its layout and sources
are under `build/mmu-trace-source-20260927/`. Functional RTL is unchanged by
this diagnostic build. Normal userspace and flash deployment remain pending.

### Normal image reaches the init exec path (2026-09-27)

The first normal-image boot on `csr-exists` progressed beyond XOR calibration,
completed the initcalls, freed init memory, and printed `Run /init as init
process`. Its XOR-PC capture was a **machine timer interrupt (cause
0x8000000000000007), not a load page fault**. The temporary trigger has now been
restricted to cause 13. The earlier two original-image captures really did
show cause 13; do not generalize them to this normal-image run.

No `USERSPACE_CHECK_PASS` was found in the normal run's retained printk ring.
The log warned that the initial console could not be opened. The rootfs lacked
`/dev/console` before PID 1 mounted devtmpfs. The builder now includes console
(5:1) and null (1:3) device entries via a gen_init_cpio manifest, requiring no
host mknod privilege. A separate console-corrected image is being built.
Evidence: `build/normal-boot-20260927/{xor-fault.txt,state/printk-strings.txt}`.

The MMU diagnostic bitstream completed with routed WNS 0.035 ns, WHS 0.039 ns,
and no DRC errors. SHA-256:
`7a18ba8108a986287393d8159f276317046826ca1d89a1c65fe5a9491f5992f2`.
It is programmed in SRAM; the unchanged first normal payload is being loaded
again to observe BusyBox entry PC `0x10144` in committed U-mode and then inspect
live execution. This diagnostic build is not a flash release.

### BusyBox entry and unresolved userspace progress (2026-09-27)

The MMU trace run captured committed U-mode PC `0x10144` at 18:40:11,
about 4 minutes 47 seconds after release. Sixteen userspace instructions were
followed by an instruction page fault at `0x30e88`; this can be a normal demand
fault. Later captures still showed page-fault handling and timer interrupts.
An explicit cause-12 trigger timed out after one minute, so repeated instruction
faults have not been established. After CPU reset/hold, the retained user leaf
for `0x30e88` was `0x2400705b` (valid U/R/X/A). The printk ring still ended at
`Run /init as init process`, with no userspace selftest marker.
Evidence: `build/mmu-normal-boot-20260927/{user.txt,current.txt,current2.txt,
walk-user.log,state/printk-strings.txt}`.

The console-corrected payload is complete and its embedded archive was verified:
SHA-256 `a628d739233f76944184781a1792cd78e6cf1071839828eec17262a6cf62c5dc`.
A fresh load and U-mode entry capture are running under
`build/console-boot-20260927/`. No new build has been flashed.

### Page-table write acknowledgement isolation (2026-09-27)

A directed SoC simulation reproduced a second RTL defect. The shared page-table
port sends both reads and hardware A/D writes, but `instruction_pte_ready` and
`data_pte_ready` previously accepted either response. If a new walk began before
an earlier A-bit write completed, its acknowledgement advanced the new walk
using stale response data. With valid, nonidentity page mappings, the old RTL
produced a spurious instruction fault (cause 12) and a spurious load fault
(cause 13) in separate cases.

Both ready signals now exclude `pte_master_write_latched`. The new
`soc_pte_write` regression exercises both overlaps, checks successful execution
and the completed A-bit update, and rejects any trap. Both corrected cases pass.
Existing `soc_ddr3_mmu`, `soc_mmu_user_diff`, and `soc_linux_handoff` tests also
pass. Negative controls and corrected logs are under
`build/pte-write-overlap-20260927/`. This establishes an RTL bug and its simulated
fix; attribution of the Linux board stall remains pending hardware retest.
The isolated `pte-fix` bitstream is being built with the same MMU debug layout.

### Console-image panic and stale BusyBox configuration (2026-09-28)

The console-corrected image on the MMU observation bitstream reached U-mode
`0x10144`, then demand-faulted at `0x29d4c`. Subsequent one-minute triggers found
no new U-mode commits, load faults, or fetch faults. Current captures finally
identified `panic()` and its delay loop. The retained printk ring reports
`Attempted to kill init! exitcode=0x00000200` through `do_trap_ecall_u`: PID 1
explicitly exited with status 2. This was not evidence of a continuing page-fault
loop. Evidence: `build/console-boot-20260927/progress/` and `state/`.

Executing the exact archived BusyBox with QEMU reproduced `can't open 'sh':
No such file or directory` and exit 2 for the intended `busybox sh` invocation.
Although `.config` enabled the required applets, `include/autoconf.h` disabled
them and `NUM_APPLETS.h` contained 1. The binary only contained `sh`.
The generated header timestamp was about 55 seconds newer than the edited
configuration. Thus the earlier archive byte checks were valid but insufficient:
they did not check that the executable implemented the requested applets.

The builder now removes generated configuration headers after editing `.config`,
explicitly runs `oldconfig`, and checks the installed applet list for sh, mount,
sleep, and cat. A corrected image is building in `linux-applets-20260928` and
will be checked in QEMU before hardware loading.

The independent PTE response fix completed implementation: WNS 0.029 ns,
WHS 0.050 ns, no DRC errors; bitstream SHA-256
`24895f6c42fb7946ca0ccff4192ece0f6f2ff5ef47f2b31817412705e3301a2b`.
It has been programmed in SRAM and is loading the unchanged console image
for comparison. This hardware fix does not repair the BusyBox build defect.

### Store-conditional fault classification (2026-09-28, pending validation)

The applet-corrected payload SHA-256 is
`039af4ddea75f59c3b0829482661649a992d2363142c902384af91619bcd0f32`.
Its full JTAG load passed; U-mode entry was captured at 09:28:53. A subsequent
live capture shows `sc.w.aqrl a0,a5,(a2)` (`0x1ef6252f`) at user PC `0x31d4c`
reported as **cause 13**, although the data MMU correctly identified a store
(access 2). The preceding LR read PTE `0x203900d3` at PA `0x81bee2c0`: valid,
user-readable, with W clear. Execution returned from the fault handler and
retried LR/SC. PC maps to BusyBox/musl `nontrivial_free`.

The core classified page faults using only ordinary-store decode, excluding
SC and AMOs. Linux sets FAULT_FLAG_WRITE only for cause 15, so this prevents
write/COW handling on this path. RTL now reports cause 15 for SC and all
read-modify-write AMOs, retaining cause 13 for LR. `core_atomic` now contains
22 injected page-fault cases (all supported atomic operations, W/D widths).
**These new tests and the new RTL have not yet been simulated or built.**

Evidence: `build/applets-boot-20260928/progress/{user.txt,loadfault.txt,
loadfault-mmu.txt}`. The current board still uses the previous PTE-response
fix bitstream. The environment switched to restricted execution; a new
`pwsh.exe` invocation failed with WSL `UtilBindVsockAnyPort ... socket failed 1`
before Vivado could run. No DDR reset/read was performed, no userspace selftest
marker has been recovered, and Linux acceptance remains incomplete.

### Atomic fault regression confirmed (2026-09-30)

Windows execution is restored (PowerShell 7.6.4 and xsim work). The new atomic
fault cases were run against both revisions: the prior core fails all 20 SC/AMO
W/D cases with cause 13 instead of 15; the corrected core passes all 22 cases,
including LR W/D retaining cause 13. Logs:
`build/atomic-fault-check-20260928/{baseline.log,fixed.log}`.
The atomic-fault bitstream build has started; hardware acceptance remains pending.

### Linux userspace selftest passed on hardware (2026-09-30)

The atomic-fault correction completed implementation with WNS **0.158 ns**,
WHS **0.036 ns**, and no DRC errors. The SRAM-programmed bitstream is
`build/vivado-bitstream-atomic-fault/rv64_mig_soc_top.bit`, SHA-256
`c3a12d2efb1d10e2c5ef6bf8af7b93d3f8aad57d974595ce121bd33c0d039b10`.
The payload remains the applet-corrected `039af4dd…` image identified above.
The corrected atomic test passes all 22 injected cases; `core_privilege`,
`soc_mmu_user_diff`, and `soc_pte_write` also pass.

The first complete hardware run is archived in
`build/atomic-fault-boot-20260930/`. Its retained printk buffer, read at
12:02:51 Singapore time and decoded on continuation, contains:

```text
RV64FPGA initramfs booted
RV64FPGA timer progressed: 278.12 -> 280.34
RV64FPGA USERSPACE_CHECK_PASS proc sysfs tmpfs sleep fork exec wait
```

Evidence: `state/printk-words.txt` (raw), `state/printk.bin`, and
`state/printk-strings.txt`. The decoded buffer contains no
`Kernel panic - not syncing`, `RV64FPGA USERSPACE_CHECK_FAIL`, or
`Unable to handle kernel`. This proves real BusyBox userspace mounted the
filesystems, observed timer progress across sleep, wrote/read tmpfs, and
completed four child shell execution/wait cycles on the FPGA. It is stronger
than the earlier U-mode entry capture alone. Post-selftest live captures
include Linux clock-event programming and OpenSBI calls.

Reading DDR resets and holds the CPU. A clean reload/restart is now running
under `build/atomic-fault-final-20260930/` to leave Linux executing after
acceptance; its completion must be checked separately. The previous Linux
supervisor did not survive the turn interruption and had not performed this
restart. The new bitstream has **not** been written to flash. Physical UART
input and prolonged stability testing remain outside the evidence above.

The first run's three post-selftest captures were decoded with the matching
Linux `System.map`: `current1` records `tmigr_cpu_new_timer` and MTIP
(cause `0x8000000000000007`), `current2` records `tick_nohz_idle_stop_tick`,
`default_idle_call`, and `arch_cpu_idle`, and `current3` records
`clockevents_program_event`, `riscv_clock_next_event`, and the expected S-mode
SBI ecall (cause 9). Their `.txt` decodes are archived beside the raw CSVs.
These snapshots show continued timer/idle execution after userspace selftest.

### Clean restart completed; CPU left running (2026-09-30)

The final run completed at 16:45:11 Singapore time (Windows Vivado log).
`build/atomic-fault-final-20260930/load.log` records all 24,028,232 bytes
loaded with chunk readback plus 32 final verification samples. User entry
`PC=0x10144`, privilege 0, committed successfully at 16:41:48.
The following one-minute load-fault and fetch-fault observation windows had
no matches. Three current captures at 16:45:11 show `timekeeping_update` /
`update_vsyscall`, `hrtimer_interrupt` / `__hrtimer_run_queues`, and
`get_next_timer_interrupt` / `tick_nohz_next_event`, respectively. These
captures show continued kernel timer execution several minutes after entry.
No panic path appears in the captured execution.

Raw captures and matching-symbol decodes are saved under the final run's
`user.csv`, `user.txt`, and `progress/`. `acceptance.log` records the first
run's selftest verification and final restart completion. The second run was
not reset to reread printk: the exact selftest marker comes from the first
run with the same verified bitstream/payload; the final run supplies clean
reload, repeated user entry, and continued execution evidence. CPU is left
running in SRAM, with flash unchanged.
