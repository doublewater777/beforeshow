# Global Transit ETA Results

2026-07-19 implementation result:

- Public transit now calls MapKit `calculateETA()` with the user's requested arrival time for outbound plans and departure time for return plans.
- ETA results save duration and optional distance without transit steps.
- Transit timelines use a generic travel node and direct users to Apple Maps for lines and transfers.
- ETA failure exposes a manual minute field and keeps plan generation available.
- The saved-plan action opens Apple Maps in public-transit mode.

Verification:

- Focused route tests: 16 tests, 0 failures.
- Full iOS test suite: 167 tests, 0 failures.
- iPhone 17 screenshots:
  - `docs/screenshots/2026-07-19-global-transit-eta-return.png`
  - `docs/screenshots/2026-07-19-global-transit-manual-fallback.png`
- Apple Maps handoff displayed a public-transit itinerary for the seeded return route.

Post-release behavior and user feedback have not been observed yet.
