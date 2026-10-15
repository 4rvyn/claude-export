---
name: export-session
description: Export the current Claude Code session (transcript as HTML and Markdown, images, uploads, scratch files) into one folder on the Desktop.
disable-model-invocation: true
allowed-tools: PowerShell
---

Run this PowerShell command exactly once, then tell the user the folder path it printed and the list of what is in it. Do nothing else.

```powershell
& "$HOME\Desktop\tools\claude-export\Export-ClaudeSession.ps1" ${CLAUDE_SESSION_ID}
```

If the user passed a folder as an argument ($ARGUMENTS), add `-Out "<that folder>"` to the command.
