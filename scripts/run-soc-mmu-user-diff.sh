#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
trace_directory="${repo_root}/build/xsim/soc_mmu_user_diff"

"${repo_root}/scripts/run-xsim.sh" soc_mmu_user_diff
uv run python "${repo_root}/tools/differential/soc_mmu_user_program.py" "${trace_directory}/iss_trace.jsonl"
uv run python "${repo_root}/tools/differential/compare_trace.py" "${trace_directory}/iss_trace.jsonl" "${trace_directory}/rtl_trace.jsonl"
