# Native Windows terminal; requires PowerShell 7.4+ and Vivado, no WSL/Python.
[CmdletBinding()]
param(
    [string]$Probes = 'build\jtag-console-hardware-20261002\bitstream\rv64_mig_soc_top.ltx',
    [string]$Session = ('build\terminal-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')),
    [string]$Vivado = 'C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat',
    [switch]$Smoke,
    [int]$TimeoutSeconds = 120
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Run this script in native Windows PowerShell 7.4+.' }
if ($PSVersionTable.PSVersion -lt [version]'7.4') { throw 'PowerShell 7.4+ is required.' }
if (-not $Smoke -and ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)) {
    throw 'Interactive mode requires a Windows terminal. Use -Smoke for a noninteractive check.'
}
$probesPath = (Resolve-Path -LiteralPath $Probes).Path
$sessionPath = [IO.Path]::GetFullPath($Session)
if (Test-Path -LiteralPath $sessionPath) { throw "Use a new session directory: $sessionPath" }
if (-not (Test-Path -LiteralPath $Vivado -PathType Leaf)) { throw "Vivado not found: $Vivado" }
[IO.Directory]::CreateDirectory($sessionPath) | Out-Null
$inputPath = Join-Path $sessionPath 'input.bin'
$outputPath = Join-Path $sessionPath 'output.bin'
$heartbeat = Join-Path $sessionPath 'heartbeat'
$stop = Join-Path $sessionPath 'stop'
$ready = Join-Path $sessionPath 'ready'
$utf8 = [Text.UTF8Encoding]::new($false)
$decoder = $utf8.GetDecoder()
$inputStream = $null
$outputStream = $null
$backend = $null
$backendStarted = $false
$oldControlC = $null
function Pulse-Heartbeat {
    [IO.File]::WriteAllText($heartbeat, [Diagnostics.Stopwatch]::GetTimestamp().ToString(), $utf8)
}
function Convert-TerminalKey([ConsoleKeyInfo]$Key) {
    if ($Key.KeyChar -eq [char]29) { return [char]29 }
    switch ($Key.Key) {
        'Enter' { return "`r" }
        'Backspace' { return [char]127 }
        'UpArrow' { return "`e[A" }
        'DownArrow' { return "`e[B" }
        'RightArrow' { return "`e[C" }
        'LeftArrow' { return "`e[D" }
        'Home' { return "`e[H" }
        'End' { return "`e[F" }
        'Delete' { return "`e[3~" }
    }
    if ($Key.KeyChar -ne [char]0) { return $Key.KeyChar.ToString() }
    return ''
}
try {
    $inputStream = [IO.File]::Open($inputPath, 'CreateNew', 'Write', 'ReadWrite')
    $outputStream = [IO.File]::Open($outputPath, 'CreateNew', 'ReadWrite', 'ReadWrite')
    Pulse-Heartbeat
    $request = @{
        WorkingDirectory = $sessionPath
        Vivado = $Vivado
        Script = Join-Path $PSScriptRoot 'jtag-console.tcl'
        Log = Join-Path $sessionPath 'vivado.log'
        Arguments = @($probesPath, $sessionPath)
    }
    $requestPath = Join-Path $sessionPath 'request.json'
    [IO.File]::WriteAllText($requestPath, ($request | ConvertTo-Json), $utf8)
    # Separate process owns Vivado. Redirect stdin so it cannot consume keys.
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $PSHOME 'pwsh.exe'
    $start.WorkingDirectory = $sessionPath
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'invoke-vivado-job.ps1'), '-Request', $requestPath)) {
        $start.ArgumentList.Add($argument)
    }
    $backend = [Diagnostics.Process]::new()
    $backend.StartInfo = $start
    if (-not $backend.Start()) { throw 'Could not start Vivado wrapper.' }
    $backendStarted = $true
    $backend.StandardInput.Close()
    # Drain both pipes immediately; otherwise a verbose Vivado can deadlock.
    $stdoutTask = $backend.StandardOutput.ReadToEndAsync()
    $stderrTask = $backend.StandardError.ReadToEndAsync()
    Write-Host 'Connecting to JTAG console. Ctrl-] exits; Ctrl-C goes to Linux.'
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $ready)) {
        Pulse-Heartbeat
        if ($backend.HasExited) { throw "Backend exited before attachment; see $sessionPath" }
        if ($timer.Elapsed.TotalSeconds -gt 120) { throw 'JTAG attach timeout.' }
        Start-Sleep -Milliseconds 100
    }
    $marker = 'JTAG_CONSOLE_' + [Guid]::NewGuid().ToString('N')
    if ($Smoke) {
        $bytes = $utf8.GetBytes("echo $marker`r")
        $inputStream.Write($bytes, 0, $bytes.Length)
        $inputStream.Flush()
    } else {
        $oldControlC = [Console]::TreatControlCAsInput
        [Console]::TreatControlCAsInput = $true
        Write-Host 'Connected. Press Enter for the shell prompt.'
    }
    $timer.Restart()
    $received = ''
    $buffer = [byte[]]::new(65536)
    $characters = [char[]]::new(65536)
    $lastDropped = 0L
    $quit = $false
    while (-not $quit) {
        Pulse-Heartbeat
        if ($backend.HasExited) { throw "Console backend stopped; see $sessionPath" }
        $count = $outputStream.Read($buffer, 0, $buffer.Length)
        if ($count -gt 0) {
            $length = $decoder.GetChars($buffer, 0, $count, $characters, 0, $false)
            $text = [string]::new($characters, 0, $length)
            [Console]::Write($text)
            if ($Smoke) {
                $received += $text
                if ($received.Length -gt 65536) { $received = $received.Substring($received.Length - 65536) }
                if ([regex]::IsMatch($received, '(?m)^' + [regex]::Escape($marker) + "`r?`n")) { break }
            }
        }
        $droppedPath = Join-Path $sessionPath 'dropped.txt'
        if (Test-Path -LiteralPath $droppedPath) {
            $dropped = 0L
            if ([long]::TryParse([IO.File]::ReadAllText($droppedPath).Trim(), [ref]$dropped) -and $dropped -ne $lastDropped) {
                [Console]::WriteLine("`r`n[JTAG: $dropped output bytes dropped since CPU reset]")
                $lastDropped = $dropped
            }
        }
        if ($Smoke) {
            if ($timer.Elapsed.TotalSeconds -gt $TimeoutSeconds) { throw 'Linux did not return the exact nonce line.' }
        } else {
            while ([Console]::KeyAvailable) {
                $text = Convert-TerminalKey ([Console]::ReadKey($true))
                if ($text -eq [string][char]29) { $quit = $true; break }
                $bytes = $utf8.GetBytes($text)
                $inputStream.Write($bytes, 0, $bytes.Length)
            }
            $inputStream.Flush()
        }
        Start-Sleep -Milliseconds 25
    }
} finally {
    if ($null -ne $oldControlC) { [Console]::TreatControlCAsInput = $oldControlC }
    [IO.File]::WriteAllText($stop, '', $utf8)
    if ($backendStarted) {
        if ($backend.WaitForExit(10000)) {
            [IO.File]::WriteAllText((Join-Path $sessionPath 'console.log'), ($stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()), $utf8)
        } else {
            Write-Warning "Backend still exiting; inspect $sessionPath\vivado.log"
        }
        $backend.Dispose()
    }
    if ($null -ne $inputStream) { $inputStream.Dispose() }
    if ($null -ne $outputStream) { $outputStream.Dispose() }
}
if ($Smoke) { Write-Host "`nJTAG_CONSOLE_SMOKE_PASS" }
else { Write-Host "`nDisconnected; Linux remains running." }
