<#
.SYNOPSIS
    Build the Forgejo MCP server from the local mirror and register it with
    Claude Code: the Windows half of `make forgejo-mcp` and `make claude`.

.DESCRIPTION
    Run as yourself, not elevated. Git, Go and the Claude CLI are installed
    through winget first if any is missing:
        powershell -ExecutionPolicy Bypass -File os\windows\forgejo-mcp.ps1

    Safe to run again: it rebuilds the newest tag, keeps the token when the
    prompt is left empty, and registers the server afresh. See
    .docs-llm/mcp-servers.md for the token scopes and why the mirror.

    Kept to ASCII on purpose, like apply.ps1.
#>

$ErrorActionPreference = 'Stop'

$Mirror = 'https://git.insuit.cz/tools-mirror/forgejo-mcp'
$Forge  = 'https://git.insuit.cz'

function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$Exe $($Arguments -join ' ') exited $LASTEXITCODE" }
}

function Update-Path {
    # A winget install reaches the PATH of new shells only, so read it afresh.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

Write-Host '== tools'
# The same winget ids as apps.txt, installed here too so this script does not
# depend on apply.ps1 having run first.
$Tools = [ordered]@{ 'git' = 'Git.Git'; 'go' = 'GoLang.Go'; 'claude' = 'Anthropic.ClaudeCode' }
Update-Path
foreach ($tool in $Tools.Keys) {
    if (Get-Command $tool -ErrorAction SilentlyContinue) { Write-Host "   $tool"; continue }
    Write-Host "   $tool  (installing $($Tools[$tool]))"
    Invoke-Native winget 'install', '--id', $Tools[$tool], '-e', '--silent', '--disable-interactivity', '--accept-source-agreements', '--accept-package-agreements'
    Update-Path
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool installed but not on PATH; open a new shell and run again" }
}

Write-Host '== build'
# Newest tag with no dash, the same rule as the Makefile: -v:refname sorts a
# pre-release above the last stable tag. A checkout and `go install .`, not
# `go install <mirror>@latest`, because go.mod declares the upstream path.
$tag = git ls-remote --tags --refs --sort=-v:refname $Mirror |
    ForEach-Object { ($_ -split '/')[-1] } | Where-Object { $_ -notmatch '-' } |
    Select-Object -First 1
if (-not $tag) { throw "no release tag found at $Mirror" }
Write-Host "   $tag"
$tmp = Join-Path ([IO.Path]::GetTempPath()) "forgejo-mcp-$tag"
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
try {
    Invoke-Native git 'clone', '-q', '--depth', '1', '--branch', $tag, '-c', 'advice.detachedHead=false', $Mirror, $tmp
    Push-Location $tmp
    try { Invoke-Native go 'install', '.' } finally { Pop-Location }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
$bin = Join-Path (go env GOPATH) 'bin\forgejo-mcp.exe'
Write-Host "   $bin"
# Smart App Control blocks any unsigned binary it has no reputation for,
# which a local build always is. Stop here rather than register a server
# that can never start.
try { & $bin --version | Out-Null } catch { $LASTEXITCODE = 1 }
if ($LASTEXITCODE -ne 0) {
    throw "$bin does not run. If Smart App Control is on, it blocks local builds: run apply.ps1 elevated, restart, then run this again. See the Smart App Control section in os/windows/CAVEATS.md"
}

Write-Host '== token'
# A user environment variable, the Windows twin of the shell drop-in that
# `make claude` writes: Claude Code hands its environment to the server.
# Machine-local, because this repo is public.
$was = [Environment]::GetEnvironmentVariable('FORGEJO_ACCESS_TOKEN', 'User')
$state = if ($was) { 'set' } else { 'unset' }
$secure = Read-Host "Forgejo token for git.insuit.cz [$state, empty keeps it]" -AsSecureString
$token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
if ($token) {
    [Environment]::SetEnvironmentVariable('FORGEJO_ACCESS_TOKEN', $token, 'User')
    Write-Host '   set'
} elseif ($was) {
    Write-Host '   kept'
} else {
    Write-Host '   left unset, so the server is not registered'
    exit 0
}

Write-Host '== claude'
# Registered here rather than through the shared .mcp.json, because every
# entry there runs through `sh -c` and sh is not on the Windows PATH.
# Removed first so a second run replaces the entry instead of failing on it.
& { $ErrorActionPreference = 'Continue'; claude mcp remove forgejo --scope user *> $null }
Invoke-Native claude 'mcp', 'add', '--scope', 'user', 'forgejo', '--', $bin, '--transport', 'stdio', '--url', $Forge
Write-Host '   forgejo'

Write-Host ''
Write-Host 'Done. Restart Claude so it sees the token, then: claude mcp list'
