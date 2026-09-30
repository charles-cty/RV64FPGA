#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
trace_directory="${repo_root}/build/xsim/core"
expected_trace="${trace_directory}/iss_trace.jsonl"
actual_trace="${trace_directory}/rtl_trace.jsonl"

"${repo_root}/scripts/run-xsim.sh" core
uv run python "${repo_root}/tools/differential/core_program.py" "${expected_trace}"
uv run python "${repo_root}/tools/differential/compare_trace.py" "${expected_trace}" "${actual_trace}"
