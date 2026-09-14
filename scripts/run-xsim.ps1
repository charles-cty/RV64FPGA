[CmdletBinding()]
param(
    [ValidateSet('alu', 'decoder', 'regfile', 'imm', 'core', 'core_csr', 'core_atomic', 'core_alignment', 'soc', 'soc_uart', 'soc_irq', 'soc_mmu', 'soc_mmu_fault', 'soc_mmu_fault_diff', 'soc_mmu_sum_diff', 'soc_mmu_user_diff', 'soc_cache_diff', 'soc_mmu_diff', 'soc_ddr3_model', 'soc_ddr3_fault', 'soc_ddr3_diff', 'soc_ddr3_instruction', 'ddr3_arbiter', 'csr', 'atomic', 'cache', 'clint', 'plic', 'uart', 'mmu', 'ddr3_model', 'ddr3_axi_adapter', 'async_memory_bridge', 'ddr3_mig_path')]
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
    } elseif ($Test -eq 'imm') {
        $sources += @('rtl\rv64_imm_gen.sv', 'sim\tb_rv64_imm_gen.sv')
        $top = 'tb_rv64_imm_gen'
    } elseif ($Test -eq 'core' -or $Test -eq 'core_csr' -or $Test -eq 'core_atomic' -or $Test -eq 'core_alignment') {
        $sources += @(
            'rtl\rv64_alu.sv', 'rtl\rv64_decoder.sv', 'rtl\rv64_imm_gen.sv',
            'rtl\rv64_regfile.sv', 'rtl\rv64_csr.sv', 'rtl\rv64_atomic_unit.sv', 'rtl\rv64_core.sv'
        )
        if ($Test -eq 'core') {
            $sources += 'sim\tb_rv64_core.sv'
            $top = 'tb_rv64_core'
        } elseif ($Test -eq 'core_csr') {
            $sources += 'sim\tb_rv64_core_csr.sv'
            $top = 'tb_rv64_core_csr'
        } elseif ($Test -eq 'core_atomic') {
            $sources += 'sim\tb_rv64_core_atomic.sv'
            $top = 'tb_rv64_core_atomic'
        } else {
            $sources += 'sim\tb_rv64_core_alignment.sv'
            $top = 'tb_rv64_core_alignment'
        }
    } elseif ($Test -eq 'soc' -or $Test -eq 'soc_uart' -or $Test -eq 'soc_irq' -or $Test -eq 'soc_mmu' -or $Test -eq 'soc_mmu_fault' -or $Test -eq 'soc_mmu_fault_diff' -or $Test -eq 'soc_mmu_sum_diff' -or $Test -eq 'soc_mmu_user_diff' -or $Test -eq 'soc_cache_diff' -or $Test -eq 'soc_mmu_diff' -or $Test -eq 'soc_ddr3_model' -or $Test -eq 'soc_ddr3_fault' -or $Test -eq 'soc_ddr3_diff' -or $Test -eq 'soc_ddr3_instruction') {
        $sources += @(
            'rtl\rv64_alu.sv', 'rtl\rv64_decoder.sv', 'rtl\rv64_imm_gen.sv',
            'rtl\rv64_regfile.sv', 'rtl\rv64_csr.sv', 'rtl\rv64_atomic_unit.sv',
            'rtl\rv64_clint.sv', 'rtl\rv64_plic.sv', 'rtl\rv64_mmu.sv', 'rtl\rv64_cache.sv', 'rtl\rv64_ddr3_model.sv', 'rtl\rv64_core.sv',
            'rtl\rv64_uart.sv', 'rtl\rv64_bram_soc.sv'
        )
        if ($Test -eq 'soc') {
            $sources += 'sim\tb_rv64_bram_soc.sv'
            $top = 'tb_rv64_bram_soc'
        } elseif ($Test -eq 'soc_uart') {
            $sources += 'sim\tb_rv64_bram_soc_uart.sv'
            $top = 'tb_rv64_bram_soc_uart'
        } elseif ($Test -eq 'soc_irq') {
            $sources += 'sim\tb_rv64_bram_soc_interrupt.sv'
            $top = 'tb_rv64_bram_soc_interrupt'
        } elseif ($Test -eq 'soc_mmu') {
            $sources += 'sim\tb_rv64_bram_soc_mmu.sv'
            $top = 'tb_rv64_bram_soc_mmu'
        } elseif ($Test -eq 'soc_mmu_fault') {
            $sources += 'sim\tb_rv64_bram_soc_mmu_fault.sv'
            $top = 'tb_rv64_bram_soc_mmu_fault'
        } elseif ($Test -eq 'soc_mmu_fault_diff') {
            $sources += 'sim\tb_rv64_bram_soc_mmu_fault_diff.sv'
            $top = 'tb_rv64_bram_soc_mmu_fault_diff'
        } elseif ($Test -eq 'soc_mmu_sum_diff') {
            $sources += 'sim\tb_rv64_bram_soc_mmu_sum_diff.sv'
            $top = 'tb_rv64_bram_soc_mmu_sum_diff'
        } elseif ($Test -eq 'soc_mmu_user_diff') {
            $sources += 'sim\tb_rv64_bram_soc_mmu_user_diff.sv'
            $top = 'tb_rv64_bram_soc_mmu_user_diff'
        } elseif ($Test -eq 'soc_ddr3_model') {
            $sources += 'sim\tb_rv64_bram_soc_ddr3_model.sv'
            $top = 'tb_rv64_bram_soc_ddr3_model'
        } elseif ($Test -eq 'soc_ddr3_fault') {
            $sources += 'sim\tb_rv64_bram_soc_ddr3_fault.sv'
            $top = 'tb_rv64_bram_soc_ddr3_fault'
        } elseif ($Test -eq 'soc_ddr3_diff') {
            $sources += 'sim\tb_rv64_bram_soc_ddr3_diff.sv'
            $top = 'tb_rv64_bram_soc_ddr3_diff'
        } elseif ($Test -eq 'soc_ddr3_instruction') {
            $sources += 'sim\tb_rv64_bram_soc_ddr3_instruction.sv'
            $top = 'tb_rv64_bram_soc_ddr3_instruction'
        } elseif ($Test -eq 'soc_cache_diff') {
            $sources += 'sim\tb_rv64_bram_soc_cache_diff.sv'
            $top = 'tb_rv64_bram_soc_cache_diff'
        } else {
            $sources += 'sim\tb_rv64_bram_soc_mmu_diff.sv'
            $top = 'tb_rv64_bram_soc_mmu_diff'
        }
    } elseif ($Test -eq 'csr') {
        $sources += @('rtl\rv64_csr.sv', 'sim\tb_rv64_csr.sv')
        $top = 'tb_rv64_csr'
    } elseif ($Test -eq 'cache') {
        $sources += @('rtl\rv64_cache.sv', 'sim\tb_rv64_cache.sv')
        $top = 'tb_rv64_cache'
    } elseif ($Test -eq 'atomic') {
        $sources += @('rtl\rv64_atomic_unit.sv', 'sim\tb_rv64_atomic_unit.sv')
        $top = 'tb_rv64_atomic_unit'
    } elseif ($Test -eq 'clint') {
        $sources += @('rtl\rv64_clint.sv', 'sim\tb_rv64_clint.sv')
        $top = 'tb_rv64_clint'
    } elseif ($Test -eq 'plic') {
        $sources += @('rtl\rv64_plic.sv', 'sim\tb_rv64_plic.sv')
        $top = 'tb_rv64_plic'
    } elseif ($Test -eq 'mmu') {
        $sources += @('rtl\rv64_mmu.sv', 'sim\tb_rv64_mmu.sv')
        $top = 'tb_rv64_mmu'
    } elseif ($Test -eq 'ddr3_model') {
        $sources += @('rtl\rv64_ddr3_model.sv', 'sim\tb_rv64_ddr3_model.sv')
        $top = 'tb_rv64_ddr3_model'
    } elseif ($Test -eq 'ddr3_axi_adapter') {
        $sources += @('rtl\rv64_ddr3_axi_adapter.sv', 'sim\tb_rv64_ddr3_axi_adapter.sv')
        $top = 'tb_rv64_ddr3_axi_adapter'
    } elseif ($Test -eq 'async_memory_bridge') {
        $sources += @('rtl\rv64_async_memory_bridge.sv', 'sim\tb_rv64_async_memory_bridge.sv')
        $top = 'tb_rv64_async_memory_bridge'
    } elseif ($Test -eq 'ddr3_arbiter') {
        $sources += @('rtl\rv64_ddr3_model.sv', 'rtl\rv64_ddr3_arbiter.sv', 'sim\tb_rv64_ddr3_arbiter.sv')
        $top = 'tb_rv64_ddr3_arbiter'
    } elseif ($Test -eq 'ddr3_mig_path') {
        $sources += @('rtl\rv64_async_memory_bridge.sv', 'rtl\rv64_ddr3_axi_adapter.sv', 'rtl\rv64_ddr3_mig_path.sv', 'sim\tb_rv64_ddr3_mig_path.sv')
        $top = 'tb_rv64_ddr3_mig_path'
    } else {
        $sources += @('rtl\rv64_uart.sv', 'sim\tb_rv64_uart.sv')
        $top = 'tb_rv64_uart'
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
    if ($Test -eq 'core' -or $Test -eq 'soc_cache_diff' -or $Test -eq 'soc_mmu_diff' -or $Test -eq 'soc_mmu_fault_diff' -or $Test -eq 'soc_mmu_sum_diff' -or $Test -eq 'soc_mmu_user_diff' -or $Test -eq 'soc_ddr3_diff') {
        $tracePath = Join-Path $workingDirectory 'rtl_trace.jsonl'
        if (-not (Test-Path -LiteralPath $tracePath -PathType Leaf)) {
            throw "core simulation did not produce a trace: $tracePath"
        }
        Copy-Item -LiteralPath $tracePath -Destination (Join-Path $resultDirectory 'rtl_trace.jsonl') -Force
    }
    "XSIM_PASS`t$Test`t$(Join-Path $resultDirectory 'sim.log')"
}
finally {
    if (-not $KeepWork) {
        Remove-Item -LiteralPath $workingDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
