# claude-export

[![License: MIT](https://img.shields.io/github/license/4rvyn/claude-export)](LICENSE)

Export a Claude Code session into one readable folder (transcript, uploads, scratch files) without
spending a token to do it.

```
> !claude-export
Exporting 472b8bb8-9c3a-4e21-8f0d-1a2b3c4d5e6f to C:\Users\you\Desktop\Claude-Exports\2026-10-15_472b8bb8

Name              MB
----              --
transcript.html   2.3   self-contained page, images embedded - open it in a browser
transcript.md     0.6   the same conversation as Markdown
uploads           0.1   images you uploaded or dropped into the session
scratch           0.0   files Claude wrote during the session
```

## Install

Requires Windows, PowerShell 5.1+, [Claude Code](https://claude.com/claude-code), and
[`uv`](https://docs.astral.sh/uv/) on PATH (renders the transcript via
[`claude-code-log`](https://github.com/daaain/claude-code-log)).

```powershell
git clone https://github.com/4rvyn/claude-export.git
cd claude-export
powershell -ExecutionPolicy Bypass -File install.ps1
```

Wires up two things, both pointing at *this* clone - nothing else on your system is touched:

- a Claude Code skill (`/claude-export`)
- a shell command (`claude-export`, works in PowerShell, cmd and Git Bash)

Moved the clone? Run the install line again to repoint them. Add `-Check` to verify without changing anything.

## Use

```powershell
!claude-export                            # inside a Claude Code shell: zero tokens, current session
claude-export                             # any other shell: exports CLAUDE_CODE_SESSION_ID, if set
claude-export 472b8bb8                    # export by the start of a session ID
claude-export -List                       # show recent sessions
claude-export 472b8bb8 -Out D:\backups    # somewhere other than Desktop\Claude-Exports
claude-export 472b8bb8 -Depth agent       # condensed - no tool calls/results - for feeding to a fresh AI
/claude-export                            # ask Claude to run it for you (costs a few tokens)
```

<details>
<summary><b>Details</b> - how it finds a session, uninstalling, what it touches</summary>

### How it finds a session

Every Claude Code session is a `.jsonl` transcript under `~/.claude/projects/*/`. `claude-export`
matches your argument against the start of a session ID, and - because a resumed session gets a new ID
while its uploads/scratch stay filed under the old one - follows every ID the transcript itself mentions.

### Uninstall

```powershell
Remove-Item "$HOME\.claude\skills\claude-export" -Recurse
Remove-Item "$HOME\.local\bin\claude-export", "$HOME\.local\bin\claude-export.cmd"
```

Nothing else to clean up - `Export-ClaudeSession.ps1` itself never leaves the clone.

### What this touches

| | |
|---|---|
| **Reads** | your session transcripts (`~\.claude\projects\*\*.jsonl`), anything you uploaded into that session, and the Temp scratchpad Claude wrote to |
| **Writes** | the export folder (wherever `-Out` points), plus - only during `install.ps1` - the two entry points above |
| **Runs** | `uvx`, pinned to a specific version of `claude-code-log` (not "latest"), and `robocopy` to copy files locally |
| **Network** | one call, the `uvx` above, fetching that pinned package from PyPI the first time (cached after). Nothing else - your transcripts, uploads and scratch files are never sent anywhere |
| **Never** | telemetry, admin rights, registry changes, PATH changes, anything outside your profile folder and the export destination you choose |

You'll see `-ExecutionPolicy Bypass` in the launcher scripts - that's just the normal way an unsigned
PowerShell script runs on Windows, scoped to that one process. It doesn't touch your system-wide policy
or elevate anything. `Export-ClaudeSession.ps1` is under 100 lines and plainly commented if you want to
check all this yourself.

</details>

## License

MIT, see [LICENSE](LICENSE).
