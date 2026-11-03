<#
.SYNOPSIS
    Register the Forgejo MCP server with Claude Code: the Windows half of the
    forgejo entry that `make claude` registers elsewhere.

.DESCRIPTION
    Run as yourself, not elevated, with Tailscale signed in:
        powershell -ExecutionPolicy Bypass -File os\windows\forgejo-mcp.ps1

    The server runs on the Pi; this only points Claude at it, with this
    device's OAuth client. The tailnet name comes from Tailscale rather than
    from this repo, which is public. Safe to run again: the entry is replaced.
    See .docs-llm/mcp-servers.md.

    Kept to ASCII on purpose, like apply.ps1.
#>

$ErrorActionPreference = 'Stop'

# The client Authelia has for this device: forgejo-mcp-<device> in the
# homelab's authelia/configuration.yml. The T480 is the one Windows machine.
$Device = 't480'

$suffix = (tailscale status --json | ConvertFrom-Json).MagicDNSSuffix.TrimEnd('.')
if (-not $suffix) { throw 'Tailscale is not running or not signed in' }

$server = @{
    type  = 'http'
    url   = "https://forgejo-mcp.$suffix/mcp"
    oauth = @{ clientId = "forgejo-mcp-$Device"; callbackPort = 53682 }
} | ConvertTo-Json -Compress

# Removed first so a second run replaces the entry instead of failing on it.
& { $ErrorActionPreference = 'Continue'; claude mcp remove forgejo --scope user *> $null }
claude mcp add-json --scope user forgejo $server
if ($LASTEXITCODE -ne 0) { throw "claude mcp add-json exited $LASTEXITCODE" }

Write-Host 'Done. Restart Claude, then sign in to forgejo in /mcp.'
