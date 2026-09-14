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

The data and instruction caches are the two cached-DDR masters. Each presents
at most one request at a time; `rtl/rv64_ddr3_arbiter.sv` serializes them before
the MIG wrapper. A selected cache presents:

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

`rtl/rv64_ddr3_model.sv` now provides the behavioral endpoint; it accepts one
request, delays completion, preserves byte strobes, and reports an error while
`calibrated=0`. `./scripts/run-xsim.sh ddr3_model` verifies its delay,
read-after-write, byte strobe, unavailable, and pending-reset behavior. It is
not a MIG model and cannot be used as DDR3 hardware evidence.

`rv64_bram_soc` can select this endpoint with `USE_DDR3_MODEL=1`. Its modelled
DDR3 physical window is `0x0000_0000_8000_0000` through
`0x0000_0000_ffff_ffff`; lower physical addresses remain BRAM-backed. The
`soc_ddr3_model` xsim regression proves a cache write-through followed by a
delayed read miss and a read hit in that DDR3 window.

The SoC's optional model path supports instruction fetches from the same
window through an instruction cache endpoint; `rv64_ddr3_arbiter` serializes
instruction and data cache misses onto one DDR3 model instance. The
`soc_ddr3_instruction` regression verifies a BRAM-to-DDR3 jump and delayed
fetch through that shared endpoint.

The vendor-free arbiter regression (`ddr3_arbiter`) verifies alternating
instruction/data grants, payload stability, response routing, and read-after-
write behavior against the delayed DDR3 endpoint. SoC integration still uses
the same arbitration contract; the remaining step is to connect this shared
CPU-side endpoint to the CDC/MIG path.

`soc_ddr3_fault` drives the model with calibration unavailable and proves that
the core receives a precise load access fault (`mcause=13`, `mepc=0x14`,
`mtval=0x0000_0000_8000_0000`) without a destination-register write. The same
error signal will later originate from the MIG wrapper rather than this model.

`rtl/rv64_ddr3_axi_adapter.sv` is the first non-vendor portion of that wrapper.
It operates in the future MIG UI clock domain and permits one request at a
time. Because the selected MIG AXI interface is 512 bits wide and disables
narrow bursts, each 8-byte cache transaction becomes a one-beat, aligned
64-byte AXI burst: reads select the addressed 64-bit lane from `RDATA`, and
writes place data and byte strobes only in that lane. It rejects uncalibrated,
misaligned, and out-of-range transactions before issuing AXI traffic and turns
AXI response errors into the CPU-side error response. It intentionally does
not include the `clk_50`/`ui_clk` asynchronous bridge or instantiate MIG.
`ddr3_axi_adapter` xsim verifies delayed independent AW/W/AR handshakes, lane
placement, response errors, range rejection, and reset during a transaction.

`rtl/rv64_async_memory_bridge.sv` carries this same one-request contract from
`clk_50` to the future `ui_clk`. It uses request and response toggle mailboxes
with two-flop synchronization; each mailbox payload remains stable until its
receiving domain acknowledges completion. Both resets must assert together to
abort an outstanding transaction. `async_memory_bridge` xsim uses unrelated
clock periods and verifies mailbox field stability, response-error propagation,
backpressure, and reset cancellation without a duplicate response.

`rtl/rv64_ddr3_mig_path.sv` composes the CDC mailbox and UI-domain AXI adapter
behind the CPU-side memory contract. Its `ddr3_mig_path` xsim regression drives
AXI responses under unrelated CPU/UI clocks and verifies read-lane selection,
write-lane strobes, AXI error propagation, and calibration rejection. This
composition remains vendor-IP-free and is not yet connected to `rv64_bram_soc`.

Before hardware work, xsim must connect this endpoint or a protocol-equivalent
behavioral model to the future adapter. Required integration regressions are:

1. Aligned 8-byte read after arbitrary wait states.
2. Write-through byte strobe preservation across every byte position.
3. Read-after-write ordering and cache miss/refill interaction.
4. Reset during a pending transaction, with no duplicate response.
5. Calibration unavailable/error behavior, with no silent data corruption.

The same tests must run against the adapter and against the SoC integration
top before any synthesis request.

## Board Configuration Status

Machine-readable board sources now identify the first memory candidate: C0 is
one `ddr3_cs_n[0]` channel of `MT41K256M8XX-125`, with 2 GiB usable capacity,
72-bit ECC-enabled physical width, 15 row-address bits, 10 column-address
bits, three bank bits, and a 200 MHz differential reference clock on
`AH27/AH28`. The generated MIG input also contains the complete C0 pin and I/O
standard selection. `docs/bringup/mig-ch0-recipe.md` records the source file
identity and a generation recipe that rejects a modified input.

The following evidence is still required before board work or a synthesis
request:

- Generated Vivado 2026.1 IP identity, port list, and generated constraints
  match the selected C0 input.
- The CDC/AXI wrapper preserves the one-outstanding-request contract and
  passes all behavioral-model regressions.
- `init_calib_complete`, usable capacity, and long-running error behavior are
  observed on the actual board.

The recipe does not synthesize, implement, download, or flash hardware. Those
operations remain gated by `CONFIRM_SYNTH`.
