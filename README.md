# BeforeShow

Monorepo for BeforeShow, a concert-prep companion focused on helping users enter the show mood during the 14 days before a live event.

## Structure

- `apps/fake-door`: demand-validation landing page, app preview, waitlist surface, and event tracking client.
- `packages/core`: shared product constants, copy, and domain logic.
- `packages/ui`: shared UI tokens and reusable web/mobile-friendly primitives.
- `packages/config`: shared tooling config placeholder.

## Run The Fake Door

```bash
npm install
npm run dev
```

The fake-door app lives in `apps/fake-door`. It stores events and waitlist submissions in browser localStorage, then lets you export JSON or CSV from the experiment panel.

For local build verification:

```bash
npm run build:fake-door
```

For a hosted test with server-side event capture, set `VITE_BEFORESHOW_EVENT_ENDPOINT` before building or running the app.

## Run the local verification loop

The primary mode listens to a GitHub PR. For each new PR HEAD it creates an isolated worktree, runs tests, performs an explicitly team-signed simulator build, checks entitlements, boots iPhone 17, launches the app, and writes a SHA-stamped PR report under `.artifacts/local-verifier/`:

```bash
tools/ship-verify watch --pr 123 --interval 20 --publish
```

For a one-shot local check:

```bash
tools/ship-verify once --ref HEAD
```

Use `--ui-command` (or `VERIFY_UI_COMMAND`) to add a local Codex, Claude Code, AXe, or other simulator scenario. The command receives `VERIFY_REPO_ROOT`, `VERIFY_HEAD_SHA`, `VERIFY_APP_PATH`, `VERIFY_SIMULATOR_UDID`, `VERIFY_BUNDLE_ID`, and `VERIFY_REPORT_PATH`.

## Validation

Fake-door evidence lives in `.builder/evidence/experiments/` in this repo. The current test checks whether users with a real upcoming show will leave an email and name that show.
