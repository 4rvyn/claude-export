# Installs claude-export: wires up the Claude Code skill and the `claude-export` command to point at
# this folder. The real logic (Export-ClaudeSession.ps1) stays here and is never copied - only the two
# tiny entry points below get installed, with {{SCRIPT_PATH}} substituted for this folder's actual
# absolute path, so the same clone works regardless of where it lives on disk.
#
#   powershell -ExecutionPolicy Bypass -File install.ps1          copy the skill + launchers into place
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Check   verify only, change nothing
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$scriptPath = Join-Path $root 'Export-ClaudeSession.ps1'
$binDest = "$HOME\.local\bin"

# The baked-in path can contain non-ASCII characters (a user folder with an umlaut). Claude Code and Git Bash read
# UTF-8 (no BOM - it would break the frontmatter and the #! line). cmd.exe decodes a .cmd file in whatever
# console code page is active - OEM in a plain terminal, UTF-8 in Claude Code's shells - so no encoding is
# right everywhere: the .cmd gets the ASCII-only 8.3 short path instead.
$cmdPath = $scriptPath
if ($cmdPath -notmatch '^[\x00-\x7F]*$') {
    $cmdPath = (New-Object -ComObject Scripting.FileSystemObject).GetFile($scriptPath).ShortPath
    if ($cmdPath -notmatch '^[\x00-\x7F]*$') {
        Write-Warning "This folder's path has non-ASCII characters and the drive has no 8.3 short names, so the 'claude-export' command will not work from cmd or PowerShell. Clone to a plain-ASCII path, or use /claude-export or Git Bash."
    }
}
$utf8 = New-Object Text.UTF8Encoding $false
$files = @(
    @{ Src = Join-Path $root 'skill\claude-export\SKILL.md'; Dest = "$HOME\.claude\skills\claude-export\SKILL.md"; Enc = $utf8; Path = $scriptPath },
    @{ Src = Join-Path $root 'bin\claude-export'; Dest = "$binDest\claude-export"; Enc = $utf8; Path = $scriptPath },
    @{ Src = Join-Path $root 'bin\claude-export.cmd'; Dest = "$binDest\claude-export.cmd"; Enc = [Text.Encoding]::ASCII; Path = $cmdPath }
)

function Expand-Template($f) {
    [IO.File]::ReadAllText($f.Src).Replace('{{SCRIPT_PATH}}', $f.Path)
}

if ($Check) {
    $ok = $true
    foreach ($f in $files) {
        if (-not (Test-Path $f.Dest)) { Write-Warning "missing: $($f.Dest)"; $ok = $false; continue }
        if ([IO.File]::ReadAllText($f.Dest, $f.Enc) -ne (Expand-Template $f)) {
            Write-Warning "out of date: $($f.Dest) does not match this folder - rerun install.ps1"; $ok = $false; continue
        }
        Write-Host "[ok] $($f.Dest)"
    }
    if ($ok) { Write-Host "claude-export is installed and up to date."; exit 0 }
    exit 1
}

foreach ($f in $files) {
    New-Item -ItemType Directory -Force (Split-Path $f.Dest) | Out-Null
    [IO.File]::WriteAllText($f.Dest, (Expand-Template $f), $f.Enc)
    Write-Host "[ok] $($f.Dest)"
}

if (($env:PATH -split ';' | ForEach-Object { $_.TrimEnd('\') }) -notcontains $binDest) {
    Write-Warning "$binDest is not on PATH; add it to use the 'claude-export' command directly (the Claude Code skill works regardless)."
}

if (-not (Get-Command uvx -ErrorAction SilentlyContinue)) {
    Write-Warning "uvx was not found; the export needs it to run 'claude-code-log' (https://github.com/daaain/claude-code-log). Install uv: https://docs.astral.sh/uv/"
}

Write-Host "`nDone. In a Claude Code session, run the skill with '/claude-export', or from any shell: '!claude-export'."
