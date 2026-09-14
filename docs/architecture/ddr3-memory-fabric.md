# DDR3 Memory Fabric Contract (M5)

## Scope

The Linux-capable SoC replaces the simulation-only DRAM portion of
`rv64_bram_soc` with a MIG-backed DDR3 path. Boot ROM remains on-chip BRAM;
the CPU must not depend on PCIe clocks or XDMA before the DDR3 calibration
completes.

This document defines the boundary before generating vendor IP. It does not
claim that a MIG instance, timing constraints, or board-level DDR3 operation
exists yet.

## CPU-Side Contract

The cache memory port is the sole cached-DDR master. It presents one request at
a time:

| Signal group | Meaning |
|---|---|
| `memory_valid` / `memory_ready` | Request handshake; a request remains stable until accepted. |
| `memory_write` | `0` reads one 8-byte cache line; `1` writes selected bytes. |
| `memory_address` | Physical byte address, naturally aligned to the cache-line transaction. |
| `memory_write_data` / `memory_write_strobe` | Write-through payload and byte enables. |
| `memory_read_data` | Read response associated with the accepted read request. |

The adapter must preserve request order, never acknowledge a request before
the returned data is valid, and report a calibration/unavailable condition as
a bus error rather than fabricating read data. MMIO remains outside this path.

## MIG-Side Contract

The eventual wrapper uses the MIG AXI user interface in the MIG UI clock
domain. It requires clock-domain crossing between `clk_50` and `ui_clk`, with
independent asynchronous reset assertion and reset release only after both
domains are stable. The wrapper owns all AXI IDs and permits one outstanding
CPU transaction in the first implementation; this matches the sequential core
and makes error attribution deterministic.

DDR3 traffic is enabled only after `init_calib_complete`. Before calibration,
the boot ROM and BRAM-resident diagnostic program remain reachable; DDR3
transactions must stall or return a defined error selected by the M-mode
bootloader policy.

## xsim Model

Before hardware work, xsim must use a behavioral DDR3 endpoint that can delay
read/write completion and inject an unavailable/error response. Required
regressions are:

1. Aligned 8-byte read after arbitrary wait states.
2. Write-through byte strobe preservation across every byte position.
3. Read-after-write ordering and cache miss/refill interaction.
4. Reset during a pending transaction, with no duplicate response.
5. Calibration unavailable/error behavior, with no silent data corruption.

The same tests must run against the adapter and against the SoC integration
top before any synthesis request.

## Required Board Facts

MIG generation and top-level constraints remain blocked until these facts are
verified from machine-readable board sources or hardware feedback:

- The selected DDR3 channel, exact rank count, component width, and total size.
- The channel's clock pair and whether it is connected to the intended 200 MHz
  reference clock.
- The complete channel pinout and I/O standards accepted by the target Vivado
  board definition.
- A generated MIG configuration identity/version that matches
  `xc7k480tffg1156-2` and `MT41K256M8XX-125`.

After these are available, the next deliverable is a checked-in MIG-generation
recipe plus an xsim behavioral-model regression. Synthesis, implementation,
download, and flash programming remain gated by `CONFIRM_SYNTH`.
