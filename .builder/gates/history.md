# Gate History

## 2026-08-24 · Live Activity Rendering Reliability

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-24-live-activity-rendering-reliability/`

Verdict: local implementation and iPhone 17 simulator verification complete; real-device verification pending.

Evidence: `WidgetSnapshotTests` pass, the app builds for iPhone 17 on iOS 26.5, compact and expanded Dynamic Island render complete digital countdowns, and the lock-screen banner still renders without the skeleton fallback.

Weakest assumption: the system `.timer` remains renderer-safe while crossing from countdown to elapsed time.

Decision: use the system date timer for the lock-screen banner and codable system digital timer/stopwatch formats for Dynamic Island.

Loop-back: revisit the timer presentation if the banner returns to a skeleton or fails to advance across show start.

## 2026-08-23 · Onboarding Feature Intro

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-23-onboarding-feature-intro/`

Verdict: local implementation and iPhone 17 simulator verification complete; release measurement pending.

Evidence: the iPhone 17 build succeeded, focused onboarding tests passed 5/5, and manual QA completed the full first-show creation flow and persistence check across relaunch.

Weakest assumption: four explanatory pages improve understanding without reducing first-show creation.

Decision: use a native lifecycle introduction, reuse the existing add-show flow, and only complete onboarding after a saved first show.

Next stage: stay on manual-onboarding and measure progression plus D0 first-show creation after release.

Loop-back: simplify the sequence if first-show creation falls by 10% relative or first-page skipping is unusually high.

## 2026-08-23 · NetEase Music Link Import

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-23-netease-music-link-import/`

Verdict: deployed and verified online.

Evidence: 171/171 non-live-integration cloud tests pass; the iPhone 17 simulator build and focused iOS tests pass; an authenticated post-deploy invocation for concert `33678541` returned HTTP 200 with 26 artists and 26 avatar URLs.

Weakest assumption: the unauthenticated NetEase Music concert detail endpoint remains stable after deployment.

Decision: support only strict `st.music.163.com` detail links carrying `concertId`; do not classify ordinary music links or guess a show from the ticket homepage.

Loop-back: if the provider adds authentication or changes the detail contract, replace the adapter rather than broadening HTML scraping.

## 2026-08-23 · Add Show Home Arrival

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-23-add-show-home-arrival/`

Verdict: implementation and iPhone 17 simulator verification complete; real-device validation pending.

Evidence: the app builds for iPhone 17, 23/23 focused tests pass, and a temporary simulator recording shows completion-card → cover → countdown → actions with no blank frame.

Weakest assumption: the 420 ms completion card is readable without making save feel slower.

Decision: keep the animation keyed to the newly added current-show ID and leave tabs, historical backfill, and selection rules unchanged.

## 2026-08-23 · Share Image Actions and Keepsake Clearance

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-23-share-image-actions-and-keepsake-clearance/`

Decision: implementation and iPhone 17 simulator verification complete; real-device validation pending.

Reason: image sharing now exposes only save/share actions, and the single-show detail keeps its ticket and timetable content outside the bottom share operation area.

## 2026-08-23 · Home Live Status Copy

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-23-home-live-status-copy/`

Verdict: implementation and iPhone 17 simulator verification complete; user validation pending.

Evidence: `ArchitectureModuleTests` passed 16/16; the iPhone 17 simulator screenshot shows the requested left status group and trailing timer group.

Weakest assumption: 「正在现场」 remains clearer than a shorter live-state label when paired with the elapsed timer.

Decision: keep lock-screen widgets, Live Activity, notifications, and countdown calculations unchanged.

Next stage: stay on manual-onboarding; verify on iPhone 17.

Loop-back: if the live timer stack is not visibly right-aligned or the pre-start copy remains unclear.

## 2026-08-19 · Opening Memory Window

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-19-opening-memory-window/`

Verdict: unknown — cycle opened, local implementation in progress.

Evidence: grilling + ADR 0033; live primary used to be End Show.

Weakest assumption: people will capture a fragment in the first hour if the primary button asks for it.

Decision: first hour from show start is the opening memory window; quiet notification at start; End Show demoted to shortcuts.

Next stage: stay on manual-onboarding; verify on iPhone 17.

Loop-back: if nobody taps capture or the notification feels like an interruption.

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

## 2026-08-18 · RevenueCat Migration

Stage: business-model

Cycle: `.builder/cycles/2026-08-18-revenuecat-migration/`

Decision: code cutover complete; dashboard and production key still open.

Reason: StoreKit 2 purchase/restore was replaced with RevenueCat offerings and the `pro` entitlement. Debug uses Test Store; Release still needs an `appl_` key and catalog confirmation before sandbox/TestFlight purchases.

## 2026-08-22 · Dynamic Memory Time Labels

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-22-dynamic-memory-time-labels/`

Decision: implementation in progress; verify dynamic phase grouping after show end-time edits.

Reason: memory fragments currently display a phase persisted at creation time, so correcting the actual end time can leave the timeline labels stale.

## 2026-08-23 · Live Activity Banner Alignment

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-23-live-activity-banner-alignment/`

Decision: implementation and iPhone 17 simulator verification complete; real-device validation pending.

Reason: the requested layout change is limited to trailing alignment and metadata spacing; the simulator confirms the cover, timer, progress bar, and started-state status remain visible.

## 2026-08-23 · Medium Widget Cover Corners

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-23-medium-widget-cover-corners/`

Decision: implementation and iPhone 17 simulator build verification complete; visual device validation pending.

Reason: the medium widget keeps its existing left-content/right-cover layout while the cover now uses a continuous rounded mask, so the requested visual correction is isolated and low-risk.

## 2026-08-23 · Show Library Cover View

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-23-show-library-cover-view/`

Decision: implementation and iPhone 17 simulator verification complete; repeat-user validation pending.

Reason: people with many saved shows need a denser visual browsing option while retaining the existing detail-rich list and management actions.

## 2026-08-25 · Footprints Final UI

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-25-footprints-final-ui/`

Decision: implementation and iPhone 17 verification complete; repeat-user validation pending.

Reason: the supplied final archive design replaces the less-direct heatmap with a one-dot-per-show rhythm and strengthens artist, city, and venue exploration without changing archive identity rules.

## 2026-08-25 · Footprints Year Archive

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-25-footprints-year-archive/`

Decision: implementation and iPhone 17 verification complete; repeat-user validation pending.

Reason: the dashboard's existing “All Years” action now reaches a year-switching archive with derived stats, monthly rhythm, a highlight show, and detail-linked records.

## 2026-08-25 · Footprints Rhythm Removal

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-25-footprints-rhythm-removal/`

Decision: implementation and iPhone 17 verification complete; repeat-user validation pending.

Reason: the standalone overview rhythm card duplicated the trend and yearly archive surfaces, so its view, dead helper logic, test, and dedicated strings were removed while those two review paths remain.

## 2026-08-25 · Footprints Trajectory Entry

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-25-footprints-trajectory-entry/`

Decision: implementation and iPhone 17 verification complete; repeat-user validation pending.

Reason: the trend entry now follows the supplied reference with all twelve months, a current-month boundary, a highlighted peak, and an explicit busiest-month count while preserving the existing year archive and detail routes.

## 2026-08-25 · Footprints Trajectory Polish

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-25-footprints-trajectory-polish/`

Decision: implementation and iPhone 17 verification complete; repeat-user validation pending.

Reason: the trajectory card now prioritizes the chart and peak callout with stronger contrast, lighter typography, a visible `全部年份 ›` route, and no redundant subtitle or footer copy.

## 2026-08-25 · Year Detail Stat Trim

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-25-year-detail-stat-trim/`

Decision: implementation and iPhone 17 verification complete; repeat-user validation pending.

Reason: the annual detail header now keeps only the retained “现场时长” metric and removes the lower-value “新艺人” and “新城市” counts without changing the year rhythm, highlight, or show list.

## 2026-08-25 · Artist Footprint Entry

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-25-artist-footprint-entry/`

Decision: implementation and iPhone 17 verification complete; avatar-backed validation pending.

Reason: the artist entry now keeps only its primary title and exposes stored Apple Music/iTunes avatar URLs as a clear circular avatar while preserving the fallback and archive route.

## 2026-08-25 · Persistent Cover Cache

Stage: manual-onboarding

Cycle: `.builder/cycles/2026-08-25-persistent-cover-cache/`

Decision: implementation, regression test, and iPhone 17 cold-launch verification complete.

Reason: previously loaded remote covers now survive process termination in the main App cache, while the existing Widget cover supplies an immediate preview during the first post-change launch.
