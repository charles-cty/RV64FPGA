#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}"
source_root="${RV64FPGA_SOURCE_ROOT:-${cache_root}/rv64fpga/sources}"

fetch_source() {
  local name="$1"
  local url="$2"
  local tag="$3"
  local revision="$4"
  local destination="${source_root}/${name}"

  if [[ ! -d "${destination}/.git" ]]; then
    git init "${destination}"
    git -C "${destination}" remote add origin "${url}"
  fi

  git -C "${destination}" fetch --depth 1 origin "tag" "${tag}"
  git -C "${destination}" checkout --detach "${tag}"

  local actual_revision
  actual_revision="$(git -C "${destination}" rev-parse HEAD)"
  if [[ "${actual_revision}" != "${revision}" ]]; then
    printf 'unexpected revision for %s: %s\n' "${name}" "${actual_revision}" >&2
    exit 1
  fi
}

mkdir -p "${source_root}"
fetch_source opensbi https://github.com/riscv-software-src/opensbi.git v1.6 bd613dd92113f683052acfb23d9dc8ba60029e0a
fetch_source linux https://github.com/torvalds/linux.git v6.12 adc218676eef25575469234709c2d87185ca223a
fetch_source busybox https://git.busybox.net/busybox 1_36_1 1a64f6a20aaf6ea4dbba68bbfa8cc1ab7e5c57c4
fetch_source musl https://git.musl-libc.org/git/musl v1.2.5 0784374d561435f7c787a555aeab8ede699ed298

printf 'LINUX_SOURCES_READY=%s\n' "${source_root}"
