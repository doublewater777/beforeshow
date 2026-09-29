#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PROJECT_YML="apps/ios/project.yml"
COMMIT_MSG_FILE="${1:-}"

if [[ -z "$COMMIT_MSG_FILE" || ! -f "$COMMIT_MSG_FILE" ]]; then
  echo "usage: validate-commit-msg.sh <commit-msg-file>" >&2
  exit 1
fi

read_version() {
  sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*$/\1/p' | head -n 1
}

SUBJECT=""
while IFS= read -r line || [[ -n "$line" ]]; do
  trimmed="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  if [[ -z "$trimmed" || "$trimmed" == \#* ]]; then
    continue
  fi
  SUBJECT="$trimmed"
  break
done < "$COMMIT_MSG_FILE"

if [[ -z "$SUBJECT" ]]; then
  echo "commit-msg: empty commit message" >&2
  exit 1
fi

if [[ "$SUBJECT" =~ ^(Merge|Revert|fixup\!|squash\!) ]]; then
  exit 0
fi

if [[ ! "$SUBJECT" =~ ^([0-9]+\.[0-9]+\.[0-9]+):\ .+ ]]; then
  cat >&2 <<'EOF'
commit-msg: invalid format

Subject must start with the app version:

  <version>: <description>

Example:
  1.0.2: feat: set a current show

See docs/agents/commit-convention.md
EOF
  exit 1
fi

COMMIT_VERSION="${BASH_REMATCH[1]}"
if ! git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACMR | grep -qx "$PROJECT_YML"; then
  EXPECTED_VERSION="$(read_version < "$REPO_ROOT/$PROJECT_YML")"
else
  STAGED_PROJECT="$(git -C "$REPO_ROOT" show ":$PROJECT_YML")"
  EXPECTED_VERSION="$(printf '%s\n' "$STAGED_PROJECT" | read_version)"
fi

if [[ -z "$EXPECTED_VERSION" ]]; then
  echo "commit-msg: could not read MARKETING_VERSION from $PROJECT_YML" >&2
  exit 1
fi

if [[ "$COMMIT_VERSION" != "$EXPECTED_VERSION" ]]; then
  cat >&2 <<EOF
commit-msg: version mismatch

  commit message: $COMMIT_VERSION
  expected:       $EXPECTED_VERSION

Use the MARKETING_VERSION in apps/ios/project.yml, or stage the version bump with this commit.
See docs/agents/commit-convention.md
EOF
  exit 1
fi
