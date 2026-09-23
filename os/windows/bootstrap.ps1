<#
.SYNOPSIS
    One command for a fresh Windows install: Git, this repo, then apply.ps1.

.DESCRIPTION
    From an elevated PowerShell:
        irm https://raw.githubusercontent.com/landsman/config/main/os/windows/bootstrap.ps1 | iex

    Another branch, to test a pull request before it is merged:
        $env:CONFIG_BRANCH = 'my-branch'
        irm https://raw.githubusercontent.com/landsman/config/my-branch/os/windows/bootstrap.ps1 | iex

    Clones into ~\projects\landsman\config, the same path as on every other
    machine. Already cloned, it pulls instead. Kept to ASCII, see apply.ps1.
#>

$ErrorActionPreference = 'Stop'

# #Requires does not apply to a script piped into iex, so check by hand.
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this from an elevated PowerShell (Run as administrator).'
}

$branch = if ($env:CONFIG_BRANCH) { $env:CONFIG_BRANCH } else { 'main' }
$repo = Join-Path $HOME 'projects\landsman\config'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host '== git'
    winget install --id Git.Git -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "winget install Git.Git exited $LASTEXITCODE" }
    # winget does not refresh PATH in the running shell.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

if (Test-Path (Join-Path $repo '.git')) {
    Write-Host "== pull $repo"
    git -C $repo pull --ff-only
} else {
    Write-Host "== clone into $repo ($branch)"
    # The repo tracks symlinks (CLAUDE.md -> AGENTS.md); without this Git for
    # Windows checks them out as text files holding the target path.
    git clone -c core.symlinks=true --branch $branch https://github.com/landsman/config $repo
}
if ($LASTEXITCODE -ne 0) { throw "git exited $LASTEXITCODE" }

powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'os\windows\apply.ps1')
if ($LASTEXITCODE -ne 0) { throw "apply.ps1 exited $LASTEXITCODE" }
