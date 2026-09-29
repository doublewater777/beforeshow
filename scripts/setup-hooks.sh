#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

chmod +x \
  "$REPO_ROOT/.githooks/commit-msg" \
  "$REPO_ROOT/scripts/validate-commit-msg.sh" \
  "$REPO_ROOT/scripts/setup-hooks.sh"

git -C "$REPO_ROOT" config core.hooksPath .githooks

echo "Installed git hooks via core.hooksPath=.githooks"
