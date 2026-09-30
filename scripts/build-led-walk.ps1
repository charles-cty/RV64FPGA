[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\vivado-led-walk'),
    [string]$VivadoBat = 'C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $true

if (-not (Test-Path -LiteralPath $VivadoBat -PathType Leaf)) {
    throw "Vivado launcher was not found: $VivadoBat"
}

$workDirectory = Join-Path $env:TEMP ("rv64fpga-led-walk-" + [Guid]::NewGuid().ToString('N'))
$stagedRoot = Join-Path $workDirectory 'source'
$stagedScript = Join-Path $workDirectory 'build-led-walk.tcl'
$vivadoLog = Join-Path $workDirectory 'vivado-led-walk.log'

try {
    New-Item -ItemType Directory -Force -Path $stagedRoot, $OutputRoot | Out-Null
    foreach ($directory in @('rtl', 'constraints')) {
        Copy-Item -LiteralPath (Join-Path $SourceRoot $directory) -Destination $stagedRoot -Recurse
    }
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'scripts\build-led-walk.tcl') -Destination $stagedScript
    Set-Location -LiteralPath $workDirectory
    & $VivadoBat -mode batch -nojournal -nolog -source $stagedScript -tclargs $stagedRoot $OutputRoot 2>&1 |
        Tee-Object -FilePath $vivadoLog
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado LED walk build failed with exit code ${LASTEXITCODE}: $vivadoLog"
    }
    if (-not (Select-String -LiteralPath $vivadoLog -SimpleMatch 'LED_WALK_BUILD_PASS' -Quiet)) {
        throw "Vivado LED walk build produced no success sentinel: $vivadoLog"
    }
    Copy-Item -LiteralPath $vivadoLog -Destination (Join-Path $OutputRoot 'vivado-led-walk.log') -Force
    "LED_WALK_BUILD_CHECK_PASS`t$OutputRoot"
}
finally {
    if (Test-Path -LiteralPath $workDirectory) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
