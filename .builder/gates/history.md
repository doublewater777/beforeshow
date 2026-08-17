# Gate History

## 2026-08-15 · Widget Glance Simplify

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-15-widget-glance-simplify/`

Verdict: unknown — cycle opened, not passed.

Evidence: HIG says a small widget typically shows one idea; current small/medium stacked kicker, badge, date, and venue.

Weakest assumption: show name plus the countdown number is enough to recognize the next show.

Decision: small = number + name; medium adds cover only; leave lock-screen families alone.

Next stage: stay on manual-onboarding; verify on iPhone 17 Home Screen.

Loop-back: if live and near clocks collide visually, tint is the only extra cue allowed.

## 2026-08-15 · Widget Ambient Bloom

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-15-widget-ambient-bloom/`

Verdict: unknown — cycle opened, not passed.

Evidence: home already extracts a top-band stage color; widgets still used a flat navy `containerBackground`.

Weakest assumption: the cached cover yields a bloom that still reads at widget size.

Decision: reuse the home extractor on small/medium widgets only; keep lock-screen monochrome.

Next stage: stay on manual-onboarding; verify on iPhone 17.

Loop-back: if the bloom is invisible or muddy, simplify the wash before touching copy.

## 2026-08-15 · First TestFlight Build

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-15-first-testflight-build/`

Verdict: unknown — cycle opened, not passed.

Evidence: ASC `builds list` is empty; 2026-06-16 local IPA existed but object-storage upload failed.

Weakest assumption: this machine can reach Apple object storage and produce a VALID TestFlight build.

Decision: unlock internal TestFlight before any App Store metadata work.

Next stage: stay on manual-onboarding until a VALID build is installable from TestFlight.

Loop-back: if upload fails twice, stop and change network/machine; do not start store listing.

## 2026-06-08

Stage: fake-door

Cycle: `.builder/cycles/2026-06-08-fake-door-validation/`

Decision: implementation-ready, not validated yet.

Reason: the fake-door surface now exists and can collect local evidence, but no target-user traffic has been run.

## 2026-06-14

Stage: business-model

Cycle: `.builder/cycles/2026-06-14-pro-membership/`

Decision: hypothesis only, not validated.

Reason: Pro membership is now part of the intended V2.1 packaging, but free allowance, price, and payment behavior evidence are still undecided.

## 2026-06-16

Stage: business-model

Cycle: `.builder/cycles/2026-06-16-core-show-loop/`

Decision: implementation in progress, validation pending.

Reason: the V2.1 goal has shifted from membership alone to a TestFlight-usable loop across Tonight First Listen, round-trip planning, preview, preparation, fragments, and Pro repeat-generation limits.

## 2026-06-23

Stage: business-model

Cycle: `.builder/cycles/2026-06-23-home-visual-redesign/`

Decision: implementation in progress, validation pending.

Reason: the V2.1 loop exists, but the home surface needs a stronger theatrical visual language, clearer current-show focus, and a simpler two-entry action model before user validation.

## 2026-07-19

Stage: business-model

Cycle: `.builder/cycles/2026-07-19-global-transit-eta/`

Decision: implementation in progress, validation pending.

Reason: MapKit can return public-transit ETA globally where supported but does not expose complete transit route steps; the product will test whether ETA, manual-duration fallback, and Apple Maps handoff are sufficient for trip planning.

## 2026-07-20

Stage: business-model

Cycle: `.builder/cycles/2026-07-20-setlist-reliability-verification/`

Decision: implementation and simulator verification complete; user validation pending.

Reason: generation now requires an explicit contract-valid final response, cancellation preserves the prior catalog, and festival lineup edits remain local until confirmation; responsiveness and real-user trust still require release observation.

## 2026-07-23

Stage: business-model

Cycle: `.builder/cycles/2026-07-23-remove-setlist-guess/`

Decision: remove the setlist-guess feature before launch.

Reason: the product owner chose to narrow BeforeShow around the current-show countdown; the speculative setlist workflow, data model, notifications, and Pro packaging no longer support that focus.

## 2026-07-23 · Memory and travel retirement

Stage: business-model

Cycle: `.builder/cycles/2026-07-23-remove-memory-and-travel/`

Decision: remove memory fragments and travel planning before launch.

Reason: the product owner chose a single current-show countdown wedge; local journaling, route planning, media permissions, and AI trip generation create a broader product than intended.

## 2026-07-23 · Add Show Reliability

Stage: business-model

Cycle: `.builder/cycles/2026-07-23-add-show-flow-reliability/`

Decision: implementation and simulator verification complete; user validation pending.

Reason: required time data, notification activation, duplicate-save protection, actionable recovery, and local cover cleanup now share tested invariants; release-user observation is still needed for the permission and completion handoff.

## 2026-07-31 · Current Show Management

Stage: business-model

Cycle: `.builder/cycles/2026-07-31-current-show-management/`

Decision: implementation-ready, user validation pending.

Reason: the product owner supplied a bounded V2.4 current-show management prototype and explicitly excluded future lists, history, statistics, and prototype navigation; the remaining risk is whether phase-driven shortcuts appear at the right moment.

## 2026-08-01 · Footprints Archive

Stage: business-model

Cycle: `.builder/cycles/2026-08-01-footprints-archive/`

Decision: implementation and simulator verification complete; repeat-user validation pending.

Reason: ended shows now produce a prototype-faithful personal archive with search, filters, rankings, yearly history, existing-flow backfill, and share-card export, but the Current / Footprints split still needs behavioral evidence.

## 2026-08-02 · Companion Icon States

Stage: business-model

Cycle: `.builder/cycles/2026-08-02-companion-icon-states/`

Decision: implementation and simulator verification complete; user comprehension validation pending.

Reason: the companion shortcut now preserves invitation, confirmation, cancellation, and shared-footprint states with a system-share handoff, but the local manual-confirmation model still needs real-user evidence before any account or remote-acceptance investment.

- 2026-08-02 companion P1 review fixes: share persistence gating, cancel restore, history identity, lifecycle invariants; 153 tests.

## 2026-08-03 · Current-show Memory Fragments

Stage: business-model

Cycle: `.builder/cycles/2026-08-03-current-show-memory-fragments/`

Decision: implementation-ready, user value validation pending.

Reason: the product owner explicitly reintroduced memory capture as one private, local-only shortcut bound to the current show, while keeping history, social, sharing, cloud, audio, and AI out of scope. The riskiest question is whether capture remains lighter than using general-purpose Photos or Notes.

- 2026-08-03 implementation verification: text and ordered mixed-media flows passed on iPhone 17; 213 tests passed; physical-device camera and release-user value remain pending.

## 2026-08-04 · Ticket and Timetable Assets

Stage: business-model

Cycle: `.builder/cycles/2026-08-04-ticket-timetable-assets/`

Decision: implementation and simulator verification complete; user-value validation pending.

Reason: ticket and timetable images now have local, show-bound storage with explicit non-official-ticket positioning, while shared media transaction boundaries and durable-storage failure behavior were hardened during adversarial review.
