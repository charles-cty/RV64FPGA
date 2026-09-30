[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\vivado-impl'),
    [string]$SynthCheckpoint = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\vivado-synth\reports\rv64_mig_soc_synth.dcp'),
    [string]$VivadoBat = 'C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $true

$SourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
if (-not [System.IO.Path]::IsPathFullyQualified($OutputRoot)) {
    $OutputRoot = Join-Path $SourceRoot $OutputRoot
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
if (-not [System.IO.Path]::IsPathFullyQualified($SynthCheckpoint)) {
    $SynthCheckpoint = Join-Path $SourceRoot $SynthCheckpoint
}
$SynthCheckpoint = [System.IO.Path]::GetFullPath($SynthCheckpoint)

if (-not (Test-Path -LiteralPath $VivadoBat -PathType Leaf)) {
    throw "Vivado launcher was not found: $VivadoBat"
}
if (-not (Test-Path -LiteralPath $synthCheckpoint -PathType Leaf)) {
    throw "Synthesis checkpoint was not found: $synthCheckpoint"
}

$workDirectory = Join-Path $env:TEMP ("rv64fpga-impl-" + [Guid]::NewGuid().ToString('N'))
$stagedCheckpoint = Join-Path $workDirectory 'rv64_mig_soc_synth.dcp'
$reportDirectory = Join-Path $workDirectory 'reports'
$stagedScript = Join-Path $workDirectory 'impl-rv64-mig-checkpoint.tcl'
$vivadoLog = Join-Path $workDirectory 'vivado-impl.log'
$vivadoSucceeded = $false

$originalLocation = Get-Location
try {
    New-Item -ItemType Directory -Force -Path $workDirectory | Out-Null
    New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
    Copy-Item -LiteralPath $synthCheckpoint -Destination $stagedCheckpoint
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'scripts\impl-rv64-mig-checkpoint.tcl') -Destination $stagedScript
    Set-Location -LiteralPath $workDirectory
    & $VivadoBat -mode batch -nojournal -nolog -source $stagedScript -tclargs $stagedCheckpoint $reportDirectory 2>&1 |
        Tee-Object -FilePath $vivadoLog
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado implementation failed with exit code ${LASTEXITCODE}: $vivadoLog"
    }
    if (-not (Select-String -LiteralPath $vivadoLog -SimpleMatch 'RV64_MIG_IMPL_PASS' -Quiet)) {
        throw "Vivado implementation produced no success sentinel: $vivadoLog"
    }
    $vivadoSucceeded = $true
}
finally {
    Set-Location -LiteralPath $originalLocation.Path
    if (Test-Path -LiteralPath $reportDirectory) {
        Get-ChildItem -LiteralPath $reportDirectory -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $OutputRoot -Recurse -Force
        }
    }
    if (Test-Path -LiteralPath $vivadoLog) {
        Copy-Item -LiteralPath $vivadoLog -Destination (Join-Path $OutputRoot 'vivado-impl.log') -Force
    }
    if (Test-Path -LiteralPath $workDirectory) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $vivadoSucceeded) {
    throw 'Vivado implementation did not complete successfully.'
}
"RV64_MIG_IMPL_CHECK_PASS`t$OutputRoot"
