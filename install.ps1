# Installs claude-export: wires up the Claude Code skill and the `claude-export` command to point at
# this folder. The real logic (Export-ClaudeSession.ps1) stays here and is never copied - only the two
# tiny entry points below get installed, so there is exactly one copy of the real script to maintain.
#
#   .\install.ps1          copy the skill + launchers into place
#   .\install.ps1 -Check   verify they're installed and point at this folder, make no changes
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$skillSrc = Join-Path $root 'skill\export-session\SKILL.md'
$skillDest = "$HOME\.claude\skills\export-session\SKILL.md"
$binSrc = Join-Path $root 'bin'
$binDest = "$HOME\.local\bin"

function Test-Installed {
    $ok = $true
    foreach ($pair in @(
        @{ Src = $skillSrc; Dest = $skillDest },
        @{ Src = Join-Path $binSrc 'claude-export'; Dest = "$binDest\claude-export" },
        @{ Src = Join-Path $binSrc 'claude-export.cmd'; Dest = "$binDest\claude-export.cmd" }
    )) {
        if (-not (Test-Path $pair.Dest)) {
            Write-Warning "missing: $($pair.Dest)"; $ok = $false; continue
        }
        if ((Get-FileHash $pair.Src).Hash -ne (Get-FileHash $pair.Dest).Hash) {
            Write-Warning "out of date: $($pair.Dest) does not match $($pair.Src) - rerun install.ps1"; $ok = $false; continue
        }
        Write-Host "[ok] $($pair.Dest)"
    }
    return $ok
}

if ($Check) {
    if (Test-Installed) { Write-Host "claude-export is installed and up to date."; exit 0 }
    exit 1
}

New-Item -ItemType Directory -Force (Split-Path $skillDest) | Out-Null
Copy-Item $skillSrc $skillDest -Force
Write-Host "[ok] skill -> $skillDest"

New-Item -ItemType Directory -Force $binDest | Out-Null
Copy-Item (Join-Path $binSrc 'claude-export') "$binDest\claude-export" -Force
Copy-Item (Join-Path $binSrc 'claude-export.cmd') "$binDest\claude-export.cmd" -Force
Write-Host "[ok] launcher -> $binDest\claude-export(.cmd)"

if ($env:PATH -split ';' -notcontains $binDest) {
    Write-Warning "$binDest is not on PATH; add it to use the 'claude-export' command directly (the Claude Code skill works regardless)."
}

$hasUvx = [bool](Get-Command uvx -ErrorAction SilentlyContinue)
if (-not $hasUvx) {
    Write-Warning "uvx was not found; the export needs it to run 'claude-code-log' (https://github.com/daaain/claude-code-log). Install uv: https://docs.astral.sh/uv/"
}

Write-Host "`nDone. In a Claude Code session, run the skill with '/export-session', or from any shell: '!claude-export'."
