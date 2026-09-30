[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BoardConfig,
    [Parameter(Mandatory)]
    [string]$OutputDirectory,
    [string]$VivadoBat = 'C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat',
    [switch]$Generate
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $true
$OFS = ' '

$expectedBoardConfigHash = 'baed6883dac282367f835cd71dd312d307bd0efbc786cf6f4a2a5a0909c4e23c'
$requiredSettings = @(
    'DDR3Count="1" NoOfControllers="1"',
    '<TargetFPGA>xc7k480t-ffg1156/-2</TargetFPGA>',
    '<MemoryDevice>DDR3_SDRAM/Components/MT41K256M8XX-125</MemoryDevice>',
    '<InputClkFreq>200</InputClkFreq>',
    '<DataWidth>72</DataWidth>',
    '<C0_MEM_SIZE>2147483648</C0_MEM_SIZE>',
    '<C0_S_AXI_DATA_WIDTH>512</C0_S_AXI_DATA_WIDTH>',
    'PADName="AH27/AH28(CC_P/N)"'
)

if (-not (Test-Path -LiteralPath $BoardConfig -PathType Leaf)) {
    throw "MIG configuration file was not found: $BoardConfig"
}

$actualBoardConfigHash = (Get-FileHash -LiteralPath $BoardConfig -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualBoardConfigHash -ne $expectedBoardConfigHash) {
    throw "Unexpected MIG configuration SHA-256: $actualBoardConfigHash"
}

$boardConfigContents = Get-Content -LiteralPath $BoardConfig -Raw
foreach ($requiredSetting in $requiredSettings) {
    if (-not $boardConfigContents.Contains($requiredSetting, [StringComparison]::Ordinal)) {
        throw "MIG configuration is missing required setting: $requiredSetting"
    }
}

"MIG_RECIPE_VALID`t$BoardConfig`t$actualBoardConfigHash"

if (-not $Generate) {
    return
}

if (Test-Path -LiteralPath $OutputDirectory) {
    throw "Refusing to overwrite existing output directory: $OutputDirectory"
}
if (-not (Test-Path -LiteralPath $VivadoBat -PathType Leaf)) {
    throw "Vivado launcher was not found: $VivadoBat"
}

$workDirectory = Join-Path $env:TEMP ("rv64fpga-mig-" + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $workDirectory | Out-Null
    $stagedConfig = Join-Path $workDirectory 'mig_0.prj'
    $stagedRecipe = Join-Path $workDirectory 'create-mig-ip.tcl'
    $stagedOutput = Join-Path $workDirectory 'generated-ip'

    Copy-Item -LiteralPath $BoardConfig -Destination $stagedConfig
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'create-mig-ip.tcl') -Destination $stagedRecipe
    Set-Location -LiteralPath $workDirectory

    $vivadoArguments = @(
        '-mode', 'batch',
        '-nojournal',
        '-nolog',
        '-source', $stagedRecipe,
        '-tclargs', 'rv64_mig_ch0', $stagedConfig, $stagedOutput
    )
    & $VivadoBat @vivadoArguments

    $generatedXci = @(Get-ChildItem -LiteralPath $stagedOutput -Filter 'rv64_mig_ch0.xci' -File -Recurse)
    if ($generatedXci.Count -ne 1) {
        throw "Vivado completed without generating exactly one expected XCI under: $stagedOutput"
    }

    $relativeXci = [IO.Path]::GetRelativePath($stagedOutput, $generatedXci[0].FullName)
    Copy-Item -LiteralPath $stagedOutput -Destination $OutputDirectory -Recurse
    "MIG_IP_GENERATED`t$(Join-Path $OutputDirectory $relativeXci)"
}
finally {
    if (Test-Path -LiteralPath $workDirectory) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
