# Support iOS 17 with progressive native enhancement

## Status

Accepted — 2026-10-17. Supersedes the minimum-version part of ADR 0035.

## Context

ADR 0035 raised the minimum to iOS 26 so root chrome could use Liquid Glass, safe-area bar and scroll-edge APIs without availability branches. BeforeShow has since shipped, and 1.0.3 lowered the deployment target to iOS 17.0 for the app, widget and tests. The rest of ADR 0035 — the root Bottom Chrome product model — is unrelated to the minimum version and still holds.

## Decision

- The minimum supported iOS version is **17.0** for the app, widget and test targets. `apps/ios/project.yml` declares it once; no target overrides it. `scripts/check_architecture.py` fails if `project.yml` or the generated `project.pbxproj` drift.
- Compatibility matrix: **iOS 17** (minimum) and **iOS 27** (latest). Intermediate releases are not separately verified.
- Core functionality must not depend on an API newer than iOS 17. Newer APIs are gated with `if #available` at the API's real availability, with a working iOS 17 fallback.
- The latest OS uses Apple's current native API and syntax, not a hand-rolled substitute. The iOS 17 path only needs to work; it does not imitate the newer look.
- Liquid Glass, safe-area bar and scroll-edge effects go through the `BS*` wrappers in `UI/DesignSystem/BSPlatformCompatibility.swift` and `BSChrome.swift`; feature code does not branch on OS version for these.
- Kept from ADR 0035, unchanged: the hidden system Tab Bar, one custom root Bottom Chrome (Current, Listen/compact player, Footprints), Listen morphing into the compact player, no `tabViewBottomAccessory`, no extra Material/black backdrop behind chrome.

## Consequences

- New root-chrome work may no longer call iOS 26+ APIs without an availability branch; the compiler enforces this at the iOS 17 deployment target.
- On iOS 17 the root chrome falls back to `safeAreaInset` and `.regularMaterial` capsules without glass morphing; layout, tab switching and player behavior are the same.
- Every UI change is checked on an iOS 27 simulator and an iOS 17 device; a combination that cannot be run is stated in the PR.
