---
name: claude-export
description: Export the current Claude Code session (transcript as HTML and Markdown, images, uploads, scratch files) into one folder on the Desktop.
disable-model-invocation: true
allowed-tools:
  - Bash(powershell -NoProfile -ExecutionPolicy Bypass -File *)
  - PowerShell
---

Run this command exactly once (it works from both the Bash and the PowerShell tool), then tell the user the folder path it printed and the list of what is in it. Do nothing else.

```
powershell -NoProfile -ExecutionPolicy Bypass -File "{{SCRIPT_PATH}}" ${CLAUDE_SESSION_ID}
```

If the user passed a folder as an argument ($ARGUMENTS), append `-Out "<that folder>"` to the command, without a trailing backslash (before a closing quote it escapes the quote).
