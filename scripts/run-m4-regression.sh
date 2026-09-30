#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

"${repo_root}/scripts/run-xsim.sh" core_fence
"${repo_root}/scripts/run-xsim.sh" core_privilege
"${repo_root}/scripts/run-xsim.sh" mmu
"${repo_root}/scripts/run-xsim.sh" mmu_random
"${repo_root}/scripts/run-xsim.sh" cache
"${repo_root}/scripts/run-core-diff.sh"
"${repo_root}/scripts/run-core-random-diff.sh"
"${repo_root}/scripts/run-soc-cache-diff.sh"
"${repo_root}/scripts/run-soc-random-diff.sh"
"${repo_root}/scripts/run-soc-mmu-diff.sh"
"${repo_root}/scripts/run-soc-mmu-fault-diff.sh"
"${repo_root}/scripts/run-soc-mmu-sum-diff.sh"
"${repo_root}/scripts/run-soc-mmu-user-diff.sh"
"${repo_root}/scripts/run-soc-mmu-tlb-diff.sh"
uv run python -m unittest discover -s "${repo_root}/tests" -v
"${repo_root}/scripts/run-xsim.sh" core_atomic
