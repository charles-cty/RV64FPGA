[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$VivadoBat = 'C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $true

if (-not (Test-Path -LiteralPath $VivadoBat -PathType Leaf)) {
    throw "Vivado launcher was not found: $VivadoBat"
}
if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "source root was not found: $SourceRoot"
}

$workDirectory = Join-Path $env:TEMP ("rv64fpga-project-check-" + [Guid]::NewGuid().ToString('N'))
$stagedRoot = Join-Path $workDirectory 'source'
$projectDirectory = Join-Path $workDirectory 'project'
$stagedScript = Join-Path $workDirectory 'validate-rv64-mig-project.tcl'
$vivadoLog = Join-Path $workDirectory 'vivado.log'
$partName = 'xc7k480tffg1156-2'

try {
    New-Item -ItemType Directory -Force -Path $workDirectory | Out-Null
    New-Item -ItemType Directory -Force -Path $stagedRoot | Out-Null
    foreach ($directory in @('rtl', 'constraints', 'ip')) {
        Copy-Item -LiteralPath (Join-Path $SourceRoot $directory) -Destination $stagedRoot -Recurse
    }
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'scripts\validate-rv64-mig-project.tcl') -Destination $stagedScript
    Set-Location -LiteralPath $workDirectory
    & $VivadoBat -mode batch -nojournal -nolog -source $stagedScript -tclargs $stagedRoot $projectDirectory 2>&1 |
        Tee-Object -FilePath $vivadoLog
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado project validation failed with exit code ${LASTEXITCODE}: $vivadoLog"
    }
    if (-not (Select-String -LiteralPath $vivadoLog -SimpleMatch 'RV64_MIG_PROJECT_VALID' -Quiet)) {
        throw "Vivado project validation produced no success sentinel: $vivadoLog"
    }
    if (Select-String -LiteralPath $vivadoLog -SimpleMatch 'synth_design' -Quiet) {
        throw "validation log unexpectedly contains synth_design: $vivadoLog"
    }
    "RV64_MIG_PROJECT_CHECK_PASS`t$partName`t$projectDirectory"
}
finally {
    if (Test-Path -LiteralPath $workDirectory) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
