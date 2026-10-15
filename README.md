# claude-export

Export a Claude Code session (this conversation, or any past one) into a single folder you can read,
search or hand to someone else, without going back through the model to do it.

```
transcript.html   self-contained page, images embedded - open it in a browser
transcript.md     the same conversation as Markdown, pasted images in images\
uploads\          images you uploaded or dropped into the session
scratch\          files Claude wrote during the session (its Temp scratchpad)
```

## Requirements

- Windows, PowerShell 5.1+ (bundled with Windows), [Claude Code](https://claude.com/claude-code).
- [`uv`](https://docs.astral.sh/uv/) on PATH, for `uvx` - the script shells out to
  [`claude-code-log`](https://github.com/daaain/claude-code-log) to render the transcript.
  `install.ps1` warns if `uvx` is missing; without it, the export still runs but
  `transcript.html`/`transcript.md` won't be created (uploads/scratch still get copied).

## Install

Clone this repo anywhere - it does not need to live in any particular folder - then run:

```powershell
git clone https://github.com/4rvyn/claude-export.git
cd claude-export
.\install.ps1
```

This copies two small entry points into place, with the path to *this* clone's
`Export-ClaudeSession.ps1` baked into them, so the real script itself stays here and is never
duplicated:

- the Claude Code skill, to `~/.claude/skills/claude-export/SKILL.md`
- the `claude-export` command (for `cmd`, PowerShell and Git Bash), to `~/.local/bin/`

Run `.\install.ps1 -Check` any time to verify both are in place and up to date with this folder. If
you move the clone to a different folder, run `.\install.ps1` again from the new location to repoint
them.

To uninstall, delete the two generated copies - nothing else to clean up:

```powershell
Remove-Item "$HOME\.claude\skills\claude-export" -Recurse
Remove-Item "$HOME\.local\bin\claude-export", "$HOME\.local\bin\claude-export.cmd"
```

## Use

**From inside a Claude Code session**, the cheapest way - it runs directly in your shell and never
reaches the model, so it costs no tokens:

```
!claude-export
```

Claude Code sets `$env:CLAUDE_CODE_SESSION_ID` in every `!`-prefixed command, so no argument is needed.

**From any other shell:**

```powershell
claude-export                # export the session CLAUDE_CODE_SESSION_ID points at (if set)
claude-export 472b8bb8        # export by the start of a session ID
claude-export -List           # show recent sessions (ID prefix, last used, size, project folder)
claude-export 472b8bb8 -Out D:\backups   # export somewhere other than ~\Desktop\Claude-Exports
claude-export 472b8bb8 -Depth agent      # condensed transcript for feeding to a fresh AI session
                                          # (drops tool calls/results; session/user/assistant/agent/tool/hook, default tool)
```

**By asking Claude** (it will run the skill above for you, through the model - costs a small number of
tokens for the one tool call):

```
/claude-export
```

## How it finds a session

Every Claude Code session is a `.jsonl` transcript under `~/.claude/projects/*/`. `claude-export` looks
there, matches your argument against the start of a session ID, and - because a resumed session gets a
new ID while its uploads and scratch files stay filed under the old one - follows every session ID the
transcript itself mentions when collecting those extra folders.

## What this touches

**Reads:**
- `~\.claude\projects\*\*.jsonl` — your session transcripts, to find and parse the one you're exporting
- `~\.claude\uploads\<session-id>\` — images you uploaded/dropped into that session
- `%LOCALAPPDATA%\Temp\claude\*\<session-id>\scratchpad` — files Claude wrote during that session

**Writes:**
- A new folder under `~\Desktop\Claude-Exports` (or wherever `-Out` points) containing
  `transcript.html`, `transcript.md`, `uploads\`, `scratch\`, and a small hidden `.session-id` marker
- `~\.claude\skills\claude-export\SKILL.md` and `~\.local\bin\claude-export(.cmd)` — only during
  `install.ps1`, and only those two small files, substituting the path to this clone

**Runs:**
- `uvx` (part of [`uv`](https://docs.astral.sh/uv/)), to fetch and run
  [`claude-code-log`](https://github.com/daaain/claude-code-log) — pinned to a specific known-good
  version (`claude-code-log@1.7.0`) rather than "latest," so a run today and a run next year use the
  exact same code
- `robocopy`, to copy the uploads/scratch folders locally (no network flags used)

**Network access:** the one `uvx claude-code-log@1.7.0` call above downloads that package from PyPI the
first time it runs (cached by `uv` after that). That's it. Nothing else in this repo makes a network
request, and that one call never uploads or transmits your transcripts, uploads, or scratch files
anywhere — it only pulls down a renderer that then runs entirely on your machine, reading and writing
local files.

**What it does NOT do:** no telemetry, no analytics, no phone-home, no admin/elevated rights needed or
requested, no registry changes, no modification of your system PATH, no files touched outside your own
user profile folder and the export destination you choose. `install.ps1` only ever writes the two
entry-point files listed above; everything else (`Export-ClaudeSession.ps1` itself) stays in this
cloned folder and is never copied anywhere.

You'll see `-ExecutionPolicy Bypass` in the launcher scripts (`bin/claude-export`,
`bin/claude-export.cmd`). This is not a security bypass of anything meaningful — it only tells that one
child PowerShell process to ignore the "don't run unsigned scripts" default, which is the normal,
necessary way any unsigned open-source PowerShell script runs on a default Windows install. It does not
touch the system-wide execution policy or elevate privileges.

Read `Export-ClaudeSession.ps1` yourself — it's under 100 lines, plainly commented, and this list is
exhaustive.

## Layout

```
Export-ClaudeSession.ps1      the real script - the only copy; everything else points at it
install.ps1                   wires up the two entry points below, substituting this clone's path
skill/claude-export/SKILL.md  source for the Claude Code skill (a template, see install.ps1)
bin/claude-export             source for the command (Git Bash, a template)
bin/claude-export.cmd         source for the command (cmd / PowerShell, a template)
tests/                        offline tests for the session-matching and safety-check logic
```

To change behaviour, edit `Export-ClaudeSession.ps1` here and run `.\install.ps1` again - there is
nothing to edit in `~/.claude` or `~/.local/bin` directly, those are generated copies.

## License

MIT, see [LICENSE](LICENSE).
