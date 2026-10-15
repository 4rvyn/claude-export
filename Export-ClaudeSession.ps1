# Export one Claude Code session into a single readable folder.
#   transcript.html   self-contained page, images embedded (open in a browser)
#   transcript.md     same conversation as Markdown, pasted images in images\
#   uploads\          images uploaded/dropped into the session (~\.claude\uploads)
#   scratch\          files Claude wrote during the session (Temp scratchpad)
# Uses claude-code-log (https://github.com/daaain/claude-code-log) via uvx.
#
#   .\Export-ClaudeSession.ps1                  inside a Claude session (! prefix): export that session
#   .\Export-ClaudeSession.ps1 -List            show recent sessions
#   .\Export-ClaudeSession.ps1 472b8bb8         export by (start of) session ID
param(
    [string]$Session,
    [string]$Out = "$HOME\Desktop\Claude-Exports",
    [switch]$List
)

# Claude Code sets this in shells it starts, including "!" commands typed in a session.
if (-not $Session -and -not $List) { $Session = $env:CLAUDE_CODE_SESSION_ID }

$projects = "$HOME\.claude\projects"
$all = Get-ChildItem $projects -Directory | ForEach-Object { Get-ChildItem $_.FullName -Filter *.jsonl -File }

if ($List -or -not $Session) {
    $all | Where-Object Length -gt 20KB | Sort-Object LastWriteTime -Descending | Select-Object -First 20 |
        Format-Table @{n='Session';e={$_.BaseName.Substring(0,8)}}, @{n='Last used';e={$_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')}},
                     @{n='MB';e={[math]::Round($_.Length/1MB,1)}}, @{n='Project folder';e={$_.Directory.Name}} -AutoSize
    return
}

$match = @($all | Where-Object { $_.BaseName -like "$Session*" })
if ($match.Count -ne 1) { Write-Error "Found $($match.Count) sessions starting with '$Session'. Use -List and give more characters."; return }
$jsonl = $match[0]
$id = $jsonl.BaseName

# Writing inside a folder this script copies from makes it copy its own output forever.
$outFull = [IO.Path]::GetFullPath($Out).TrimEnd('\') + '\'
foreach ($src in "$env:LOCALAPPDATA\Temp\claude\", "$HOME\.claude\") {
    if ($outFull.StartsWith($src, [StringComparison]::OrdinalIgnoreCase)) { Write-Error "-Out must not be inside $src"; return }
}

# An 8-char id prefix is what -List shows and normally unique enough for one folder name, but two
# unrelated sessions exported on the same day can share one (birthday-paradox odds, not astronomical
# over years of heavy use) - widen it rather than silently merging a second session's files into the
# first one's folder. A marker file records which full id a folder belongs to, so re-exporting the
# same session still reuses its own folder instead of making a new one each time.
$day = $jsonl.LastWriteTime.ToString('yyyy-MM-dd')
for ($len = 8; $true; $len += 4) {
    $short = $id.Substring(0, [Math]::Min($len, $id.Length))
    $dest = Join-Path $Out "${day}_$short"
    $marker = Join-Path $dest '.session-id'
    if (-not (Test-Path $dest)) { break }
    if ((Test-Path $marker) -and (Get-Content $marker -Raw).Trim() -eq $id) { break }
    if ($len -ge $id.Length) { break }  # out of characters to disambiguate with; reuse/overwrite as before
}
New-Item -ItemType Directory -Force $dest | Out-Null
Set-Content $marker $id -NoNewline
(Get-Item $marker).Attributes = 'Hidden'  # keep it out of the summary listing at the end
Write-Host "Exporting $id to $dest"

# Run from home: uvx refuses to start when the current folder is inside its own cache.
Push-Location $HOME
foreach ($fmt in 'html', 'md') {
    $log = & uvx claude-code-log convert $jsonl.FullName --format $fmt --image-export-mode $(if ($fmt -eq 'md') { 'referenced' } else { 'embedded' }) -o "$dest\transcript.$fmt" 2>&1
    if (-not (Test-Path "$dest\transcript.$fmt")) {
        Write-Warning "transcript.$fmt was not created:"
        $log | ForEach-Object { "$_" } | Where-Object { $_ -notmatch 'Loading agent|unrecognized message type' } | Select-Object -Last 10 | Write-Host
    }
}
Pop-Location

# A resumed session gets a new ID, but its uploads and scratch files stay under the old one,
# which the transcript still mentions. Collect files for every ID it mentions.
$ids = @($id) + @(Select-String $jsonl.FullName -Pattern '"session_?[iI]d":"([0-9a-f-]{36})"' -AllMatches |
    ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value }) | Select-Object -Unique

# robocopy, not Copy-Item: /XJ skips folder links (Copy-Item in PowerShell 5.1 follows them,
# which can loop) and it copies paths longer than 260 characters.
function Copy-Folder($from, $to) {
    robocopy $from $to /E /XJ /R:0 /W:0 /NFL /NDL /NJH /NJS /NP | Out-Null
}

foreach ($sid in $ids) {
    $uploads = "$HOME\.claude\uploads\$sid"
    if (Test-Path $uploads) { Copy-Folder $uploads "$dest\uploads" }
    $scratch = Get-ChildItem "$env:LOCALAPPDATA\Temp\claude\*\$sid\scratchpad" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($scratch -and (Get-ChildItem $scratch.FullName -Force | Select-Object -First 1)) {
        $target = if ($ids.Count -gt 1) { "$dest\scratch\$($sid.Substring(0,8))" } else { "$dest\scratch" }
        Copy-Folder $scratch.FullName $target
    }
}

Get-ChildItem $dest | Format-Table Name, @{n='MB';e={ if ($_.PSIsContainer) { [math]::Round((Get-ChildItem $_.FullName -Recurse -File | Measure-Object Length -Sum).Sum/1MB,1) } else { [math]::Round($_.Length/1MB,1) } }} -AutoSize
