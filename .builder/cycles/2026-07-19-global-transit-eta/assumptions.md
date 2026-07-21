# Global Transit ETA Assumptions

- Users mainly need a reliable leave/arrival time inside BeforeShow; detailed transit navigation can happen in Apple Maps.
- Apple Maps handoff is an acceptable global iOS baseline.
- A manual duration fallback is preferable to blocking plan creation when transit ETA is unavailable.
- Users will understand that the generic transit timeline is an estimate, not a reproduced transfer itinerary.

Riskiest assumption: users still consider the saved plan useful when detailed public-transit steps live in Apple Maps rather than BeforeShow.

Falsification: users repeatedly abandon transit planning, request station-level details in BeforeShow, or avoid opening the map action.

Existing evidence: MapKit returned `directionsNotFound` for transit `calculate()` while the same request succeeded with `calculateETA()` and in the system Maps app.
