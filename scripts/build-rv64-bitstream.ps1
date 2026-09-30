[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory)][string]$BoardConfig,
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\hardware'),
    [string]$VivadoBat = 'C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat'
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $true
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$boot = Join-Path $SourceRoot 'build\boot\boot_rom.hex'
$common = @{SourceRoot=$SourceRoot; VivadoBat=$VivadoBat}
& (Join-Path $PSScriptRoot 'synth-rv64-mig-project.ps1') @common -BoardConfig $BoardConfig -BootRomImage $boot -OutputRoot (Join-Path $OutputRoot 'synth')
& (Join-Path $PSScriptRoot 'impl-rv64-mig-checkpoint.ps1') @common -SynthCheckpoint (Join-Path $OutputRoot 'synth\reports\rv64_mig_soc_synth.dcp') -OutputRoot (Join-Path $OutputRoot 'impl')
$timing = Join-Path $OutputRoot 'impl\timing_summary_routed.rpt'
if (-not (Select-String -LiteralPath $timing -SimpleMatch 'All user specified timing constraints are met.' -Quiet)) {
    throw 'Routed timing constraints were not met'
}
$bitDir = Join-Path $OutputRoot 'bitstream'
New-Item -ItemType Directory -Force -Path $bitDir | Out-Null
$arguments = @('-mode', 'batch', '-nojournal', '-log', (Join-Path $bitDir 'vivado.log'), '-source', (Join-Path $PSScriptRoot 'write-rv64-mig-bitstream.tcl'), '-tclargs',
    (Join-Path $OutputRoot 'impl\rv64_mig_soc_routed.dcp'), (Join-Path $bitDir 'rv64_mig_soc_top.bit'),
    (Join-Path $bitDir 'rv64_mig_soc_top.mcs'), (Join-Path $bitDir 'rv64_mig_soc_top.ltx'))
& $VivadoBat @arguments
if (-not (Select-String -LiteralPath (Join-Path $bitDir 'vivado.log') -Pattern '^RV64_MIG_DEBUG_PROBES_PASS ' -Quiet)) { throw 'No bitstream/probe success sentinel' }
'RV64_BITSTREAM_BUILD_PASS'
