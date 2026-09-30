#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
image_name="${RV64FPGA_LINUX_BUILDER_IMAGE:-localhost/rv64fpga-linux-builder:bookworm}"
cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}"
source_root="${RV64FPGA_SOURCE_ROOT:-${cache_root}/rv64fpga/sources}"
build_root="${RV64FPGA_LINUX_BUILD_ROOT:-${cache_root}/rv64fpga/build/linux}"
published_root="${repo_root}/build/linux"

RV64FPGA_SOURCE_ROOT="${source_root}" "${repo_root}/scripts/fetch-linux-sources.sh"
podman build --tag "${image_name}" --file "${repo_root}/containers/linux-builder/Containerfile" "${repo_root}"
mkdir -p "${build_root}"
podman run --rm --userns=keep-id \
  --volume "${repo_root}:/workspace:Z" \
  --volume "${source_root}:/sources:Z" \
  --volume "${build_root}:/build:Z" \
  --workdir /workspace \
  --env "JOBS=${JOBS:-}" \
  --env RV64FPGA_OUTPUT_ROOT=/build \
  --env RV64FPGA_SOURCE_ROOT=/sources \
  --env "RV64FPGA_MINIMAL_INIT=${RV64FPGA_MINIMAL_INIT:-0}" \
  "${image_name}" \
  ./scripts/build-linux-stack-inner.sh

install -D -m 0644 "${build_root}/linux/arch/riscv/boot/Image" \
  "${published_root}/linux/arch/riscv/boot/Image"
install -D -m 0644 "${build_root}/linux/vmlinux" \
  "${published_root}/vmlinux"
install -D -m 0644 "${build_root}/linux/System.map" \
  "${published_root}/System.map"
install -D -m 0644 "${build_root}/linux/.config" \
  "${published_root}/linux/.config"
install -D -m 0644 "${build_root}/rv64fpga-model.dtb" \
  "${published_root}/rv64fpga-model.dtb"
install -D -m 0644 "${build_root}/rv64fpga-fw_payload.bin" \
  "${published_root}/rv64fpga-fw_payload.bin"
install -D -m 0644 "${build_root}/SHA256SUMS" \
  "${published_root}/SHA256SUMS"
# Publish inputs needed by the maintained acceptance command alongside payload.
for pair in 'busybox:rootfs/bin/busybox' 'busybox.config:busybox/.config'             'busybox.links:busybox/busybox.links' 'init:rootfs/init'             'initramfs-devices.list:initramfs-devices.list'; do
  install -D -m 0644 "${build_root}/${pair#*:}" "${published_root}/${pair%%:*}"
done
(
  cd "${published_root}"
  sha256sum linux/.config linux/arch/riscv/boot/Image vmlinux System.map \
    rv64fpga-model.dtb rv64fpga-fw_payload.bin busybox busybox.config busybox.links init initramfs-devices.list > SHA256SUMS
)
