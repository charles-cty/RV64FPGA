[CmdletBinding()]
param(
    [ValidateSet('alu', 'decoder', 'regfile', 'imm', 'divider', 'core', 'core_divzero', 'core_random', 'core_csr', 'core_atomic', 'core_alignment', 'core_supervisor_irq', 'core_privilege', 'core_fence', 'soc', 'soc_random', 'soc_uart', 'soc_uart_irq', 'soc_irq', 'soc_sbi', 'soc_mmu', 'soc_mmu_fault', 'soc_mmu_fault_diff', 'soc_mmu_sum_diff', 'soc_mmu_user_diff', 'soc_mmu_tlb_diff', 'soc_cache_diff', 'soc_mmu_diff', 'soc_ddr3_model', 'soc_ddr3_external', 'soc_ddr3_mmu', 'soc_pte_write', 'soc_ddr3_high_half', 'soc_ddr3_fault', 'soc_ddr3_diff', 'soc_ddr3_instruction', 'soc_ddr3_atomic', 'soc_init_files', 'soc_boot_image', 'soc_linux_handoff', 'soc_jtag_smoke', 'ddr3_arbiter', 'ddr3_mig_shared_path', 'ddr3_mig_atomic_path', 'csr', 'atomic', 'cache', 'clint', 'plic', 'uart', 'uart_rx', 'mmu', 'mmu_random', 'ddr3_model', 'ddr3_axi_adapter', 'async_memory_bridge', 'ddr3_mig_path', 'ddr3_diag_controller', 'jtag_axi_loader', 'startup_reset')]
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
    if ($Test -eq 'soc_boot_image' -or $Test -eq 'soc_linux_handoff' -or $Test -eq 'soc_jtag_smoke') {
        $bootImage = Join-Path $SourceRoot 'build\boot\boot_rom.hex'
        if (-not (Test-Path -LiteralPath $bootImage -PathType Leaf)) {
            throw "boot image was not found; run scripts/build-boot-image.sh first: $bootImage"
        }
        Copy-Item -LiteralPath $bootImage -Destination (Join-Path $workingDirectory 'boot_rom.hex')
    }
    if ($Test -eq 'soc_linux_handoff') {
        $payloadImage = Join-Path $SourceRoot 'build\boot\linux_ddr3_image.hex'
        if (-not (Test-Path -LiteralPath $payloadImage -PathType Leaf)) {
            throw "Linux handoff DDR3 image was not found; run scripts/build-boot-image.sh first: $payloadImage"
        }
        Copy-Item -LiteralPath $payloadImage -Destination (Join-Path $workingDirectory 'linux_ddr3_image.hex')
    }
    if ($Test -eq 'soc_jtag_smoke') {
        $payloadImage = Join-Path $SourceRoot 'build\boot\jtag_smoke_ddr3_image.hex'
        if (-not (Test-Path -LiteralPath $payloadImage -PathType Leaf)) {
            throw "JTAG smoke DDR3 image was not found; run make jtag-smoke-image first: $payloadImage"
        }
        Copy-Item -LiteralPath $payloadImage -Destination (Join-Path $workingDirectory 'jtag_smoke_ddr3_image.hex')
    }
    if ($Test -eq 'core_random' -or $Test -eq 'soc_random') {
        $randomProgram = Join-Path $SourceRoot (Join-Path 'build\xsim' (Join-Path $Test 'program.hex'))
        if (-not (Test-Path -LiteralPath $randomProgram -PathType Leaf)) {
            throw "random program was not found; run the matching random differential script first: $randomProgram"
        }
        Copy-Item -LiteralPath $randomProgram -Destination (Join-Path $workingDirectory 'sim\random_program.hex')
    }
    Set-Location -LiteralPath $workingDirectory

    $sources = @('rtl\riscv_pkg.sv')
    if ($Test -eq 'alu') {
        $sources += @('rtl\rv64_alu.sv', 'sim\tb_rv64_alu.sv')
        $top = 'tb_rv64_alu'
    } elseif ($Test -eq 'divider') {
        $sources += @('rtl\rv64_divider.sv', 'sim\tb_rv64_divider.sv')
        $top = 'tb_rv64_divider'
    } elseif ($Test -eq 'decoder') {
        $sources += @('rtl\rv64_decoder.sv', 'sim\tb_rv64_decoder.sv')
        $top = 'tb_rv64_decoder'
    } elseif ($Test -eq 'regfile') {
        $sources += @('rtl\rv64_regfile.sv', 'sim\tb_rv64_regfile.sv')
        $top = 'tb_rv64_regfile'
    } elseif ($Test -eq 'imm') {
        $sources += @('rtl\rv64_imm_gen.sv', 'sim\tb_rv64_imm_gen.sv')
        $top = 'tb_rv64_imm_gen'
    } elseif ($Test -eq 'core' -or $Test -eq 'core_divzero' -or $Test -eq 'core_random' -or $Test -eq 'core_csr' -or $Test -eq 'core_atomic' -or $Test -eq 'core_alignment' -or $Test -eq 'core_supervisor_irq' -or $Test -eq 'core_privilege' -or $Test -eq 'core_fence') {
        $sources += @(
            'rtl\rv64_alu.sv', 'rtl\rv64_decoder.sv', 'rtl\rv64_imm_gen.sv',
            'rtl\rv64_regfile.sv', 'rtl\rv64_csr.sv', 'rtl\rv64_atomic_unit.sv', 'rtl\rv64_divider.sv', 'rtl\rv64_core.sv'
        )
        if ($Test -eq 'core') {
            $sources += 'sim\tb_rv64_core.sv'
            $top = 'tb_rv64_core'
        } elseif ($Test -eq 'core_divzero') {
            $sources += 'sim\tb_rv64_core_divzero.sv'
            $top = 'tb_rv64_core_divzero'
        } elseif ($Test -eq 'core_random') {
            $sources += 'sim\tb_rv64_core_random.sv'
            $top = 'tb_rv64_core_random'
        } elseif ($Test -eq 'core_csr') {
            $sources += 'sim\tb_rv64_core_csr.sv'
            $top = 'tb_rv64_core_csr'
        } elseif ($Test -eq 'core_atomic') {
            $sources += 'sim\tb_rv64_core_atomic.sv'
            $top = 'tb_rv64_core_atomic'
        } else {
            if ($Test -eq 'core_alignment') {
                $sources += 'sim\tb_rv64_core_alignment.sv'
                $top = 'tb_rv64_core_alignment'
            } elseif ($Test -eq 'core_supervisor_irq') {
                $sources += 'sim\tb_rv64_core_supervisor_irq.sv'
                $top = 'tb_rv64_core_supervisor_irq'
            } elseif ($Test -eq 'core_privilege') {
                $sources += 'sim\tb_rv64_core_privilege.sv'
                $top = 'tb_rv64_core_privilege'
            } else {
                $sources += 'sim\tb_rv64_core_fence.sv'
                $top = 'tb_rv64_core_fence'
            }
        }
    } elseif ($Test -eq 'soc' -or $Test -eq 'soc_random' -or $Test -eq 'soc_uart' -or $Test -eq 'soc_uart_irq' -or $Test -eq 'soc_irq' -or $Test -eq 'soc_sbi' -or $Test -eq 'soc_mmu' -or $Test -eq 'soc_mmu_fault' -or $Test -eq 'soc_mmu_fault_diff' -or $Test -eq 'soc_mmu_sum_diff' -or $Test -eq 'soc_mmu_user_diff' -or $Test -eq 'soc_mmu_tlb_diff' -or $Test -eq 'soc_cache_diff' -or $Test -eq 'soc_mmu_diff' -or $Test -eq 'soc_ddr3_model' -or $Test -eq 'soc_ddr3_external' -or $Test -eq 'soc_ddr3_mmu' -or $Test -eq 'soc_pte_write' -or $Test -eq 'soc_ddr3_high_half' -or $Test -eq 'soc_ddr3_fault' -or $Test -eq 'soc_ddr3_diff' -or $Test -eq 'soc_ddr3_instruction' -or $Test -eq 'soc_ddr3_atomic' -or $Test -eq 'soc_init_files' -or $Test -eq 'soc_boot_image' -or $Test -eq 'soc_linux_handoff' -or $Test -eq 'soc_jtag_smoke') {
        $sources += @(
            'rtl\rv64_alu.sv', 'rtl\rv64_decoder.sv', 'rtl\rv64_imm_gen.sv',
            'rtl\rv64_regfile.sv', 'rtl\rv64_csr.sv', 'rtl\rv64_atomic_unit.sv', 'rtl\rv64_divider.sv',
            'rtl\rv64_clint.sv', 'rtl\rv64_plic.sv', 'rtl\rv64_mmu.sv', 'rtl\rv64_cache.sv', 'rtl\rv64_ddr3_model.sv', 'rtl\rv64_ddr3_arbiter.sv', 'rtl\rv64_core.sv',
            'rtl\rv64_uart.sv', 'rtl\rv64_bram_soc.sv'
        )
        if ($Test -eq 'soc') {
            $sources += 'sim\tb_rv64_bram_soc.sv'
            $top = 'tb_rv64_bram_soc'
        } elseif ($Test -eq 'soc_random') {
            $sources += 'sim\tb_rv64_bram_soc_random.sv'
            $top = 'tb_rv64_bram_soc_random'
        } elseif ($Test -eq 'soc_uart') {
            $sources += 'sim\tb_rv64_bram_soc_uart.sv'
            $top = 'tb_rv64_bram_soc_uart'
        } elseif ($Test -eq 'soc_uart_irq') {
            $sources += 'sim\tb_rv64_bram_soc_uart_irq.sv'
            $top = 'tb_rv64_bram_soc_uart_irq'
        } elseif ($Test -eq 'soc_irq') {
            $sources += 'sim\tb_rv64_bram_soc_interrupt.sv'
            $top = 'tb_rv64_bram_soc_interrupt'
        } elseif ($Test -eq 'soc_sbi') {
            $sources += 'sim\tb_rv64_bram_soc_sbi.sv'
            $top = 'tb_rv64_bram_soc_sbi'
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
        } elseif ($Test -eq 'soc_mmu_tlb_diff') {
            $sources += 'sim\tb_rv64_bram_soc_mmu_tlb_diff.sv'
            $top = 'tb_rv64_bram_soc_mmu_tlb_diff'
        } elseif ($Test -eq 'soc_ddr3_model') {
            $sources += 'sim\tb_rv64_bram_soc_ddr3_model.sv'
            $top = 'tb_rv64_bram_soc_ddr3_model'
        } elseif ($Test -eq 'soc_ddr3_external') {
            $sources += 'sim\tb_rv64_bram_soc_ddr3_external.sv'
            $top = 'tb_rv64_bram_soc_ddr3_external'
        } elseif ($Test -eq 'soc_pte_write') {
            $sources += 'sim\tb_rv64_bram_soc_pte_write.sv'
            $top = 'tb_rv64_bram_soc_pte_write'
        } elseif ($Test -eq 'soc_ddr3_mmu') {
            $sources += 'sim\tb_rv64_bram_soc_ddr3_mmu.sv'
            $top = 'tb_rv64_bram_soc_ddr3_mmu'
        } elseif ($Test -eq 'soc_ddr3_high_half') {
            $sources += 'sim\tb_rv64_bram_soc_ddr3_high_half.sv'
            $top = 'tb_rv64_bram_soc_ddr3_high_half'
        } elseif ($Test -eq 'soc_ddr3_fault') {
            $sources += 'sim\tb_rv64_bram_soc_ddr3_fault.sv'
            $top = 'tb_rv64_bram_soc_ddr3_fault'
        } elseif ($Test -eq 'soc_ddr3_diff') {
            $sources += 'sim\tb_rv64_bram_soc_ddr3_diff.sv'
            $top = 'tb_rv64_bram_soc_ddr3_diff'
    } elseif ($Test -eq 'soc_ddr3_instruction') {
            $sources += 'sim\tb_rv64_bram_soc_ddr3_instruction.sv'
            $top = 'tb_rv64_bram_soc_ddr3_instruction'
        } elseif ($Test -eq 'soc_ddr3_atomic') {
            $sources += 'sim\tb_rv64_bram_soc_ddr3_atomic.sv'
            $top = 'tb_rv64_bram_soc_ddr3_atomic'
        } elseif ($Test -eq 'soc_init_files') {
            $sources += 'sim\tb_rv64_bram_soc_init_files.sv'
            $top = 'tb_rv64_bram_soc_init_files'
        } elseif ($Test -eq 'soc_boot_image') {
            $sources += 'sim\tb_rv64_bram_soc_boot_image.sv'
            $top = 'tb_rv64_bram_soc_boot_image'
        } elseif ($Test -eq 'soc_linux_handoff') {
            $sources += 'sim\tb_rv64_bram_soc_linux_handoff.sv'
            $top = 'tb_rv64_bram_soc_linux_handoff'
        } elseif ($Test -eq 'soc_jtag_smoke') {
            $sources += 'sim\tb_rv64_bram_soc_jtag_smoke.sv'
            $top = 'tb_rv64_bram_soc_jtag_smoke'
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
    } elseif ($Test -eq 'mmu_random') {
        $sources += @('rtl\rv64_mmu.sv', 'sim\tb_rv64_mmu_random.sv')
        $top = 'tb_rv64_mmu_random'
    } elseif ($Test -eq 'ddr3_model') {
        $sources += @('rtl\rv64_ddr3_model.sv', 'sim\tb_rv64_ddr3_model.sv')
        $top = 'tb_rv64_ddr3_model'
    } elseif ($Test -eq 'ddr3_axi_adapter') {
        $sources += @('rtl\rv64_ddr3_axi_adapter.sv', 'sim\tb_rv64_ddr3_axi_adapter.sv')
        $top = 'tb_rv64_ddr3_axi_adapter'
    } elseif ($Test -eq 'async_memory_bridge') {
        $sources += @('rtl\rv64_async_memory_bridge.sv', 'sim\tb_rv64_async_memory_bridge.sv')
        $top = 'tb_rv64_async_memory_bridge'
    } elseif ($Test -eq 'uart_rx') {
        $sources += @('rtl\rv64_uart.sv', 'sim\tb_rv64_uart_rx.sv')
        $top = 'tb_rv64_uart_rx'
    } elseif ($Test -eq 'ddr3_arbiter') {
        $sources += @('rtl\rv64_ddr3_model.sv', 'rtl\rv64_ddr3_arbiter.sv', 'sim\tb_rv64_ddr3_arbiter.sv')
        $top = 'tb_rv64_ddr3_arbiter'
    } elseif ($Test -eq 'ddr3_mig_shared_path') {
        $sources += @('rtl\rv64_async_memory_bridge.sv', 'rtl\rv64_ddr3_axi_adapter.sv', 'rtl\rv64_ddr3_arbiter.sv', 'rtl\rv64_ddr3_mig_shared_path.sv', 'sim\tb_rv64_ddr3_mig_shared_path.sv')
        $top = 'tb_rv64_ddr3_mig_shared_path'
    } elseif ($Test -eq 'ddr3_mig_atomic_path') {
        $sources += @('rtl\rv64_async_memory_bridge.sv', 'rtl\rv64_ddr3_axi_adapter.sv', 'rtl\rv64_ddr3_mig_path.sv', 'rtl\rv64_ddr3_mig_atomic_path.sv', 'sim\tb_rv64_ddr3_mig_atomic_path.sv')
        $top = 'tb_rv64_ddr3_mig_atomic_path'
    } elseif ($Test -eq 'ddr3_mig_path') {
        $sources += @('rtl\rv64_async_memory_bridge.sv', 'rtl\rv64_ddr3_axi_adapter.sv', 'rtl\rv64_ddr3_mig_path.sv', 'sim\tb_rv64_ddr3_mig_path.sv')
        $top = 'tb_rv64_ddr3_mig_path'
    } elseif ($Test -eq 'ddr3_diag_controller') {
        $sources += @('rtl\rv64_ddr3_diag_controller.sv', 'sim\tb_rv64_ddr3_diag_controller.sv')
        $top = 'tb_rv64_ddr3_diag_controller'
    } elseif ($Test -eq 'jtag_axi_loader') {
        $sources += @('rtl\rv64_jtag_axi_loader.sv', 'sim\tb_rv64_jtag_axi_loader.sv')
        $top = 'tb_rv64_jtag_axi_loader'
    } elseif ($Test -eq 'startup_reset') {
        $sources += @('rtl\rv64_startup_reset.sv', 'sim\tb_rv64_startup_reset.sv')
        $top = 'tb_rv64_startup_reset'
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
    if ($Test -eq 'core' -or $Test -eq 'core_random' -or $Test -eq 'soc_random' -or $Test -eq 'soc_cache_diff' -or $Test -eq 'soc_mmu_diff' -or $Test -eq 'soc_mmu_fault_diff' -or $Test -eq 'soc_mmu_sum_diff' -or $Test -eq 'soc_mmu_user_diff' -or $Test -eq 'soc_mmu_tlb_diff' -or $Test -eq 'soc_ddr3_diff') {
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
