---
name: loop-status
description: Inspect the current project's Codex Loop process, configuration, and temporary log path. Use for `$loop-status`.
---

# Codex Loop Status

Run:

```bash
bash plugins/codex-loop/scripts/loop-status.sh
```

Use `--cwd <directory>` to inspect a different project. Report whether the loop is running, its PID when active, its configured interval and limit, and the log path. Do not start or modify a loop while checking status.
