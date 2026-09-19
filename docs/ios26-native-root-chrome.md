# iOS 26 Native Root Chrome

> Status: Approved planning spec — 2026-09-19
> Planning base: `main@06ae043029ec798b2c0fac12f476ea6db3218571`
> Delivery model: two serial Phase Pilot implementation phases; one branch and one PR per phase.

## Problem

BeforeShow already has the intended navigation shape: three detached bottom controls, with Listen able to expand into a compact player. The remaining problem is that this chrome is installed as a custom bottom safe-area inset and carries an older-system fallback. Scrolling content can end against a hard visual boundary, pages can accumulate manual bottom compensation, Current Show atmosphere falls toward unrelated black near the Home Indicator, and the Listen morph uses delayed duplicate presentation state to coordinate with tab selection.

The goal is not to replace this navigation concept. The goal is to make it native to iOS 26: one stable root bar, system scroll-edge separation, Liquid Glass controls, state-driven motion, and feature-owned atmosphere.

## Product outcome

The three root destinations remain independent Liquid Glass controls floating over each page's own atmosphere. Scrolling foreground content softly recedes as it approaches them. Current Show cover color remains faintly present through the lower safe area. Moving between Current, Listen, and Footprints never changes root-bar height.

When a disc is loaded, Listen can become a compact player on other tabs. This is a horizontal Liquid Glass morph inside the same root bar, not a second player row and not a system tab-bar accessory.

## Durable decisions

### Platform baseline

BeforeShow requires iOS 26. The deployment target applies to app, widget, and tests through `apps/ios/project.yml`. Because the app has not launched, iOS 18–25 runtime compatibility is intentionally not preserved.

This does not trigger repository-wide removal of all availability checks. Only compatibility code made dead in the touched Bottom Chrome scope is removed.

### Root navigation ownership

- System `TabView` remains destination selection.
- The visible system Tab Bar remains hidden.
- Do not adopt `tabViewBottomAccessory`; the compact player is itself the morphing center navigation control.
- The only visible root navigation is custom Bottom Chrome with Current, Listen/mini-player, and Footprints.

### Safe-area and scroll-edge relationship

- Replace root `.safeAreaInset(edge: .bottom)` ownership with iOS 26 `.safeAreaBar(edge: .bottom, spacing: 0)`.
- Apply `.scrollEdgeEffectStyle(.soft, for: .bottom)` at the shared root.
- Do not hand-attach three feature-specific bottom blur modifiers.
- Do not add `.ultraThinMaterial`, bottom black gradients, backdrop rectangles, or private variable-blur filters behind chrome.
- The safe-area bar is the sole root-chrome occupancy source. Remove only spacers/insets whose purpose is duplicate Bottom Chrome clearance; keep normal feature content spacing.

### Layout invariants

- Root Bottom Chrome vertical height and bottom anchor are constant.
- Only the center Listen control may change width; mini-player appearance/disappearance must not change page safe-area height.
- The final interactive element of every top-level vertical scroll view must be fully reachable above chrome at rest.
- Background/atmosphere may extend through bottom safe area; foreground layout does not ignore the bar.

### Atmosphere ownership

Bottom Chrome owns no atmosphere. Current, Listen, and Footprints own their own backgrounds. For Current Show, tune existing `CurrentShowAmbientBackground` rather than adding a new bottom layer. Cover-derived hue should influence the lower screen faintly while the bottom remains dark. Exact opacity/radius values are validated on iPhone 17 rather than fixed by this spec.

### Liquid Glass motion

- `selectedTab` plus loaded-disc/player state decide circle versus compact player.
- Phase 2 removes `presentedTab`, `Task.yield()`, and fixed delayed choreography.
- Use one `GlassEffectContainer`, one shared Listen glass identity, `glassEffectTransition(.matchedGeometry)`, and native spring/fluid motion.
- Animation never changes root-bar height.
- Reduce Motion replaces geometric morph/spring with a short crossfade and continues to stop disc rotation.

## Existing implementation anchors

- `apps/ios/BeforeShow/RootView.swift` — root `TabView` and feature composition.
- `apps/ios/BeforeShow/Features/Listening/ListeningFeatureRootView.swift` — `ListeningRootChromeModifier`, currently installing Bottom Chrome with `.safeAreaInset`.
- `apps/ios/BeforeShow/Features/Listening/Views/ListeningPolishedBottomChrome.swift` — Liquid Glass chrome, legacy fallback, layout constants, delayed morph choreography.
- `apps/ios/BeforeShow/Features/CurrentShow/CurrentShowHomeView.swift` and `apps/ios/BeforeShow/UI/DesignSystem/BSStagePresentation.swift` — Current Show scroll composition and ambient background.
- `apps/ios/project.yml` — deployment-target/project source of truth.

`RootView.swift` remains routing/composition only; feature UI must not move into it.

## Global out of scope

- Restoring a visible system Tab Bar or using `tabViewBottomAccessory`.
- Redesigning root icons, destinations, or compact-player information hierarchy.
- Changing playback semantics, evidence persistence, remote commands, disc lifecycle, cold-start restoration, or MusicKit behavior.
- Adding custom/private variable backdrop blur.
- Repository-wide cleanup of all iOS availability branches.
- Applying root soft edge to detail screens, sheets, nested horizontal scrollers, or unrelated fixed controls.
- Pixel-perfect snapshot tests for system Liquid Glass.

## Testing strategy

System Liquid Glass and scroll-edge rendering are runtime behavior, so acceptance uses structural tests plus iPhone 17 runtime verification rather than brittle pixel snapshots. At each phase exact final HEAD: run architecture guard; run `xcodegen generate` after project-source changes and commit generated `.xcodeproj`; build/test with `DEVELOPMENT_TEAM=29C8MS76CZ`; run targeted Bottom Chrome/Listening regressions plus full relevant XCTest; install/launch on iPhone 17; verify no later-phase scope leakage.

## Phase Plan

### Phase 1 — iOS 26 Native Root Chrome

**Outcome**

Existing Bottom Chrome participates in native iOS 26 bottom safe-area/scroll-edge behavior with a stable vertical footprint. Compatibility code in touched Bottom Chrome scope is removed; existing circle/mini-player choreography remains until Phase 2.

**Scope**

- Raise deployment target to iOS 26 in `apps/ios/project.yml` for app/widget/tests through shared configuration and regenerate the Xcode project.
- Replace root `.safeAreaInset(edge: .bottom)` installation with `.safeAreaBar(edge: .bottom, spacing: 0)`.
- Apply shared bottom `.scrollEdgeEffectStyle(.soft, for: .bottom)`.
- Delete `ListeningLegacyDetachedBottomChrome` and Bottom Chrome `#available(iOS 26.0, *)` split.
- Remove duplicate page-level Bottom Chrome compensation only where inspection proves it exists.
- Ensure top-level feature backgrounds continue through bottom safe area while scroll content remains bar-aware.
- Keep compact-player data, controls, playback behavior, and current animation choreography.

**Out of scope**

- Do not remove `presentedTab`, `Task.yield()`, or rewrite morph animation.
- Do not tune Current Show ambient scrim/glow except a minimal change strictly required for safe-area painting.
- Do not change player synchronization, transport, remote commands, evidence projection, persistence, or disc lifecycle.
- Do not clean unrelated iOS <26 branches.

**Prerequisite**

Branch from the latest integrated `main` containing this approved spec and ADR; report the exact prerequisite SHA before editing.

**Acceptance criteria**

- App, widget, and tests resolve with iOS 26 minimum target.
- No legacy Bottom Chrome implementation remains.
- Bottom Chrome is installed through the native bottom safe-area bar relationship.
- All three root tabs receive bottom soft scroll edge without three feature modifiers.
- No extra Material/gradient/backdrop is introduced behind root chrome.
- Bottom Chrome height is identical in disc-circle and compact-player states.
- Final interactive content on all three root tabs can rest fully above chrome.
- Tab switching introduces no new vertical content jump.
- Existing playback and compact-player behavior is unchanged.

**Verification**

- architecture guard PASS;
- `xcodegen generate` PASS and generated project committed;
- targeted Bottom Chrome/Listening tests PASS;
- signed iPhone 17 simulator build/test PASS;
- simulator install + launch survival PASS;
- runtime checks for all tabs, final-scroll position, no-disc/loaded-disc, repeated tab switching;
- PR review confirms no Phase 2 scope leakage.

**Delivery**

One branch, one PR, one exact final HEAD. Stop at review/verification checkpoint; do not merge unless separately authorized and do not begin Phase 2.

### Phase 2 — Liquid Glass Motion & Atmosphere

**Outcome**

Bottom Chrome uses one iOS 26 state-driven Liquid Glass morph with accessibility-aware motion, and Current Show cover atmosphere remains perceptible through lower safe area without a new bottom layer.

**Scope**

- Remove `presentedTab`, `Task.yield()`, and old delayed/fixed-duration morph coordination.
- Derive center-control presentation directly from `selectedTab` and loaded-disc/player state.
- Use `GlassEffectContainer + glassEffectID + glassEffectTransition(.matchedGeometry)` with native spring/fluid motion.
- Preserve constant root-bar height and horizontal-only center expansion.
- Under Reduce Motion, use a short crossfade; keep disc rotation disabled.
- Tune `CurrentShowAmbientBackground` so cover hue reaches lower safe area faintly while retaining dark contrast.
- Keep Bottom Chrome backgroundless: no new Material, black gradient, or custom blur.

**Out of scope**

- No playback state-machine, MusicKit, remote-command, persistence, evidence, or cold-start behavior changes.
- No mini-player information-architecture redesign.
- No shared atmosphere system across tabs.
- No global iOS 26 cleanup outside touched code.

**Prerequisite**

Phase 1 must be independently verified, passed, merged, and Phase 2 must branch from the resulting integrated `main` SHA.

**Acceptance criteria**

- Circle ⇄ compact-player transition is driven by product state with no delayed duplicate tab state.
- Rapid Current ↔ Listen switching does not flicker, pass through an incorrect intermediate state, or vertically move page content.
- Disc insertion/ejection and tab changes use the same transition model.
- Reduce Motion uses a short non-geometric transition and no disc rotation.
- Current Show bottom remains dark but visibly belongs to active cover atmosphere.
- Scroll foreground still uses system soft edge and does not blur atmosphere itself.
- Root bar vertical geometry remains unchanged.
- Existing playback controls and state synchronization remain behaviorally unchanged.

**Verification**

- architecture guard PASS;
- targeted motion/chrome/Listening regressions PASS;
- full relevant XCTest PASS;
- signed iPhone 17 simulator build/test PASS;
- install + launch survival PASS;
- runtime checks for all tabs, no-disc/loaded-disc, playing/paused, insert/eject, rapid tab switching, cold-start loaded-disc restoration, varied Current cover colors, and Reduce Motion;
- PR review confirms no out-of-scope playback or repository-wide cleanup.

**Delivery**

One branch, one PR, one exact final HEAD. Stop at merge checkpoint unless separately authorized.

## Final integrated acceptance

After both phases are merged, independently verify integrated `main`: all relevant regressions pass; root navigation is one stable three-control Liquid Glass chrome; no visible system Tab Bar or second mini-player row exists; soft scroll-edge separation is present on all three root tabs; no page ends with content hidden by chrome; Current Show atmosphere reaches lower safe area without an unrelated black band; Reduce Motion is correct; playback/remote/persistence/evidence/cold-start behavior has no regression.
