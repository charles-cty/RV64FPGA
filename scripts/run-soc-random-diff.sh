#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
trace_directory="${repo_root}/build/xsim/soc_random"
expected_trace="${trace_directory}/iss_trace.jsonl"
actual_trace="${trace_directory}/rtl_trace.jsonl"
program_image="${trace_directory}/program.hex"

mkdir -p "${trace_directory}"
uv run python "${repo_root}/tools/differential/random_core_program.py" \
  "${program_image}" "${expected_trace}"
"${repo_root}/scripts/run-xsim.sh" soc_random
uv run python "${repo_root}/tools/differential/compare_trace.py" \
  "${expected_trace}" "${actual_trace}"
