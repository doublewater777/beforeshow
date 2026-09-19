# Require iOS 26 and use native root chrome APIs

## Status

Accepted — 2026-09-19

## Context

BeforeShow is not yet released. The project currently carries an iOS 18 deployment target while root navigation already prefers iOS 26 Liquid Glass when available and keeps a fallback implementation for older systems.

The intended root navigation is three detached controls, with Listen able to become a compact player. iOS 26 provides native safe-area bar, scroll-edge, and Liquid Glass transition APIs that fit this product model without a hand-built backdrop.

Keeping iOS 18–25 support would preserve parallel visual/layout paths for a product that has not shipped.

## Decision

- Set the minimum supported iOS version to 26 for the app, widget, and tests.
- Keep the system Tab Bar hidden; it remains a destination-selection mechanism only.
- Keep one custom visible root Bottom Chrome composed of Current, Listen/compact-player, and Footprints.
- Use iOS 26 native safe-area bar and scroll-edge APIs for the root bottom-bar relationship.
- Use native Liquid Glass primitives for root controls and their state transitions.
- Do not adopt `tabViewBottomAccessory`; the compact player is the morphing center navigation control, not a separate accessory above a visible Tab Bar.
- Remove compatibility code only in the Bottom Chrome scope as this work lands; repository-wide availability cleanup is separate.

## Consequences

- Devices on iOS 25 and earlier cannot install this version.
- New root-chrome work may use iOS 26 APIs directly without availability branches.
- Custom Bottom Chrome must participate in system safe-area and scroll-edge behavior instead of emulating those relationships with duplicate insets/backdrops.
- Page backgrounds remain feature-owned and may extend behind root chrome; chrome does not introduce a fixed Material or black background.
