---
name: loop-stop
description: Stop the current project's Codex Loop supervisor. Use for `$loop-stop` or an explicit request to stop a running loop.
---

# Stop Codex Loop

Run:

```bash
bash plugins/codex-loop/scripts/loop-stop.sh
```

Use `--cwd <directory>` to stop a loop for a different project. Only stop the loop identified by the plugin's own PID file; do not kill an unrelated process.
