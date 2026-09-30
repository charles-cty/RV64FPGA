#!/usr/bin/env bash
set -euo pipefail

repo_root=/workspace
source_root="${RV64FPGA_SOURCE_ROOT:-/sources}"
output_root="${RV64FPGA_OUTPUT_ROOT:-${repo_root}/build/linux}"
linux_source="${source_root}/linux"
opensbi_source="${source_root}/opensbi"
busybox_source="${source_root}/busybox"
musl_source="${source_root}/musl"
linux_output="${output_root}/linux"
linux_headers="${output_root}/linux-headers"
opensbi_output="${output_root}/opensbi"
busybox_output="${output_root}/busybox"
musl_output="${output_root}/musl"
rootfs="${output_root}/rootfs"
jobs="${JOBS:-$(nproc)}"
minimal_init="${RV64FPGA_MINIMAL_INIT:-0}"
if [[ "$minimal_init" != 0 && "$minimal_init" != 1 ]]; then
  printf 'RV64FPGA_MINIMAL_INIT must be 0 or 1\n' >&2
  exit 1
fi
rv64ima_cflags="-march=rv64ima -mabi=lp64"
fdt_relocation_offset=0x10000000
musl_cross_compile="riscv64-unknown-elf-"
busybox_cflags="${rv64ima_cflags} -isystem ${musl_output}/include -isystem ${linux_headers}/include"
busybox_cc_wrapper="${repo_root}/scripts/rv64-musl-busybox-cc.sh"

for path in "${linux_source}" "${opensbi_source}" "${busybox_source}" "${musl_source}"; do
  if [[ ! -d "${path}/.git" ]]; then
    printf 'source tree is missing; run scripts/fetch-linux-sources.sh first: %s\n' "${path}" >&2
    exit 1
  fi
done

rm -rf "${opensbi_output}" "${busybox_output}" "${rootfs}"
mkdir -p "${linux_output}" "${linux_headers}" "${opensbi_output}" "${busybox_output}" "${musl_output}" "${rootfs}"

make -C "${linux_source}" O="${linux_output}" ARCH=riscv defconfig
"${linux_source}/scripts/kconfig/merge_config.sh" -m -O "${linux_output}" \
  "${linux_output}/.config" "${repo_root}/sw/linux/rv64fpga.fragment"
"${linux_source}/scripts/config" --file "${linux_output}/.config" \
  --enable NONPORTABLE \
  --disable EFI \
  --disable RISCV_ISA_C \
  --disable FPU \
  --disable RISCV_ISA_FALLBACK
make -C "${linux_source}" O="${linux_output}" ARCH=riscv olddefconfig
make -C "${linux_source}" O="${linux_output}" ARCH=riscv \
  INSTALL_HDR_PATH="${linux_headers}" headers_install

make -C "${musl_output}" distclean 2>/dev/null || true
(
  cd "${musl_output}"
  CROSS_COMPILE="${musl_cross_compile}" CFLAGS="${rv64ima_cflags}" "${musl_source}/configure" \
    --target=riscv64-unknown-elf \
    --disable-shared \
    --prefix="${musl_output}" \
    --syslibdir="${musl_output}/lib"
)
make -C "${musl_output}" -j"${jobs}"
make -C "${musl_output}" install

rm -f "${busybox_output}/.config"
make -C "${busybox_source}" O="${busybox_output}" ARCH=riscv CROSS_COMPILE="${musl_cross_compile}" allnoconfig
sed -i \
  -e 's/^# CONFIG_BUSYBOX is not set$/CONFIG_BUSYBOX=y/' \
  -e 's/^# CONFIG_STATIC is not set$/CONFIG_STATIC=y/' \
  -e 's/^# CONFIG_ASH is not set$/CONFIG_ASH=y/' \
  -e 's/^# CONFIG_MOUNT is not set$/CONFIG_MOUNT=y/' \
  -e 's/^# CONFIG_ASH_ECHO is not set$/CONFIG_ASH_ECHO=y/' \
  -e 's/^# CONFIG_ASH_TEST is not set$/CONFIG_ASH_TEST=y/' \
  -e 's/^# CONFIG_SLEEP is not set$/CONFIG_SLEEP=y/' \
  -e 's/^# CONFIG_CAT is not set$/CONFIG_CAT=y/' \
  "${busybox_output}/.config"
# The container and mounted filesystem clocks can differ. allnoconfig may
# leave generated headers newer than the edited .config, so make otherwise
# silently compiles the old, shell-only configuration.
rm -f "${busybox_output}/include/autoconf.h" \
      "${busybox_output}/include/config/auto.conf"
make -C "${busybox_source}" O="${busybox_output}" ARCH=riscv CROSS_COMPILE="${musl_cross_compile}" \
  oldconfig </dev/null
RV64FPGA_BUSYBOX_CC="${musl_cross_compile}gcc" \
RV64FPGA_MUSL_LIB="${musl_output}/lib" \
make -C "${busybox_source}" O="${busybox_output}" ARCH=riscv CROSS_COMPILE="${musl_cross_compile}" \
  CC="${busybox_cc_wrapper}" \
  CFLAGS="${busybox_cflags}" \
  -j"${jobs}"
RV64FPGA_BUSYBOX_CC="${musl_cross_compile}gcc" \
RV64FPGA_MUSL_LIB="${musl_output}/lib" \
make -C "${busybox_source}" O="${busybox_output}" ARCH=riscv CROSS_COMPILE="${musl_cross_compile}" \
  CC="${busybox_cc_wrapper}" \
  CFLAGS="${busybox_cflags}" \
  CONFIG_PREFIX="${rootfs}" install
for applet in sh mount sleep cat; do
  if ! grep -qx "/bin/${applet}" "${busybox_output}/busybox.links"; then
    printf 'BusyBox binary is missing required applet: %s\n' "${applet}" >&2
    exit 1
  fi
done
install -D -m 0755 "${repo_root}/sw/linux/init" "${rootfs}/init"
# The freestanding PID-1 loop is an explicit diagnostic option. Normal builds
# retain the BusyBox init script and its userspace checks.
if [[ "$minimal_init" == 1 ]]; then
"${musl_cross_compile}gcc" \
  -march=rv64ima -mabi=lp64 -nostdlib -nostartfiles -static \
  -Wl,-e,_start -Wl,--build-id=none \
  "${repo_root}/sw/linux/init-userspace-minimal.S" \
  -o "${rootfs}/init-userspace"
mv "${rootfs}/init-userspace" "${rootfs}/init"
fi
# devtmpfs is mounted by PID 1 below.  Keep the mount point in the
# initramfs; mounting on a missing directory fails and leaves /dev/console
# unavailable, which makes PID 1 exit before userspace can be tested.
mkdir -p "${rootfs}/dev" "${rootfs}/proc" "${rootfs}/sys" "${rootfs}/tmp"
# The kernel opens /dev/console before starting PID 1, before the init script
# can mount devtmpfs. Describe device nodes without requiring host mknod rights.
device_list="${output_root}/initramfs-devices.list"
cat > "${device_list}" <<'EOF'
nod /dev/console 0600 0 0 c 5 1
nod /dev/null 0666 0 0 c 1 3
EOF
# Keep the initramfs source tied to the output tree used by this invocation.
# In the container build, that tree is mounted at /build; using the repository
# path here can silently embed a stale host-side rootfs instead.
"${linux_source}/scripts/config" --file "${linux_output}/.config" \
  --set-str INITRAMFS_SOURCE "${rootfs} ${device_list}"
make -C "${linux_source}" O="${linux_output}" ARCH=riscv olddefconfig
# The default defconfig enables debug lockup detectors.  They can report a
# false workqueue stall while this single soft-core is still performing early
# uncached DDR3 initialization, so enforce the bring-up policy after the final
# olddefconfig pass (which otherwise restores defaults).
"${linux_source}/scripts/config" --file "${linux_output}/.config" \
  --disable SOFTLOCKUP_DETECTOR \
  --disable WQ_WATCHDOG \
  --disable RISCV_PMU_SBI \
  --disable CPU_IDLE \
  --disable CPU_FREQ \
  --disable USB_SUPPORT \
  --disable MMC \
  --disable SCSI \
  --disable ATA \
  --disable PCI \
  --disable VIRTIO \
  --disable SOUND \
  --disable SND \
  --disable SND_SOC \
  --disable PM \
  --disable SUSPEND \
  --disable HIBERNATION \
  --disable CGROUPS \
  --disable NAMESPACES \
  --disable MODULES \
  --disable NET
make -C "${linux_source}" O="${linux_output}" ARCH=riscv -j"${jobs}" Image

dtc -I dts -O dtb -o "${output_root}/rv64fpga-model.dtb" \
  "${repo_root}/sw/dts/rv64fpga-model.dts"

# The generic OpenSBI defconfig enables semihosting, whose startup probe uses
# ebreak.  This board has a real 16550 UART and no semihosting debugger, so
# generate a fresh output-tree configuration and disable that backend before
# building.  Keeping this override out of the cached source tree makes clean
# builds reproducible and avoids silently reusing an older hand-edited config.
opensbi_kconfig_dir="${opensbi_output}/platform/generic/kconfig"
mkdir -p "${opensbi_kconfig_dir}"
KCONFIG_CONFIG="${opensbi_kconfig_dir}/.config" \
OPENSBI_SRC_DIR="${opensbi_source}" \
OPENSBI_PLATFORM=generic \
OPENSBI_PLATFORM_SRC_DIR="${opensbi_source}/platform/generic" \
python3 "${opensbi_source}/scripts/Kconfiglib/defconfig.py" \
  --kconfig "${opensbi_source}/Kconfig" \
  "${opensbi_source}/platform/generic/configs/defconfig"
sed -i 's/^CONFIG_SERIAL_SEMIHOSTING=y$/# CONFIG_SERIAL_SEMIHOSTING is not set/' \
  "${opensbi_kconfig_dir}/.config"
if ! grep -qx '# CONFIG_SERIAL_SEMIHOSTING is not set' "${opensbi_kconfig_dir}/.config"; then
  printf 'failed to disable OpenSBI semihosting\n' >&2
  exit 1
fi
make -C "${opensbi_source}" O="${opensbi_output}" \
  PLATFORM=generic \
  PLATFORM_RISCV_ABI=lp64 \
  PLATFORM_RISCV_ISA=rv64ima_zicsr_zifencei \
  FW_TEXT_START=0x80000000 \
  FW_PAYLOAD_PATH="${linux_output}/arch/riscv/boot/Image" \
  FW_PAYLOAD_OFFSET=0x200000 \
  FW_PAYLOAD_FDT_OFFSET="${fdt_relocation_offset}" \
  FW_FDT_PATH="${output_root}/rv64fpga-model.dtb"

cp "${opensbi_output}/platform/generic/firmware/fw_payload.bin" \
  "${output_root}/rv64fpga-fw_payload.bin"
if ! grep -qx '# CONFIG_SERIAL_SEMIHOSTING is not set' "${opensbi_kconfig_dir}/.config"; then
  printf 'OpenSBI build changed the semihosting configuration\n' >&2
  exit 1
fi
payload_size="$(stat --printf='%s' "${output_root}/rv64fpga-fw_payload.bin")"
if (( payload_size >= fdt_relocation_offset )); then
  printf 'OpenSBI payload overlaps its FDT relocation target: payload=%d offset=%d\n' \
    "${payload_size}" "${fdt_relocation_offset}" >&2
  exit 1
fi
(
  cd "${output_root}"
  sha256sum rv64fpga-fw_payload.bin rv64fpga-model.dtb > SHA256SUMS
)
printf 'LINUX_STACK_PASS=%s\n' "${output_root}"
