#!/usr/bin/env bash
set -euo pipefail

test_name="${1:-alu}"
script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_root="$(cd -- "${script_directory}/.." && pwd)"
ps_script_windows="$(wslpath -w "${script_directory}/run-xsim.ps1")"
source_root_windows="$(wslpath -w "${source_root}")"

bootstrap='param([string]$ScriptPath, [string]$RootPath, [string]$TestName)
Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
$PSNativeCommandArgumentPassing = "Standard"
$PSNativeCommandUseErrorActionPreference = $true
$localScript = Join-Path $env:TEMP "rv64fpga-run-xsim.ps1"
Copy-Item -LiteralPath $ScriptPath -Destination $localScript -Force
& $localScript -SourceRoot $RootPath -Test $TestName
'

pwsh.exe -WorkingDirectory 'C:\Windows\Temp' -CommandWithArgs "$bootstrap" \
  "$ps_script_windows" "$source_root_windows" "$test_name"
