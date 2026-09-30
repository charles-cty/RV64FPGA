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
  "${repo_root}/sw/boot/boot.S" -o "${build_root}/boot.o"
"${objcopy}" -O binary "${build_root}/boot.o" "${build_root}/boot.bin"
uv run python "${repo_root}/tools/bin_to_memhex.py" \
  "${build_root}/boot.bin" "${build_root}/boot_rom.hex" \
  --word-bytes 4 --max-words 16384

"${cc}" --target=riscv64 -march=rv64ima -mabi=lp64 -nostdlib -c \
  "${repo_root}/sw/boot/linux-handoff.S" -o "${build_root}/linux-handoff.o"
"${objcopy}" -O binary "${build_root}/linux-handoff.o" "${build_root}/linux-handoff.bin"
uv run python "${repo_root}/tools/bin_to_memhex.py" \
  "${build_root}/linux-handoff.bin" "${build_root}/linux_payload.hex" \
  --word-bytes 8 --max-words 65536
uv run python "${repo_root}/tools/build_model_dtb.py" \
  "${build_root}/rv64fpga-model.dtb"
uv run python "${repo_root}/tools/build_sparse_memhex.py" \
  "${build_root}/linux_ddr3_image.hex" \
  "0x0=${build_root}/linux-handoff.bin" \
  "0x10000=${build_root}/rv64fpga-model.dtb" \
  --word-bytes 8
printf 'BOOT_IMAGE=%s\nPAYLOAD_IMAGE=%s\nDDR3_IMAGE=%s\n' \
  "${build_root}/boot_rom.hex" "${build_root}/linux_payload.hex" \
  "${build_root}/linux_ddr3_image.hex"
