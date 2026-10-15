# Installs claude-export: wires up the Claude Code skill and the `claude-export` command to point at
# this folder. The real logic (Export-ClaudeSession.ps1) stays here and is never copied - only the two
# tiny entry points below get installed, with {{SCRIPT_PATH}} substituted for this folder's actual
# absolute path, so the same clone works regardless of where it lives on disk.
#
#   .\install.ps1          copy the skill + launchers into place
#   .\install.ps1 -Check   verify they're installed and point at this folder, make no changes
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$scriptPath = Join-Path $root 'Export-ClaudeSession.ps1'

$skillSrc = Join-Path $root 'skill\claude-export\SKILL.md'
$skillDest = "$HOME\.claude\skills\claude-export\SKILL.md"
$oldSkillDir = "$HOME\.claude\skills\export-session"  # pre-rename location; removed if still present
$binSrc = Join-Path $root 'bin'
$binDest = "$HOME\.local\bin"

function Expand-Template($path) {
    (Get-Content $path -Raw).Replace('{{SCRIPT_PATH}}', $scriptPath)
}

function Test-Installed {
    $ok = $true
    if (Test-Path $oldSkillDir) {
        Write-Warning "stale: $oldSkillDir (pre-rename skill folder) still exists - rerun install.ps1 to remove it"
        $ok = $false
    }
    foreach ($pair in @(
        @{ Expected = Expand-Template $skillSrc; Dest = $skillDest },
        @{ Expected = Expand-Template (Join-Path $binSrc 'claude-export'); Dest = "$binDest\claude-export" },
        @{ Expected = Expand-Template (Join-Path $binSrc 'claude-export.cmd'); Dest = "$binDest\claude-export.cmd" }
    )) {
        if (-not (Test-Path $pair.Dest)) {
            Write-Warning "missing: $($pair.Dest)"; $ok = $false; continue
        }
        if ((Get-Content $pair.Dest -Raw) -ne $pair.Expected) {
            Write-Warning "out of date: $($pair.Dest) does not match this folder - rerun install.ps1"; $ok = $false; continue
        }
        Write-Host "[ok] $($pair.Dest)"
    }
    return $ok
}

if ($Check) {
    if (Test-Installed) { Write-Host "claude-export is installed and up to date."; exit 0 }
    exit 1
}

if (Test-Path $oldSkillDir) {
    Remove-Item $oldSkillDir -Recurse -Force
    Write-Host "[ok] removed stale $oldSkillDir (renamed to claude-export)"
}

New-Item -ItemType Directory -Force (Split-Path $skillDest) | Out-Null
Expand-Template $skillSrc | Set-Content $skillDest -NoNewline
Write-Host "[ok] skill -> $skillDest"

New-Item -ItemType Directory -Force $binDest | Out-Null
Expand-Template (Join-Path $binSrc 'claude-export') | Set-Content "$binDest\claude-export" -NoNewline
Expand-Template (Join-Path $binSrc 'claude-export.cmd') | Set-Content "$binDest\claude-export.cmd" -NoNewline
Write-Host "[ok] launcher -> $binDest\claude-export(.cmd)"

if ($env:PATH -split ';' -notcontains $binDest) {
    Write-Warning "$binDest is not on PATH; add it to use the 'claude-export' command directly (the Claude Code skill works regardless)."
}

$hasUvx = [bool](Get-Command uvx -ErrorAction SilentlyContinue)
if (-not $hasUvx) {
    Write-Warning "uvx was not found; the export needs it to run 'claude-code-log' (https://github.com/daaain/claude-code-log). Install uv: https://docs.astral.sh/uv/"
}

Write-Host "`nDone. In a Claude Code session, run the skill with '/claude-export', or from any shell: '!claude-export'."
