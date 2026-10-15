# Smoke tests for Export-ClaudeSession.ps1 and install.ps1.
#
# Every check launches the script under test in a brand-new powershell.exe process
# (Invoke-Pwsh below). That is deliberate, not just style:
#   - $ErrorActionPreference set in THIS file can never leak into the script under test.
#     (Previously this file set $ErrorActionPreference = 'Stop' at the top. Because `& $script`
#     runs in a child *scope* of the same process, the child inherited that 'Stop'. That turned
#     every Write-Error inside Export-ClaudeSession.ps1 - which the script relies on being a
#     non-terminating, "print and then explicitly `return`" error - into a terminating exception,
#     which is NOT captured by `2>&1` the way the tests assumed. That produced false [FAIL]s and
#     inconsistent results depending on which check ran first.)
#   - Environment variable overrides (e.g. clearing CLAUDE_CODE_SESSION_ID for one check) are
#     applied only to that one child process and are restored immediately after, so they can
#     never bleed into this test runner or any other check.
#
# SAFETY: any check that performs a real export always passes -Out at a fresh folder under
# $env:TEMP, deleted again in a finally block. Nothing here ever writes to the real default
# export folder (~/Desktop/Claude-Exports) - that is checked explicitly at the end.
#
#   .\tests\run-tests.ps1

$root = Split-Path $PSScriptRoot -Parent
$script = Join-Path $root 'Export-ClaudeSession.ps1'
$installScript = Join-Path $root 'install.ps1'
$failed = 0
$defaultExportDir = Join-Path $HOME 'Desktop\Claude-Exports'

# PowerShell silently drops an empty-string argument when calling a native exe (powershell.exe
# here counts as native). The fix is the well-known '""' trick: a literal two-double-quote token
# is what the child process's argument parser turns back into an empty string.
function ConvertTo-NativeArg([string]$s) {
    if ($s -eq '') { '""' } else { $s }
}

# Runs $ScriptPath in a brand-new powershell.exe process and returns its combined
# stdout+stderr text and exit code. -EnvOverrides (hashtable) is applied to this process's
# environment only for the duration of the call (a $null value clears the variable for the
# child), then restored in a finally block no matter what happens.
function Invoke-Pwsh {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [hashtable]$EnvOverrides = @{}
    )
    $saved = @{}
    foreach ($k in $EnvOverrides.Keys) {
        $saved[$k] = [Environment]::GetEnvironmentVariable($k)
        [Environment]::SetEnvironmentVariable($k, $EnvOverrides[$k])
    }
    try {
        $nativeArgs = @($Arguments | ForEach-Object { ConvertTo-NativeArg $_ })
        $text = (& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath @nativeArgs 2>&1 |
            ForEach-Object { "$_" }) -join "`n"
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = $text }
    } finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
}

function Get-AllSessionFiles {
    Get-ChildItem "$HOME\.claude\projects" -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ChildItem $_.FullName -Filter *.jsonl -File -ErrorAction SilentlyContinue }
}

function Check($name, [scriptblock]$body) {
    try {
        $result = & $body
        if ($result) { Write-Host "[PASS] $name" } else { Write-Host "[FAIL] $name"; $script:failed++ }
    } catch {
        Write-Host "[FAIL] $name - $_"; $script:failed++
    }
}

# ---- list / lookup behavior ----

Check "-List runs and prints a table" {
    $r = Invoke-Pwsh $script @('-List')
    $r.Text -match 'Session\s+Last used'
}

Check "zero matches is a clear error, not a crash" {
    $r = Invoke-Pwsh $script @('zzz-no-such-session-prefix-zzz')
    ($r.Text -match 'Found 0 sessions starting with') -and ($r.ExitCode -eq 0)
}

Check "an ambiguous prefix (matches 2+ sessions) is a clear error, not a silent pick" {
    $allIds = @(Get-AllSessionFiles | ForEach-Object { $_.BaseName })
    $prefix = $null; $expected = 0
    foreach ($len in 1..3) {
        $g = $allIds | Group-Object { $_.Substring(0, [Math]::Min($len, $_.Length)) } |
            Where-Object Count -gt 1 | Sort-Object Count -Descending | Select-Object -First 1
        if ($g) { $prefix = $g.Name; $expected = $g.Count; break }
    }
    if (-not $prefix) { throw "no two sessions under ~/.claude/projects share a short prefix - cannot exercise this path right now" }
    $r = Invoke-Pwsh $script @($prefix)
    ($r.Text -match "Found $expected sessions starting with") -and ($r.ExitCode -eq 0)
}

Check "empty-string session argument with no ambient session falls back to -List (safe), not an export" {
    # Redesigned after a real incident (see below). With CLAUDE_CODE_SESSION_ID unset, an empty
    # $Session trips the script's own "$List -or -not $Session" check and just prints -List -
    # it never reaches the match/export logic at all. -Out still points at a scratch temp dir
    # as a second line of defense, and we assert nothing was ever created there.
    $tempOut = Join-Path $env:TEMP ("claude-export-test-{0}" -f ([guid]::NewGuid()))
    try {
        $r = Invoke-Pwsh $script @('', '-Out', $tempOut) -EnvOverrides @{ CLAUDE_CODE_SESSION_ID = $null }
        $showedList = $r.Text -match 'Session\s+Last used'
        $nothingExported = -not (Test-Path $tempOut)
        $showedList -and $nothingExported
    } finally {
        if (Test-Path $tempOut) { Remove-Item -Recurse -Force $tempOut -ErrorAction SilentlyContinue }
    }
}

Check "empty-string session argument WITH an ambient CLAUDE_CODE_SESSION_ID reproduces the real incident safely (contained to a scratch -Out)" {
    # This is the actual bug that happened: Export-ClaudeSession.ps1 resolves
    # "-not $Session -and -not $List" to fall back to $env:CLAUDE_CODE_SESSION_ID BEFORE
    # checking whether $Session was explicitly passed as ''. So when that env var is set (the
    # normal case inside a Claude Code session), an empty-string -Session argument is NOT
    # list/ambiguous mode - it silently resolves to "export that one ambient session for real".
    # The old test exercised this with the REAL ambient session and the REAL default -Out,
    # which is exactly how it leaked into ~/Desktop/Claude-Exports. Here the "ambient session"
    # is a fake one we control (a known small session id), overridden only for this one child
    # process and restored immediately after, and -Out is a scratch temp dir we always delete -
    # so the hazardous path is exercised and asserted on, but it can never touch anything real.
    $small = Get-AllSessionFiles | Where-Object { $_.Length -gt 0 } | Sort-Object Length | Select-Object -First 1
    if (-not $small) { throw "no session file found under ~/.claude/projects to use as the fake ambient session" }
    $tempOut = Join-Path $env:TEMP ("claude-export-test-{0}" -f ([guid]::NewGuid()))
    try {
        $r = Invoke-Pwsh $script @('', '-Out', $tempOut) -EnvOverrides @{ CLAUDE_CODE_SESSION_ID = $small.BaseName }
        $destDir = Get-ChildItem $tempOut -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $destDir) { throw "expected the fake ambient session to be exported into the scratch -Out. Output:`n$($r.Text)" }
        $destDir.Name -match [regex]::Escape($small.BaseName.Substring(0, 8))
    } finally {
        if (Test-Path $tempOut) { Remove-Item -Recurse -Force $tempOut -ErrorAction SilentlyContinue }
    }
}

# ---- -Out safety guard ----

function Get-OneRealSessionId {
    $r = Invoke-Pwsh $script @('-List')
    $idLine = ($r.Text -split "`n") | Select-String '^\S{8}\s' | Select-Object -First 1
    if (-not $idLine) { throw "no session available to test against" }
    ($idLine -split '\s+')[0]
}

Check "-Out inside ~/.claude is refused before anything runs" {
    $id = Get-OneRealSessionId
    $badOut = Join-Path $HOME '.claude\should-not-be-written'
    $r = Invoke-Pwsh $script @($id, '-Out', $badOut)
    ($r.Text -match '-Out must not be inside') -and (-not (Test-Path $badOut))
}

Check "-Out inside `$env:LOCALAPPDATA\Temp\claude is refused before anything runs" {
    $id = Get-OneRealSessionId
    $badOut = Join-Path $env:LOCALAPPDATA 'Temp\claude\should-not-be-written'
    $r = Invoke-Pwsh $script @($id, '-Out', $badOut)
    ($r.Text -match '-Out must not be inside') -and (-not (Test-Path $badOut))
}

# ---- real end-to-end export (scratch temp dir only) ----

Check "end-to-end export of a small real session creates non-empty transcript.html and transcript.md" {
    $small = Get-AllSessionFiles | Where-Object { $_.Length -gt 0 } | Sort-Object Length | Select-Object -First 1
    if (-not $small) { throw "no session file found under ~/.claude/projects to export" }
    $tempOut = Join-Path $env:TEMP ("claude-export-test-{0}" -f ([guid]::NewGuid()))
    try {
        $r = Invoke-Pwsh $script @($small.BaseName.Substring(0, 8), '-Out', $tempOut)
        $destDir = Get-ChildItem $tempOut -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $destDir) { throw "no destination folder created under $tempOut. Output:`n$($r.Text)" }
        $html = Join-Path $destDir.FullName 'transcript.html'
        $md = Join-Path $destDir.FullName 'transcript.md'
        (Test-Path $html) -and ((Get-Item $html).Length -gt 0) -and (Test-Path $md) -and ((Get-Item $md).Length -gt 0)
    } finally {
        if (Test-Path $tempOut) { Remove-Item -Recurse -Force $tempOut -ErrorAction SilentlyContinue }
    }
}

# ---- folder-name collision ----

Check "a pre-existing folder from a DIFFERENT session with the same date+prefix is not overwritten" {
    $small = Get-AllSessionFiles | Where-Object { $_.Length -gt 0 } | Sort-Object Length | Select-Object -First 1
    if (-not $small) { throw "no session file found under ~/.claude/projects to export" }
    $id8 = $small.BaseName.Substring(0, 8)
    $day = $small.LastWriteTime.ToString('yyyy-MM-dd')
    $tempOut = Join-Path $env:TEMP ("claude-export-test-{0}" -f ([guid]::NewGuid()))
    try {
        $collidingDest = Join-Path $tempOut "${day}_$id8"
        New-Item -ItemType Directory -Force $collidingDest | Out-Null
        Set-Content (Join-Path $collidingDest '.session-id') 'not-the-real-session-00000000-0000-0000-0000-000000000000' -NoNewline
        "content from an unrelated session - must survive" | Set-Content (Join-Path $collidingDest 'transcript.html')

        $r = Invoke-Pwsh $script @($small.BaseName.Substring(0, 8), '-Out', $tempOut)
        $otherSessionIntact = (Get-Content (Join-Path $collidingDest 'transcript.html')) -match 'must survive'
        $widenedDest = Get-ChildItem $tempOut -Directory | Where-Object { $_.FullName -ne $collidingDest } | Select-Object -First 1
        if (-not $widenedDest) { throw "expected a second, widened folder for the real session. Output:`n$($r.Text)" }
        $realExported = Test-Path (Join-Path $widenedDest.FullName 'transcript.html')
        $otherSessionIntact -and $realExported
    } finally {
        if (Test-Path $tempOut) { Remove-Item -Recurse -Force $tempOut -ErrorAction SilentlyContinue }
    }
}

Check "re-exporting the same session reuses its own folder instead of widening again" {
    $small = Get-AllSessionFiles | Where-Object { $_.Length -gt 0 } | Sort-Object Length | Select-Object -First 1
    if (-not $small) { throw "no session file found under ~/.claude/projects to export" }
    $tempOut = Join-Path $env:TEMP ("claude-export-test-{0}" -f ([guid]::NewGuid()))
    try {
        Invoke-Pwsh $script @($small.BaseName.Substring(0, 8), '-Out', $tempOut) | Out-Null
        Invoke-Pwsh $script @($small.BaseName.Substring(0, 8), '-Out', $tempOut) | Out-Null
        (Get-ChildItem $tempOut -Directory).Count -eq 1
    } finally {
        if (Test-Path $tempOut) { Remove-Item -Recurse -Force $tempOut -ErrorAction SilentlyContinue }
    }
}

# ---- install.ps1 ----

Check "install.ps1 -Check passes after install.ps1 has run" {
    $r = Invoke-Pwsh $installScript @('-Check')
    $r.Text -match 'up to date'
}

# ---- final safety net ----

if (Test-Path $defaultExportDir) {
    Write-Host "[FAIL] safety: $defaultExportDir exists - a test leaked a real export into the real default folder. Not auto-deleting; investigate before touching it."
    $failed++
}

if ($failed -gt 0) { Write-Host "`n$failed check(s) failed."; exit 1 }
Write-Host "`nAll checks passed."
