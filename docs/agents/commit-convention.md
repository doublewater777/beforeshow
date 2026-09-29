# Commit Convention

Every commit message is scoped to the app version it belongs to. The version must match the canonical `MARKETING_VERSION` in `apps/ios/project.yml`.

## Message format

```text
<version>: <description>
```

Use the current `major.minor.patch` version, followed by a colon, a space, and a short description. Keep the subject under 72 characters when practical. Use an imperative description and an optional Conventional Commits type.

Examples:

```text
1.0.2: feat: set a current show
1.0.2: fix(companion): preserve queued invites
1.0.2: chore: sync App Store metadata
1.0.2: release
```

The version may be changed in the same commit. Stage `apps/ios/project.yml` with the version bump first; the hook validates the message against that staged version. Since `project.yml` is the XcodeGen source of truth, run `cd apps/ios && xcodegen generate` and include the generated project changes in the commit.

## Install enforcement

Run once per clone:

```bash
./scripts/setup-hooks.sh
```

The `commit-msg` hook rejects subjects that omit the version, use an invalid version, or do not match the current or staged app version. Git-generated merge, revert, fixup, and squash subjects are exempt.

## Why version-scoped commits

- `git log --grep '^1.0.2:'` shows commits for a release line.
- Release notes and version history are easier to assemble.
- Version drift is caught before a commit is created.
