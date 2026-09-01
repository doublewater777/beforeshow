#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

IOS_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = IOS_ROOT.parents[1]

# Legacy files that are already too large. The guard does not demand an immediate
# rewrite; it prevents these hotspots from growing without an explicit budget change.
HOTSPOT_BUDGETS = {
    "BeforeShow/RootView.swift": 60_000,
    "BeforeShow/HomeHeroPresentation.swift": 12_000,
    "BeforeShow/Features/CurrentShow/CurrentShowHomeView.swift": 24_000,
    "BeforeShow/Features/CurrentShow/CurrentShowManagementView.swift": 40_000,
    "BeforeShow/Features/CurrentShow/CurrentShowCompanionView.swift": 28_000,
    "BeforeShow/AddShowFlowViews.swift": 155_000,
    "BeforeShow/FootprintsArchive.swift": 105_000,
    "BeforeShow/FootprintArchiveViews.swift": 125_000,
    "BeforeShow/MemoryFragmentsView.swift": 95_000,
    "BeforeShow/BeforeShowApp.swift": 26_000,
    "BeforeShow/Show.swift": 24_000,
}

ROOT_VIEW_FORBIDDEN_TOKENS = (
    "import PhotosUI",
    "PhotosPickerItem",
    "DynamicCoverImportCoordinator",
    "WidgetDataSync.sync",
    "LocalNotificationCenter.shared.reconcileFocus",
    "struct CurrentShowManagementSection",
    "struct CurrentShowCompanionSheet",
)

HOME_HERO_FORBIDDEN_TOKENS = (
    "import PhotosUI",
    "struct CurrentShowHomeView",
    "struct CurrentShowManagementSection",
    "struct CurrentShowCompanionSheet",
)


def git(*args: str) -> str:
    return subprocess.check_output(
        ["git", *args],
        cwd=REPO_ROOT,
        text=True,
        stderr=subprocess.DEVNULL,
    ).strip()


def resolve_base_ref(explicit: str | None) -> str | None:
    candidates = [explicit]
    github_base = os.environ.get("GITHUB_BASE_REF")
    if github_base:
        candidates.extend((f"origin/{github_base}", github_base))
    candidates.append("HEAD^")

    for candidate in candidates:
        if not candidate:
            continue
        try:
            git("rev-parse", "--verify", candidate)
            return candidate
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
    return None


def added_swift_files(base_ref: str | None) -> list[str]:
    if base_ref is None:
        return []
    try:
        output = git("diff", "--name-status", "--diff-filter=A", f"{base_ref}...HEAD")
    except subprocess.CalledProcessError:
        output = git("diff", "--name-status", "--diff-filter=A", base_ref, "HEAD")

    added: list[str] = []
    for line in output.splitlines():
        if not line:
            continue
        _, path = line.split("\t", 1)
        prefix = "apps/ios/"
        if path.startswith(prefix) and path.endswith(".swift"):
            added.append(path[len(prefix):])
    return added


def check_hotspot_budgets(errors: list[str]) -> None:
    for relative_path, max_bytes in HOTSPOT_BUDGETS.items():
        path = IOS_ROOT / relative_path
        if not path.exists():
            continue
        size = path.stat().st_size
        if size > max_bytes:
            errors.append(
                f"{relative_path} is {size:,} bytes (budget {max_bytes:,}). "
                "Split responsibilities before adding more code, or move code out and update the budget intentionally."
            )


def check_forbidden_tokens(
    relative_path: str,
    tokens: tuple[str, ...],
    boundary_description: str,
    errors: list[str],
) -> None:
    path = IOS_ROOT / relative_path
    if not path.exists():
        return
    content = path.read_text()
    for token in tokens:
        if token in content:
            errors.append(
                f"{relative_path} contains forbidden token {token!r}. {boundary_description}"
            )


def check_presentation_boundaries(errors: list[str]) -> None:
    check_forbidden_tokens(
        "BeforeShow/RootView.swift",
        ROOT_VIEW_FORBIDDEN_TOKENS,
        "Keep RootView limited to app/root routing and DEBUG support.",
        errors,
    )
    check_forbidden_tokens(
        "BeforeShow/HomeHeroPresentation.swift",
        HOME_HERO_FORBIDDEN_TOKENS,
        "Keep this file limited to reusable hero snapshot/stage presentation.",
        errors,
    )


def check_new_file_locations(base_ref: str | None, errors: list[str]) -> None:
    for relative_path in added_swift_files(base_ref):
        if not relative_path.startswith("BeforeShow/"):
            continue
        if Path(relative_path).parent.as_posix() != "BeforeShow":
            continue
        errors.append(
            f"new app source {relative_path} was added to the legacy BeforeShow root. "
            "Place new feature code under BeforeShow/Features/<Feature>/; use App, Domain, "
            "Infrastructure, or UI only when that ownership is genuinely cross-feature."
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Guard BeforeShow iOS architecture boundaries.")
    parser.add_argument("--base-ref", default=None)
    args = parser.parse_args()

    errors: list[str] = []
    base_ref = resolve_base_ref(args.base_ref)
    check_hotspot_budgets(errors)
    check_presentation_boundaries(errors)
    check_new_file_locations(base_ref, errors)

    if errors:
        print("iOS architecture guard failed:\n")
        for error in errors:
            print(f"- {error}")
        return 1

    print("iOS architecture guard passed.")
    if base_ref:
        print(f"Compared new Swift files against {base_ref}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
