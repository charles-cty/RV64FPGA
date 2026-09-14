[CmdletBinding()]
param(
    [ValidateSet('alu', 'decoder', 'regfile', 'imm')]
    [string]$Test = 'alu',
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$VivadoBat = 'C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat',
    [switch]$KeepWork
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $true

if (-not (Test-Path -LiteralPath $VivadoBat -PathType Leaf)) {
    throw "Vivado launcher was not found: $VivadoBat"
}

$vivadoBin = Split-Path -Parent $VivadoBat
$xvlog = Join-Path $vivadoBin 'xvlog.bat'
$xelab = Join-Path $vivadoBin 'xelab.bat'
$xsim = Join-Path $vivadoBin 'xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Vivado simulator tool was not found: $tool"
    }
}

$workingDirectory = Join-Path $env:TEMP ("rv64fpga-xsim-" + [Guid]::NewGuid().ToString('N'))
$resultDirectory = Join-Path $SourceRoot (Join-Path 'build\xsim' $Test)
New-Item -ItemType Directory -Force -Path $workingDirectory | Out-Null

try {
    foreach ($directory in @('rtl', 'sim')) {
        Copy-Item -LiteralPath (Join-Path $SourceRoot $directory) -Destination $workingDirectory -Recurse
    }
    Set-Location -LiteralPath $workingDirectory

    $sources = @('rtl\riscv_pkg.sv')
    if ($Test -eq 'alu') {
        $sources += @('rtl\rv64_alu.sv', 'sim\tb_rv64_alu.sv')
        $top = 'tb_rv64_alu'
    } elseif ($Test -eq 'decoder') {
        $sources += @('rtl\rv64_decoder.sv', 'sim\tb_rv64_decoder.sv')
        $top = 'tb_rv64_decoder'
    } elseif ($Test -eq 'regfile') {
        $sources += @('rtl\rv64_regfile.sv', 'sim\tb_rv64_regfile.sv')
        $top = 'tb_rv64_regfile'
    } else {
        $sources += @('rtl\rv64_imm_gen.sv', 'sim\tb_rv64_imm_gen.sv')
        $top = 'tb_rv64_imm_gen'
    }
    & $xvlog --nolog --sv @sources
    $snapshot = "${top}_snap"
    & $xelab --nolog --debug typical --snapshot $snapshot $top
    $logPath = Join-Path $workingDirectory 'sim.log'
    & $xsim --nolog --runall $snapshot 2>&1 | Tee-Object -FilePath $logPath
    if (Select-String -LiteralPath $logPath -SimpleMatch 'SIM FAIL' -Quiet) {
        throw "xsim reported SIM FAIL: $logPath"
    }
    if (-not (Select-String -LiteralPath $logPath -SimpleMatch 'SIM PASS' -Quiet)) {
        throw "xsim completed without a SIM PASS sentinel: $logPath"
    }

    New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
    Copy-Item -LiteralPath $logPath -Destination (Join-Path $resultDirectory 'sim.log') -Force
    "XSIM_PASS`t$Test`t$(Join-Path $resultDirectory 'sim.log')"
}
finally {
    if (-not $KeepWork) {
        Remove-Item -LiteralPath $workingDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
