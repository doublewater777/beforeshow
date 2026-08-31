# GitHub PR local verifier

`tools/ship-verify` is a single-purpose local listener for GitHub PRs. It does not require a Chat workflow or Plugin.

```text
GitHub PR HEAD → isolated worktree → tests → team build → iPhone 17 Simulator → launch smoke → optional UI agent → PR report
```

## Automatic discovery

Install the macOS background listener once:

```bash
tools/ship-verify install
```

It starts at login and polls all open GitHub PRs. You do not pass a PR number. Every new PR HEAD is verified once, and the result is published to that PR. The installer keeps a private Git cache, state, reports, and logs under `~/Library/Application Support/BeforeShow/local-verifier/`, outside Desktop/Documents protection.

If launchd reports `Operation not permitted` for a checkout under macOS Desktop/Documents, grant the shell/host app Full Disk Access or place the checkout outside those protected folders, then run `tools/ship-verify install` again.

To run it in the foreground instead:

```bash
tools/ship-verify watch --interval 20 --publish
```

The optional `--pr NUMBER` form remains available when you want to focus on one PR.

## One committed HEAD

Run this from a clean checkout:

```bash
tools/ship-verify once --ref HEAD
```

The default iOS checks are:

1. `git diff --check`
2. `xcodebuild test` on iPhone 17
3. `xcodebuild build` with `DEVELOPMENT_TEAM=29C8MS76CZ`
4. `Entitlements-Simulated.plist` contains the iCloud container entitlement
5. install and launch `com.doublewaterapps.beforeshow` on iPhone 17
6. keep the launched process alive for two seconds

Reports and logs are local-only under `.artifacts/local-verifier/`, which is ignored by Git.

## Follow a PR

```bash
tools/ship-verify watch --pr 123 --interval 20 --publish
```

Every new PR HEAD is fetched and checked out in a temporary detached worktree, so the verifier does not alter the working tree where you are developing. `--publish` adds the resulting `LOCAL_AGENT_VERIFY` report as a PR comment; without it, the report remains local.

For a bounded smoke test of the watcher:

```bash
tools/ship-verify watch --pr 123 --max-runs 1
```

## Add a real UI scenario

Pass a command that drives the already-installed app with the local tool of your choice:

```bash
VERIFY_UI_COMMAND="$PWD/path/to/your-simulator-scenario" \
  tools/ship-verify once --pr 123
```

The command receives:

```text
VERIFY_REPO_ROOT VERIFY_HEAD_SHA VERIFY_APP_PATH VERIFY_SIMULATOR_UDID
VERIFY_BUNDLE_ID VERIFY_REPORT_PATH
```

This is the seam for Codex, Claude Code, AXe, or another Computer Use runner. The first version deliberately keeps that runner injectable because the correct UI scenario depends on the feature being changed.
