#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
image_name="${RV64FPGA_LINUX_BUILDER_IMAGE:-localhost/rv64fpga-linux-builder:bookworm}"
mkdir -p "${repo_root}/build/boot"
podman run --rm --userns=keep-id --volume "${repo_root}:/workspace:Z" --workdir /workspace \
  "${image_name}" sh -ec '
    riscv64-unknown-elf-gcc -march=rv64ima_zicsr -mabi=lp64 -nostdlib -nostartfiles \
      -Wl,--no-relax,-Ttext=0x80000000 -o build/boot/ddr-scrub.elf sw/boot/ddr-scrub.S
    riscv64-unknown-elf-objcopy -O binary build/boot/ddr-scrub.elf build/boot/ddr-scrub.bin
    riscv64-unknown-elf-gcc -march=rv64ima_zicsr -mabi=lp64 -nostdlib -nostartfiles \
      -DSCRUB_END=0x80010080 -Wl,--no-relax,-Ttext=0x80000000 \
      -o build/boot/ddr-scrub-test.elf sw/boot/ddr-scrub.S
    riscv64-unknown-elf-objcopy -O binary build/boot/ddr-scrub-test.elf build/boot/ddr-scrub-test.bin
    riscv64-unknown-elf-objdump -d build/boot/ddr-scrub.elf > build/boot/ddr-scrub.dis
  '
python3 "${repo_root}/tools/bin_to_memhex.py" "${repo_root}/build/boot/ddr-scrub.bin" \
  "${repo_root}/build/boot/ddr-scrub.hex" --word-bytes 8
python3 "${repo_root}/tools/bin_to_memhex.py" "${repo_root}/build/boot/ddr-scrub-test.bin" \
  "${repo_root}/build/boot/ddr-scrub-test.hex" --word-bytes 8
printf 'DDR_SCRUB_IMAGE=%s\n' "${repo_root}/build/boot/ddr-scrub.bin"
