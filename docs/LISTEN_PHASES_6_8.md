# Listen Phases 6–8 integration

This delivery builds on the merged Phase 1–5 domain, repositories and transport.
The existing branch and physical CD player/cabinet are retained by explicit product instruction.

## Confirmed amendments to Spec v1.1

- Navigation is Current / Listen / Footprints.
- The physical player and cabinet replace the generic artwork-first player card. Song metadata, capability, familiarity, upcoming song and show-scoped expectations accompany the machine.
- Default preparation CD uses the existing whole-show round-robin queue policy.
- Selecting an album uses album order. Its last track stops. Back to whole show restores the preparation CD.
- Disc changes use the same mechanical release/remove/insert/seat/close chain.
- No vertical swipe-to-skip. The lid owns its drag and the physical transport owns navigation.
- No manual heard/undo UI. Existing manual evidence and repository APIs remain intact for historical data and Phase 1–5 invariants.
- Actual full listening must strictly exceed 50%. Preview never writes automatic familiarity.
- Wants Live freezes at opening; canceled shows cannot mutate expectations.

## Ownership

- `ListeningRoomCoordinator` owns room state and intent orchestration; `ListeningPlaybackController` remains the transport/evidence boundary.
- `ListeningPresentation` defines page states and lifecycle-pause policy.
- `ListeningArtistPresentation` projects trusted snapshots; top songs are only snapshot.topSongIDs.
- First-page MusicKit songs can enter an in-memory runtime queue while full catalog loads. These songs never become the completeness denominator or overwrite a snapshot.
- Artist matching retains the existing iTunes service, an ephemeral candidate selection, and an explicit confirmation mutation.
- `FootprintListeningCoordinator` owns recall transactions and uses the existing baseline/evidence repository seams.
- `FootprintDetailView` embeds one feature section; no hotspot budget increase.

## Isolated debug fixtures

Use `--listen-fixture` followed by `no-current`, `single-full`, `multi-full`, `preview-only`, `metadata-only`, `cached-error`, or `ended-current`.
Each uses an in-memory ModelContainer, injected catalog service and simulated transport. Full/preview fixture playback is a test clock, not real audio. No Apple Music networking or production persistence is used.
The older `--listening-fixture` flag maps to metadata-only.

## Verification

Run XcodeGen and architecture guard, then signed tests with `-allowProvisioningUpdates DEVELOPMENT_TEAM=29C8MS76CZ` on iPhone 17.
New test suites cover presentation, three-language keys, accessibility wiring, lifecycle, artist confirmation/preferences/library/rematch, historical tiers, recall evidence and cleanup. Existing Phase 1–5 tests remain part of the full suite.
Real MusicKit subscription, denied-authorization and physical-device audio behavior require separate device/account verification; fixture playback must never be represented as that verification.
