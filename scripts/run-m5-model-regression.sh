#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

"${repo_root}/scripts/run-xsim.sh" ddr3_model
"${repo_root}/scripts/run-xsim.sh" ddr3_axi_adapter
"${repo_root}/scripts/run-xsim.sh" async_memory_bridge
"${repo_root}/scripts/run-xsim.sh" ddr3_mig_path
"${repo_root}/scripts/run-xsim.sh" ddr3_arbiter
"${repo_root}/scripts/run-xsim.sh" ddr3_mig_shared_path
"${repo_root}/scripts/run-xsim.sh" ddr3_mig_atomic_path
"${repo_root}/scripts/run-xsim.sh" soc_ddr3_model
"${repo_root}/scripts/run-xsim.sh" soc_ddr3_external
"${repo_root}/scripts/run-xsim.sh" soc_ddr3_mmu
"${repo_root}/scripts/run-xsim.sh" soc_ddr3_fault
"${repo_root}/scripts/run-xsim.sh" soc_ddr3_instruction
"${repo_root}/scripts/run-xsim.sh" soc_ddr3_atomic
"${repo_root}/scripts/run-xsim.sh" soc_init_files
"${repo_root}/scripts/run-xsim.sh" soc_linux_handoff
"${repo_root}/scripts/run-xsim.sh" soc_sbi
"${repo_root}/scripts/run-xsim.sh" core_supervisor_irq
"${repo_root}/scripts/run-xsim.sh" uart_rx
"${repo_root}/scripts/run-xsim.sh" soc_uart_irq
"${repo_root}/scripts/run-xsim.sh" soc_pte_write

"${repo_root}/scripts/run-xsim.sh" jtag_console

"${repo_root}/scripts/build-ddr-scrub.sh"
"${repo_root}/scripts/run-xsim.sh" ddr_scrub
