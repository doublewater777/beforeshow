# Business Model Stage

## Current Summary

Buyer: the same individual music live-goer who uses BeforeShow.

User: people with real upcoming concerts, Livehouse shows, or music festivals who want help entering the show mood and preparing lightly.

Payment trigger: hitting the saved-show limit after experiencing value from adding one real show.

Pricing model: Pro membership through App Store subscriptions at an initial test price of ¥12/month or ¥68/year.

## Evidence

No payment evidence yet. Current evidence is limited to fake-door planning and local prototype readiness.

## Decisions

- Paid value currently attaches only to unlimited saved shows, not to ticketing, social visibility, preparation generators, or public community.
- The first-show experience should remain useful enough to prove the product before asking for payment.
- Free users can save one show.
- Pro unlocks unlimited saved shows.
- Pro has no free trial in V2.1.
- Pro uses App Store subscriptions and purchase restoration without a BeforeShow account.
- The core implementation cycle `.builder/cycles/2026-06-16-core-show-loop/` tests whether the five-feature show loop makes Pro repeat-generation limits understandable.
- The active implementation cycle `.builder/cycles/2026-06-23-home-visual-redesign/` tests whether a theatrical, two-entry home surface improves current-show clarity without hiding the broader tool loop.
- The active implementation cycle `.builder/cycles/2026-07-19-global-transit-eta/` tests whether a globally available transit ETA with an Apple Maps handoff is enough for users to save a useful trip plan without in-app transfer details.
- The active verification cycle `.builder/cycles/2026-07-20-setlist-reliability-verification/` tests whether generated setlist guesses remain trustworthy across streaming, cancellation, festival lineup changes, and editing.
- The active simplification cycle `.builder/cycles/2026-07-23-remove-setlist-guess/` removes setlist guessing after the product owner chose a narrower current-show and countdown focus.
- The active simplification cycle `.builder/cycles/2026-07-23-remove-memory-and-travel/` removes memory fragments, travel planning, and the remaining generation backend.
- The parallel reliability cycle `.builder/cycles/2026-07-23-add-show-flow-reliability/` verifies that adding the first real show produces valid countdown data, one current focus, and working notification follow-through before the Pro save limit is tested.
- The active current-show management cycle `.builder/cycles/2026-07-31-current-show-management/` tests whether one poster-led, phase-driven surface can make adding, opening, preparing for, and explicitly ending the current show understandable without reviving retired standalone tools.
- The active archive cycle `.builder/cycles/2026-08-01-footprints-archive/` tests whether the supplied Current / Footprints split and a personal history of ended shows increase repeat recording.
- The active companion cycle `.builder/cycles/2026-08-02-companion-icon-states/` tests whether one local, phase-aware friend state makes shared attendance legible without requiring accounts or a social feed.
- The active memory-fragments cycle `.builder/cycles/2026-08-03-current-show-memory-fragments/` explicitly revisits the July retirement decision with a narrower current-show-only, private local timeline; it tests whether low-friction capture adds emotional value without reopening history, social, cloud, or AI scope.
- The ticket/timetable assets cycle `.builder/cycles/2026-08-04-ticket-timetable-assets/` tests whether a private, show-bound visual reference adds preparation value without being mistaken for official ticket validation or reopening cloud scope.

## Open Questions

- Whether payment increases or reduces core preparation behavior.
- Whether ¥12/month and ¥68/year are the right initial prices.
- Whether the one-show free limit hurts first-show activation.

## Gate

Not passed. Payment is an explicit hypothesis to test after the membership package and price are defined.
