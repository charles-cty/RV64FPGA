#!/usr/bin/env bash
set -euo pipefail

compiler="${RV64FPGA_BUSYBOX_CC:?RV64FPGA_BUSYBOX_CC is required}"
musl_lib="${RV64FPGA_MUSL_LIB:?RV64FPGA_MUSL_LIB is required}"

for argument in "$@"; do
  case "${argument}" in
    -c|-E|-S|-r)
      exec "${compiler}" "$@"
      ;;
  esac
done

exec "${compiler}" \
  -static \
  -nodefaultlibs \
  -nostartfiles \
  "${musl_lib}/crt1.o" \
  "${musl_lib}/crti.o" \
  "-L${musl_lib}" \
  "$@" \
  -lc \
  -lgcc \
  "${musl_lib}/crtn.o"
