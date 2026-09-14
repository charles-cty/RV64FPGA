#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

"${repo_root}/scripts/run-xsim.sh" ddr3_model
"${repo_root}/scripts/run-xsim.sh" ddr3_axi_adapter
"${repo_root}/scripts/run-xsim.sh" async_memory_bridge
"${repo_root}/scripts/run-xsim.sh" ddr3_mig_path
"${repo_root}/scripts/run-xsim.sh" soc_ddr3_model
"${repo_root}/scripts/run-xsim.sh" soc_ddr3_fault
