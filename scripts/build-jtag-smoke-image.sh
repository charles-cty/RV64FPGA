#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${repo_root}/build/boot"
cc="${RISCV_CLANG:-clang-18}"
objcopy="${LLVM_OBJCOPY:-llvm-objcopy-18}"

command -v "${cc}" >/dev/null || { echo "missing compiler: ${cc}" >&2; exit 1; }
command -v "${objcopy}" >/dev/null || { echo "missing objcopy: ${objcopy}" >&2; exit 1; }
mkdir -p "${build_root}"

"${cc}" --target=riscv64 -march=rv64ima -mabi=lp64 -nostdlib -c \
  "${repo_root}/sw/boot/jtag-smoke.S" -o "${build_root}/jtag-smoke.o"
"${objcopy}" -O binary "${build_root}/jtag-smoke.o" "${build_root}/jtag-smoke.bin"
uv run python "${repo_root}/tools/build_sparse_memhex.py" \
  "${build_root}/jtag_smoke_ddr3_image.hex" \
  "0x0=${build_root}/jtag-smoke.bin" \
  --word-bytes 8
printf 'JTAG_SMOKE_IMAGE=%s\nJTAG_SMOKE_DDR3_IMAGE=%s\n' \
  "${build_root}/jtag-smoke.bin" "${build_root}/jtag_smoke_ddr3_image.hex"
