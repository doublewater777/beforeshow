# Results

Removed memory fragments and travel planning from the product, together with the already-retired setlist feature:

- Removed iOS models, sessions, media/audio services, UI, navigation, notification targets, permissions, tests, prototype resources, and feature-specific design tokens.
- Removed the CloudBase generation contracts, provider clients, streaming code, tests, deployment script, model-provider configuration, and local provider environment keys.
- Deleted the deployed `generate` function; a follow-up function listing confirmed only `parseShowLink` remains online.
- Removed fake-door setlist/travel demos and rebuilt the countdown-only marketing surface.
- Removed obsolete ADRs, UX plans, design explorations, QA artifacts, and current product/App Store promises.
- Removed 448 MB of local in-repository DerivedData from obsolete builds.

Verification:

- Repository search found no retired feature identifiers or user-facing terms in iOS, CloudBase, or fake-door executable sources.
- Xcode project regeneration and iPhone 17 build succeeded.
- All 81 iOS tests passed.
- Fake-door production build passed.
- CloudBase parse-link suite passed 24 of 25 tests; the remaining public Damai PC integration fixture no longer returns a start time. Deterministic parser and entry tests passed, and this is unrelated to the removed generation backend.
- The final iPhone 17 screenshot shows the current-show hero and lifecycle countdown only.

Evidence:

- `docs/screenshots/2026-07-23-countdown-only-home.png`
