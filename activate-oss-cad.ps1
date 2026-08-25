# Session-only activator for OSS CAD Suite (Windows).
# Does not modify the user or system PATH permanently.
# Usage from D:\FPGA:  .\activate-oss-cad.ps1
# Or:  . D:\FPGA\oss-cad-suite\environment.ps1

$suite = 'D:\FPGA\oss-cad-suite'
$envScript = Join-Path $suite 'environment.ps1'

if (-not (Test-Path -LiteralPath $envScript)) {
    throw "OSS CAD Suite environment script not found: $envScript"
}

. $envScript

Write-Host ''
Write-Host 'OSS CAD Suite environment active (this PowerShell session only).'
Write-Host "YOSYSHQ_ROOT=$env:YOSYSHQ_ROOT"
Write-Host ''

function Show-ToolVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Args
    )
    Write-Host "----- $Name -----"
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Name @Args 2>&1 | ForEach-Object { "$_" } | Select-Object -First 8 | ForEach-Object { Write-Host $_ }
    } catch {
        Write-Host "FAILED: $_"
    } finally {
        $ErrorActionPreference = $prev
    }
    Write-Host ''
}

Show-ToolVersion -Name 'yosys' -Args @('-V')
Show-ToolVersion -Name 'nextpnr-himbaechel' -Args @('-V')
Show-ToolVersion -Name 'openFPGALoader' -Args @('--Version')
