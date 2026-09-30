# Linux device-tree input

`rv64fpga-model.dts` describes the xsim platform used by the boot handoff
regressions: one RV64IMA hart, Sv39, the CLINT and PLIC windows from the
platform map, the polling UART, and a 512 MiB DDR3 model window.

The repository includes a dependency-free generator for the fixed model tree:

```bash
make dts
```

The generated DTB can also be replaced by an external device-tree compiler
when preparing an OpenSBI or Linux image:

```bash
dtc -I dts -O dtb -o rv64fpga-model.dtb rv64fpga-model.dts
```

The model memory size is intentionally separate from the board's eventual
measured DDR3 capacity. Update only the `memory@80000000` `reg` size after the
MIG calibration and capacity test are complete.
