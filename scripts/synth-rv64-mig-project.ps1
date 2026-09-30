[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\vivado-synth'),
    [string]$BoardConfig = 'C:\My\Projects\FPGA\LC480T\vivado 板卡文件\ypcb_00338_1p1_hack-main\ypcb003381p1\1.0\mig_0.prj',
    [string]$VivadoBat = 'C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat',
    [string]$BootRomImage = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\boot\boot_rom.hex'),
    [ValidateSet('rv64_mig_soc_top', 'rv64_mig_ddr3_diag_top')]
    [string]$Top = 'rv64_mig_soc_top'
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
if (-not [System.IO.Path]::IsPathFullyQualified($BootRomImage)) {
    $BootRomImage = Join-Path $SourceRoot $BootRomImage
}
$BootRomImage = [System.IO.Path]::GetFullPath($BootRomImage)

$expectedBoardConfigHash = 'baed6883dac282367f835cd71dd312d307bd0efbc786cf6f4a2a5a0909c4e23c'

if (-not (Test-Path -LiteralPath $VivadoBat -PathType Leaf)) {
    throw "Vivado launcher was not found: $VivadoBat"
}
if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "source root was not found: $SourceRoot"
}
if (-not (Test-Path -LiteralPath $BoardConfig -PathType Leaf)) {
    throw "MIG board configuration was not found: $BoardConfig"
}
if ($Top -eq 'rv64_mig_soc_top' -and -not (Test-Path -LiteralPath $BootRomImage -PathType Leaf)) {
    throw "boot ROM image was not found; run scripts/build-boot-image.sh first: $BootRomImage"
}
$actualBoardConfigHash = (Get-FileHash -LiteralPath $BoardConfig -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualBoardConfigHash -ne $expectedBoardConfigHash) {
    throw "Unexpected MIG board configuration SHA-256: $actualBoardConfigHash"
}

$workDirectory = Join-Path $env:TEMP ("rv64fpga-synth-" + [Guid]::NewGuid().ToString('N'))
$stagedRoot = Join-Path $workDirectory 'source'
$projectDirectory = Join-Path $workDirectory 'project'
$reportDirectory = Join-Path $workDirectory 'reports'
$stagedScript = Join-Path $workDirectory 'synth-rv64-mig-project.tcl'
$stagedBootRomImage = Join-Path $stagedRoot 'boot\boot_rom.hex'
$vivadoLog = Join-Path $workDirectory 'vivado-synth.log'

$originalLocation = Get-Location
try {
    New-Item -ItemType Directory -Force -Path $workDirectory | Out-Null
    New-Item -ItemType Directory -Force -Path $stagedRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
    foreach ($directory in @('rtl', 'constraints', 'ip')) {
        Copy-Item -LiteralPath (Join-Path $SourceRoot $directory) -Destination $stagedRoot -Recurse
    }
    if ($Top -eq 'rv64_mig_soc_top') {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stagedBootRomImage) | Out-Null
        Copy-Item -LiteralPath $BootRomImage -Destination $stagedBootRomImage
    }
    Copy-Item -LiteralPath $BoardConfig -Destination (Join-Path $stagedRoot 'ip\mig_0.prj')
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'scripts\synth-rv64-mig-project.tcl') -Destination $stagedScript
    Set-Location -LiteralPath $workDirectory
    & $VivadoBat -mode batch -nojournal -nolog -source $stagedScript -tclargs $stagedRoot $projectDirectory $reportDirectory $stagedBootRomImage $Top 2>&1 |
        Tee-Object -FilePath $vivadoLog
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado synthesis failed with exit code ${LASTEXITCODE}: $vivadoLog"
    }
    if (-not (Select-String -LiteralPath $vivadoLog -SimpleMatch 'RV64_MIG_SYNTH_PASS' -Quiet)) {
        throw "Vivado synthesis produced no success sentinel: $vivadoLog"
    }
    Copy-Item -LiteralPath $reportDirectory -Destination $OutputRoot -Recurse -Force
    Copy-Item -LiteralPath $vivadoLog -Destination (Join-Path $OutputRoot 'vivado-synth.log') -Force
    "RV64_MIG_SYNTH_CHECK_PASS`t$OutputRoot"
}
finally {
    Set-Location -LiteralPath $originalLocation.Path
    if (Test-Path -LiteralPath $workDirectory) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
