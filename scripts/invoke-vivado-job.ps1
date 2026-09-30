[CmdletBinding()]
param([Parameter(Mandatory)][string]$Request)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $true
$job = Get-Content -LiteralPath $Request -Raw | ConvertFrom-Json
Set-Location -LiteralPath $job.WorkingDirectory
$arguments = @('-mode', 'batch', '-nojournal', '-log', $job.Log, '-source', $job.Script, '-tclargs') + @($job.Arguments)
& $job.Vivado @arguments
