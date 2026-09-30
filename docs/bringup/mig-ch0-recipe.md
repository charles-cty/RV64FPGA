# MIG C0 generation recipe

This recipe establishes the first Linux-memory candidate: one DDR3 channel
(C0), providing 2 GiB of addressable memory. It is intentionally separate from
the SoC top level, constraints, synthesis, and hardware deployment.

## Verified input identity

The input is the board pack's machine-generated `mig_0.prj`, not an edited
copy. Its SHA-256 is:

```text
baed6883dac282367f835cd71dd312d307bd0efbc786cf6f4a2a5a0909c4e23c
```

The recipe rejects a different file. The selected configuration is:

| Field | Value |
|---|---|
| FPGA | `xc7k480tffg1156-2` |
| DDR channel | C0, one chip-select (`ddr3_cs_n[0]`) |
| Memory device | `MT41K256M8XX-125` |
| Capacity | 2 GiB (`C0_MEM_SIZE=2147483648`) |
| Physical data width | 72 bits, ECC enabled |
| MIG AXI interface | 31-bit address, 512-bit data, 4-bit ID |
| Reference clock | Differential 200 MHz, `AH27/AH28` |
| DDR I/O | 15 row-address bits, 10 column-address bits, 3 bank bits |

The C0 configuration and its I/O assignments originate from
`C:\My\Projects\FPGA\LC480T\vivado 板卡文件\ypcb_00338_1p1_hack-main\ypcb003381p1\1.0\mig_0.prj`.
It must remain an externally supplied board input until its licence permits
checking it into this repository.

## Preflight

From WSL, first run the default validation-only mode. It checks the file hash
and all settings listed above; it does not invoke Vivado.

```bash
pwsh.exe -WorkingDirectory 'C:\Windows\Temp' \
  -File "$(wslpath -w scripts/create-mig-ip.ps1)" \
  -BoardConfig "$(wslpath -w '/mnt/c/My/Projects/FPGA/LC480T/vivado 板卡文件/ypcb_00338_1p1_hack-main/ypcb003381p1/1.0/mig_0.prj')" \
  -OutputDirectory 'C:\My\Projects\RV64FPGA\ip\rv64_mig_ch0'
```

Expected output is one `MIG_RECIPE_VALID` TSV record. A hash mismatch is a
stop condition: regenerate the configuration through the MIG GUI and review
the change before updating this recipe.

## Explicit IP generation

Only after the preflight succeeds, append `-Generate`. The PowerShell script
copies the configuration and Tcl recipe into a Windows-local temporary
directory, invokes Vivado there, then copies the generated IP directory back.
It creates `rv64_mig_ch0.xci` and generated IP support files only. Its Tcl
recipe contains no `synth_design`, `launch_runs`, `implement`,
`write_bitstream`, Hardware Manager, JTAG, or flash operation.

```bash
pwsh.exe -WorkingDirectory 'C:\Windows\Temp' \
  -File "$(wslpath -w scripts/create-mig-ip.ps1)" \
  -BoardConfig "$(wslpath -w '/mnt/c/My/Projects/FPGA/LC480T/vivado 板卡文件/ypcb_00338_1p1_hack-main/ypcb003381p1/1.0/mig_0.prj')" \
  -OutputDirectory 'C:\My\Projects\RV64FPGA\ip\rv64_mig_ch0' \
  -Generate
```

This is not evidence of calibration, timing closure, or valid DDR3 traffic.
Before any `CONFIRM_SYNTH` request, inspect the generated XCI's target part,
MIG version, ports, and generated constraints; then connect the future
single-outstanding-request CDC/AXI wrapper to the existing behavioral-model
regressions.
