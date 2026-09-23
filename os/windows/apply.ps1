#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Apply the Windows config this repo owns: power timeouts, power mode, every
    registry policy under registry/, and every app in apps.txt.

.DESCRIPTION
    Safe to run again: every step sets a value rather than toggling one, so a
    second run changes nothing. See README.md next to this file for why each
    value is what it is.

    Run from an elevated PowerShell:
        powershell -ExecutionPolicy Bypass -File os\windows\apply.ps1

    Kept to ASCII on purpose: Windows PowerShell 5.1 reads a BOM-less file as
    the ANSI code page, and a stray dash in a comment is enough to break parsing.
#>

$ErrorActionPreference = 'Stop'

# Minutes; 0 means never. AC is plugged in, DC is on battery.
# Plugged in, the machine is a workstation that must not drop a session.
# On battery the Windows defaults stay, so a forgotten laptop still sleeps.
$Timeouts = [ordered]@{
    'monitor-timeout-ac'   = 0
    'standby-timeout-ac'   = 0
    'hibernate-timeout-ac' = 0
    'monitor-timeout-dc'   = 3
    'standby-timeout-dc'   = 10
    'hibernate-timeout-dc' = 180
}

# Settings > System > Power & battery > Power mode, stored as an overlay GUID.
# Best Performance kept the T480 fan running for nothing.
$Overlays = @{
    'Balanced'              = '00000000-0000-0000-0000-000000000000'
    'Best Performance'      = 'ded574b5-45a0-4f42-8737-46345c09c238'
    'Best Power Efficiency' = '961cc777-2547-4f9d-8174-7d86181b8a7a'
}
$PowerMode = 'Balanced'

function Invoke-Native {
    # Native tools do not throw on failure, so ErrorActionPreference alone
    # would let a failed powercfg or reg import report success.
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$Exe $($Arguments -join ' ') exited $LASTEXITCODE" }
}

Write-Host '== power plan'
# Power mode overlays only apply on top of the Balanced plan.
Invoke-Native powercfg '/setactive', 'SCHEME_BALANCED'
Write-Host '   Balanced'

Write-Host '== power timeouts'
foreach ($name in $Timeouts.Keys) {
    Invoke-Native powercfg '/change', $name, "$($Timeouts[$name])"
    Write-Host ("   {0,-22} {1}" -f $name, $Timeouts[$name])
}

Write-Host '== power mode'
if ((Get-CimInstance Win32_OperatingSystem).ProductType -ne 1) {
    # CI runs on Windows Server, which has no power mode to set.
    Write-Host '   skipped, not a client edition of Windows'
} else {
    # Through the power service, not the registry: the PowerSchemes key is
    # writable by SYSTEM only, and Set-ItemProperty is denied even elevated.
    # ponytail: sets the mode for the power source in use, so run this plugged
    # in; switch to the battery and check Settings once if that side matters.
    Invoke-Native powercfg '/overlaysetactive', $Overlays[$PowerMode]
    Write-Host "   $PowerMode"
}

Write-Host '== registry'
$regs = Get-ChildItem -Path (Join-Path $PSScriptRoot 'registry') -Filter '*.reg' | Sort-Object Name
foreach ($reg in $regs) {
    Invoke-Native reg 'import', $reg.FullName
    Write-Host "   $($reg.Name)"
}

Write-Host '== apps'
# Last, because it is the slow, network-bound step: power and policy are in
# place even if a download fails. One failed app does not stop the rest.
$failed = @()
$apps = Get-Content (Join-Path $PSScriptRoot 'apps.txt') |
    ForEach-Object { ($_ -replace '#.*', '').Trim() } | Where-Object { $_ }
foreach ($id in $apps) {
    winget list --id $id -e --accept-source-agreements | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "   $id  (installed)"; continue }
    Write-Host "   $id"
    # Captured rather than shown: winget draws spinners and progress bars that
    # only make sense on a live console. Printed after all when it fails.
    $out = winget install --id $id -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        $out | Where-Object { $_ -match '[a-z]{3}' } | ForEach-Object { "      $_" }
        $failed += "$id ($LASTEXITCODE)"
    }
}

Write-Host ''
if ($failed) { throw "winget could not install: $($failed -join ', ')" }
Write-Host 'Done. Restart once so the Windows Update policy takes effect.'
