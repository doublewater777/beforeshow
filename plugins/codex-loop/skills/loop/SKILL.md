---
name: loop
description: Start a bounded background loop of fresh `codex exec` runs in the current project. Use for `$loop`, repeated Codex execution, or periodic checks.
---

# Codex Loop

Use this skill when the user asks for `$loop <interval> <prompt>` or asks Codex to repeat a task periodically.

The loop runs a fresh non-interactive `codex exec` in the current project for each round. Because each round is a new session, prompts should tell Codex to inspect the repository and durable project state such as `TODO.md` before acting.

Start it with the plugin's `scripts/loop.sh`:

```bash
bash plugins/codex-loop/scripts/loop.sh start 1m --max-rounds 20 -- "Inspect the current project, run the relevant tests, and fix the next incomplete task."
```

Rules:

- Accept intervals in seconds, minutes, or hours, such as `30s`, `1m`, or `2h`.
- Default to 20 rounds. Use `--forever` only when the user explicitly requests an unbounded loop.
- Use `--until-success` when the user's goal is to stop after the first successful `codex exec`.
- Keep the loop in the current project unless the user explicitly provides `--cwd`.
- Do not add `--dangerously-bypass-approvals-and-sandbox`; the script intentionally leaves approval and sandbox policy under the user's Codex configuration.
- Report the supervisor PID, working directory, and log path after starting.

For status and stopping, use the companion skills `$loop-status` and `$loop-stop`.
